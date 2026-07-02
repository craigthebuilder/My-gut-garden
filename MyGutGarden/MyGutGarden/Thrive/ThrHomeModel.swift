//
//  ThrHomeModel.swift
//  MyGutGarden, Module C: load + shape the Thrive home dashboard (SPEC §10,
//  §11a). Best-effort loads against the RLS-scoped Repository; every fetch is
//  guarded so a partial/offline backend degrades to a clean empty state that
//  invites action rather than erroring (DESIGN.md "Writing").
//

import SwiftUI
import Observation

@MainActor
@Observable
final class ThrHomeModel {
    // Surfaced goal (the ONLY anthropometric-derived number shown, §10 / rule #6).
    var fiberGoalG: Int?
    var fiberConsumedTodayG: Double = 0

    // Weekly plant variety toward 30 (presence-based, Sunday reset, §8/§13).
    var uniquePlantsThisWeek = 0
    var weekly30Streak = 0
    var bestWeekCount = 0

    // 3 P's + rainbow as relative amounts today (Batch D, coarse tiers only).
    var todayThreePs = ThrThreePAmounts()
    var rainbowAmounts = ThrRainbowAmounts()

    // Recent meals (last 5 days) + this week's per-color amounts (weekly chart).
    var recentMeals: [MealRow] = []
    var weeklyColorAmounts: [WeeklyColorAmountRow] = []

    // Variable reward + rainbow education content.
    var curiosity: ThrCuriosityFactRow?
    var recipeSuggestion: RecipeRow?
    private var allRecipes: [RecipeRow] = []
    var colorEducation: [String: ThrColorEducation] = ThrRainbowContent.fallback
    var colorExampleFoods: [String: [String]] = [:]

    // Today's optional mood tap (Thrive keeps tracking burden to one tap, §12).
    var loggedMoodToday = false

    var isLoaded = false

    private let target = GameConfig.shared.weeklyPlantTarget

    var fiberFraction: Double {
        guard let goal = fiberGoalG, goal > 0 else { return 0 }
        return min(1, fiberConsumedTodayG / Double(goal))
    }

    /// The goal surfaces ONLY once the week-one baseline quest unlocks it
    /// (SPEC §10 / Fence 5) — a stale `fiber_goal_g` while the state is still
    /// `baseline_pending` must never show.
    static func surfacedGoal(_ profile: UserProfile?) -> Int? {
        guard let profile, profile.fiberGoalState == "unlocked" else { return nil }
        return profile.fiberGoalG
    }
    var plantsRemaining: Int { max(0, target - uniquePlantsThisWeek) }
    var plantFraction: Double { min(1, Double(uniquePlantsThisWeek) / Double(target)) }

    /// Load from the latest meal first (works fully offline), then enrich from
    /// the backend if a session is available.
    func load(appState: AppState, latestMeal: ConfirmedMeal?) async {
        applyLatestMeal(latestMeal)

        guard let repo = appState.repository else {
            fiberGoalG = Self.surfacedGoal(appState.profile)
            isLoaded = true
            return
        }

        var profile = appState.profile
        if profile == nil { profile = (try? await repo.fetchProfile()) ?? nil }
        fiberGoalG = Self.surfacedGoal(profile)

        await loadWeeklyVariety(repo)
        await loadWeeklyPlantsLive(repo)        // live count so a fresh snap shows up now
        await loadCuriosity(repo)
        await loadColorEducation(repo)
        await loadTodayCheckin(repo, userId: profile?.id)
        await loadTodayMealItems(repo)
        await loadRecentMeals(repo)
        await loadWeeklyColors(repo, userId: profile?.id)
        await loadRecipeSuggestion(repo)

        isLoaded = true
    }

    /// Recent weeks of one color's max amount (oldest → newest) for the tap-in
    /// weekly chart. Reads `weekly_color_amounts` already loaded by `load`.
    func weeklyAmounts(for group: ThrRainbowGroup, weeks: Int = 8) -> [ThrColorAmount] {
        let rows = weeklyColorAmounts
            .filter { $0.colorId == group.rawValue }
            .sorted { $0.weekStart < $1.weekStart }
            .suffix(weeks)
        return rows.map { ThrColorAmount(tier: PortionTier(rawValue: $0.maxTier)) }
    }

    func exampleFoods(for group: ThrRainbowGroup) -> [String] {
        colorExampleFoods[group.rawValue] ?? []
    }

    // MARK: - Pieces

    /// The latest snap (works fully offline) seeds today's 3 P's + rainbow with
    /// real coarse tiers from the meal; the DB read below merges the rest of today.
    private func applyLatestMeal(_ latestMeal: ConfirmedMeal?) {
        guard let meal = latestMeal else { return }
        for item in meal.response.items {
            guard let attrs = item.attributes else { continue }
            let amount = ThrColorAmount(tier: item.vision.portionTier)
            for color in attrs.colors { rainbowAmounts.mark(color, amount) }
            if !attrs.fibers.isEmpty || !attrs.guildFeeds.isEmpty {
                todayThreePs.prebiotic = max(todayThreePs.prebiotic, amount)
            }
            if attrs.isFermented {
                todayThreePs.probiotic = max(todayThreePs.probiotic, amount)
            }
            if attrs.phytochemicals.contains(where: { $0.category == "polyphenol" }) || attrs.colors.contains("blue_purple") {
                todayThreePs.polyphenol = max(todayThreePs.polyphenol, amount)
            }
        }
    }

    private func loadWeeklyVariety(_ repo: Repository) async {
        guard let rows: [WeeklySummaryRow] = try? await repo.select(
            "weekly_summaries", order: "week_start.desc", limit: 26
        ) else { return }

        let thisMonday = ThrDates.dateString(ThrDates.currentMonday())
        bestWeekCount = rows.map(\.uniquePlantCount).max() ?? 0

        // Current in-progress week (if present) drives the "X/30" indicator but
        // is excluded from the streak count (it hasn't had its chance to close).
        var completed = rows
        if let first = rows.first, first.weekStart == thisMonday {
            uniquePlantsThisWeek = first.uniquePlantCount
            completed = Array(rows.dropFirst())
        }
        weekly30Streak = ThrIngestor.consecutiveWeeklyHits(mostRecentFirst: completed.map(\.hit30))
    }

    /// `weekly_summaries` is computed server-side and lags a fresh snap, so the
    /// "X / 30 plants" hero would look frozen right after logging. Recompute this
    /// week's distinct plant foods live from the week's meals and keep the larger
    /// of the two, so the number moves immediately and never regresses (R3 Batch A).
    private func loadWeeklyPlantsLive(_ repo: Repository) async {
        let since = ThrDates.timestampString(ThrDates.currentMonday())
        guard let meals: [MealRow] = try? await repo.select(
            "meals", columns: "id,photo_url,captured_at,confirmed,user_annotation",
            filters: ["captured_at": "gte.\(since)", "confirmed": "eq.true"]
        ), !meals.isEmpty else { return }
        let mealList = "(" + meals.map(\.id).joined(separator: ",") + ")"
        guard let items: [ThrMealItemTierRow] = try? await repo.select(
            "meal_items", columns: "food_id,portion_tier,est_fiber_g", filters: ["meal_id": "in.\(mealList)"]
        ), !items.isEmpty else { return }
        let foodList = "(" + Set(items.map(\.foodId)).joined(separator: ",") + ")"
        guard let foods: [ThrFoodNameRow] = try? await repo.select(
            "foods", columns: "id,canonical_name", filters: ["id": "in.\(foodList)"]
        ) else { return }
        let plantNames = Set(((try? await repo.fetchPlants()) ?? []).map { $0.name.lowercased() })
        let distinct = Set(foods.map { $0.canonicalName.lowercased() }.filter { plantNames.contains($0) })
        uniquePlantsThisWeek = max(uniquePlantsThisWeek, distinct.count)
    }

    // Tiny decode rows for the 3 P's DB computation.
    private struct ThrFoodIdRow: Decodable, Sendable { let foodId: String }
    private struct ThrIdRow: Decodable, Sendable { let id: String }

    private func loadCuriosity(_ repo: Repository) async {
        if let facts: [ThrCuriosityFactRow] = try? await repo.select("curiosity_facts", limit: 50) {
            curiosity = facts.randomElement()
        }
    }

    private func loadColorEducation(_ repo: Repository) async {
        guard let rows: [ThrColorRow] = try? await repo.select("colors") else { return }
        for row in rows {
            colorEducation[row.id] = ThrColorEducation(
                meaning: row.meaningCopy ?? colorEducation[row.id]?.meaning ?? "",
                whatItDoes: row.whatItDoesCopy ?? colorEducation[row.id]?.whatItDoes ?? "",
                deficiency: row.deficiencyCopy ?? colorEducation[row.id]?.deficiency ?? ""
            )
            if let examples = row.exampleFoods, !examples.isEmpty { colorExampleFoods[row.id] = examples }
        }
    }

    /// A curated "try this" recipe, preferring one that covers a rainbow colour the
    /// user is missing this week (gap-driven, SPEC §14). Curated data, never generated.
    private func loadRecipeSuggestion(_ repo: Repository) async {
        allRecipes = (try? await repo.select("recipes")) ?? []
        guard !allRecipes.isEmpty else { return }
        let missing = Set(rainbowAmounts.missing.map(\.rawValue))
        recipeSuggestion = allRecipes.first { !Set($0.colorIds).isDisjoint(with: missing) } ?? allRecipes.randomElement()
    }

    /// "Refresh": a fresh random pick from the curated library (never the one
    /// already showing when there's a choice).
    func shuffleRecipe() {
        let pool = allRecipes.filter { $0.id != recipeSuggestion?.id }
        recipeSuggestion = (pool.isEmpty ? allRecipes : pool).randomElement() ?? recipeSuggestion
    }

    /// "Optimize": the curated recipe covering the MOST of today's rainbow gaps
    /// (the deterministic proxy for diversity + phytonutrient coverage — colors
    /// carry the phytochemicals). Random among the equally-best so it stays fresh.
    func optimizeRecipe() {
        guard !allRecipes.isEmpty else { return }
        let missing = Set(rainbowAmounts.missing.map(\.rawValue))
        guard !missing.isEmpty else { shuffleRecipe(); return }
        let scored = allRecipes.map { ($0, Set($0.colorIds).intersection(missing).count) }
        let best = scored.map(\.1).max() ?? 0
        recipeSuggestion = scored.filter { $0.1 == best }.map(\.0).randomElement() ?? recipeSuggestion
    }

    private func loadTodayCheckin(_ repo: Repository, userId: String?) async {
        struct IdRow: Decodable { let id: String }
        guard let userId else { return }
        let today = ThrDates.dateString()
        let rows: [IdRow] = (try? await repo.select(
            "check_ins", columns: "id",
            filters: ["user_id": "eq.\(userId)", "log_date": "eq.\(today)"], limit: 1)) ?? []
        loggedMoodToday = !rows.isEmpty
    }

    /// Today's coarse/directional fiber sum AND per-color rainbow amount, from
    /// `meal_items` joined to `food_colors` in Swift (two cheap reads each; no
    /// fragile embedded join). Errors leave the running totals where they are.
    private func loadTodayMealItems(_ repo: Repository) async {
        let since = ThrDates.timestampString(ThrDates.startOfToday())
        guard let meals: [MealRow] = try? await repo.select(
            "meals", columns: "id,photo_url,captured_at,confirmed,user_annotation",
            filters: ["captured_at": "gte.\(since)", "confirmed": "eq.true"]
        ), !meals.isEmpty else { return }

        let mealList = "(" + meals.map(\.id).joined(separator: ",") + ")"
        guard let items: [ThrMealItemTierRow] = try? await repo.select(
            "meal_items", columns: "food_id,portion_tier,est_fiber_g", filters: ["meal_id": "in.\(mealList)"]
        ), !items.isEmpty else { return }

        fiberConsumedTodayG = items.compactMap(\.estFiberG).reduce(0, +)

        // Highest coarse tier per food today, then fan each food out to its colors.
        var tierByFood: [String: PortionTier] = [:]
        for item in items {
            guard let tier = PortionTier(rawValue: item.portionTier) else { continue }
            if let existing = tierByFood[item.foodId], existing.amountRank >= tier.amountRank { continue }
            tierByFood[item.foodId] = tier
        }
        let foodList = "(" + tierByFood.keys.joined(separator: ",") + ")"
        guard let colors: [ThrFoodColorRow] = try? await repo.select(
            "food_colors", columns: "food_id,color_id", filters: ["food_id": "in.\(foodList)"]
        ) else { return }
        for fc in colors {
            guard let tier = tierByFood[fc.foodId] else { continue }
            rainbowAmounts.mark(fc.colorId, tier: tier)
        }

        // The 3 P's from the DB too, so they update on the Today tab (latestMeal nil),
        // not only on the post-snap path. Same dual-path gap that hit "30 plants".
        await markThreePsFromDB(repo, tierByFood: tierByFood,
                                bluePurpleFoods: Set(colors.filter { $0.colorId == "blue_purple" }.map(\.foodId)))
    }

    /// Prebiotic = a food with fiber or a guild feed; Probiotic = a fermented food;
    /// Polyphenol = a polyphenol-class phytochemical or a blue/purple color. Mirrors
    /// applyLatestMeal so the offline and DB paths agree.
    private func markThreePsFromDB(_ repo: Repository, tierByFood: [String: PortionTier],
                                   bluePurpleFoods: Set<String>) async {
        let ids = Array(tierByFood.keys)
        guard !ids.isEmpty else { return }
        let list = "(" + ids.joined(separator: ",") + ")"
        async let fibers: [ThrFoodIdRow]   = (try? await repo.select("food_fibers", columns: "food_id", filters: ["food_id": "in.\(list)"])) ?? []
        async let guilds: [ThrFoodIdRow]   = (try? await repo.select("food_guild_feeds", columns: "food_id", filters: ["food_id": "in.\(list)"])) ?? []
        async let ferments: [ThrIdRow]     = (try? await repo.select("foods", columns: "id", filters: ["id": "in.\(list)", "is_fermented": "eq.true"])) ?? []
        async let polyIds: [ThrIdRow]      = (try? await repo.select("phytochemicals", columns: "id", filters: ["class": "eq.polyphenol"])) ?? []
        async let foodPhytos: [ThrFoodPhytoRow] = (try? await repo.select("food_phytochemicals", columns: "food_id,phytochemical_id", filters: ["food_id": "in.\(list)"])) ?? []
        let (fib, gld, frm, ply, fph) = await (fibers, guilds, ferments, polyIds, foodPhytos)

        let prebioticFoods = Set(fib.map(\.foodId)).union(gld.map(\.foodId))
        let probioticFoods = Set(frm.map(\.id))
        let polySet = Set(ply.map(\.id))
        let polyphenolFoods = Set(fph.filter { polySet.contains($0.phytochemicalId) }.map(\.foodId)).union(bluePurpleFoods)

        for (foodId, tier) in tierByFood {
            let amt = ThrColorAmount(tier: tier)
            if prebioticFoods.contains(foodId)  { todayThreePs.prebiotic = max(todayThreePs.prebiotic, amt) }
            if probioticFoods.contains(foodId)  { todayThreePs.probiotic = max(todayThreePs.probiotic, amt) }
            if polyphenolFoods.contains(foodId) { todayThreePs.polyphenol = max(todayThreePs.polyphenol, amt) }
        }
    }

    /// Last 5 days of confirmed meals for the Recent-Meals rail. A nil photo_url
    /// (e.g. a never-photographed manual meal) renders a neutral placeholder.
    private func loadRecentMeals(_ repo: Repository) async {
        let since = ThrDates.timestampString(
            Calendar.current.date(byAdding: .day, value: -5, to: ThrDates.startOfToday()) ?? ThrDates.startOfToday()
        )
        if let meals: [MealRow] = try? await repo.select(
            "meals", columns: "id,photo_url,captured_at,confirmed,user_annotation",
            filters: ["captured_at": "gte.\(since)", "confirmed": "eq.true"],
            order: "captured_at.desc", limit: 20
        ) {
            recentMeals = meals
        }
    }

    /// This + recent weeks of per-color amounts for the rainbow tap-in chart.
    private func loadWeeklyColors(_ repo: Repository, userId: String?) async {
        guard let userId else { return }
        if let rows: [WeeklyColorAmountRow] = try? await repo.select(
            "weekly_color_amounts", filters: ["user_id": "eq.\(userId)"],
            order: "week_start.desc", limit: 60
        ) {
            weeklyColorAmounts = rows
        }
    }
}
