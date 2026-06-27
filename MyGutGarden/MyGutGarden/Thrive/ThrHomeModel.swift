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
    var plantsRemaining: Int { max(0, target - uniquePlantsThisWeek) }
    var plantFraction: Double { min(1, Double(uniquePlantsThisWeek) / Double(target)) }

    /// Load from the latest meal first (works fully offline), then enrich from
    /// the backend if a session is available.
    func load(appState: AppState, latestMeal: ConfirmedMeal?) async {
        applyLatestMeal(latestMeal)

        guard let repo = appState.repository else {
            fiberGoalG = appState.profile?.fiberGoalG
            isLoaded = true
            return
        }

        var profile = appState.profile
        if profile == nil { profile = (try? await repo.fetchProfile()) ?? nil }
        fiberGoalG = profile?.fiberGoalG

        await loadWeeklyVariety(repo)
        await loadWeeklyPlantsLive(repo)        // live count so a fresh snap shows up now
        await loadCuriosity(repo)
        await loadColorEducation(repo)
        await loadTodayCheckin(repo, userId: profile?.id)
        await loadTodayMealItems(repo)
        await loadRecentMeals(repo)
        await loadWeeklyColors(repo, userId: profile?.id)

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
        for item in meal.response.items where item.silentlyOmitted != true {
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
            "meals", columns: "id,mode,photo_url,captured_at,confirmed,user_annotation,photo_expires_at",
            filters: ["captured_at": "gte.\(since)", "mode": "eq.thrive", "confirmed": "eq.true"]
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

    private func loadTodayCheckin(_ repo: Repository, userId: String?) async {
        guard let userId else { return }
        let today = ThrDates.dateString()
        if let rows: [ThriveCheckinRow] = try? await repo.select(
            "thrive_checkins", filters: ["user_id": "eq.\(userId)", "log_date": "eq.\(today)"], limit: 1
        ), let row = rows.first {
            loggedMoodToday = row.mood != nil || row.energy != nil || row.clarity != nil
        }
    }

    /// Today's coarse/directional fiber sum AND per-color rainbow amount, from
    /// `meal_items` joined to `food_colors` in Swift (two cheap reads each; no
    /// fragile embedded join). Errors leave the running totals where they are.
    private func loadTodayMealItems(_ repo: Repository) async {
        let since = ThrDates.timestampString(ThrDates.startOfToday())
        guard let meals: [MealRow] = try? await repo.select(
            "meals", columns: "id,mode,photo_url,captured_at,confirmed,user_annotation,photo_expires_at",
            filters: ["captured_at": "gte.\(since)", "mode": "eq.thrive", "confirmed": "eq.true"]
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
    }

    /// Last 5 days of confirmed Thrive meals for the Recent-Meals rail. Photos are
    /// nulled server-side after 5 days; the card renders a placeholder for nil.
    private func loadRecentMeals(_ repo: Repository) async {
        let since = ThrDates.timestampString(
            Calendar.current.date(byAdding: .day, value: -5, to: ThrDates.startOfToday()) ?? ThrDates.startOfToday()
        )
        if let meals: [MealRow] = try? await repo.select(
            "meals", columns: "id,mode,photo_url,captured_at,confirmed,user_annotation,photo_expires_at",
            filters: ["captured_at": "gte.\(since)", "mode": "eq.thrive", "confirmed": "eq.true"],
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
