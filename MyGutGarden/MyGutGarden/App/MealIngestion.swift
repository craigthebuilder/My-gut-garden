//
//  MealIngestion.swift
//  MyGutGarden, the consolidation coordinator (orchestrator-owned). The SOLE
//  writer of meal-derived per-user state: it takes a confirmed meal, calls each
//  module's PURE ingestion function (C's plants, D's guild feeding), owns the
//  decay-then-add `guild_state` write, the lifetime plant collection, and the
//  §13 progression (Tier-2 + sequential district unlocks), and emits the Thrive
//  celebration events. Modules compute; this persists.
//

import Foundation

@MainActor
struct MealIngestion {
    let repository: Repository
    let appState: AppState

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    // MARK: - Entry point (called by Capture after a meal is confirmed)

    func ingest(_ meal: ConfirmedMeal) async {
        let context = MealContext.from(meal.response, loggedAt: meal.capturedAt)
        guard !context.items.isEmpty else { return }
        guard let userId = appState.profile?.id else { return }

        await ingestPlants(context, userId: userId)
        await ingestGuilds(context, userId: userId, at: meal.capturedAt)
        await recomputeProgression(userId: userId)
    }

    // MARK: - Plant collection (lifetime, presence-based, C's pure plantNames)

    private func ingestPlants(_ context: MealContext, userId: String) async {
        let names = ThrIngestor().plantNames(for: context)
        guard !names.isEmpty else { return }
        let plants = (try? await repository.fetchPlants()) ?? []
        let idByName = Dictionary(plants.map { ($0.name.lowercased(), $0.id) }, uniquingKeysWith: { a, _ in a })
        for name in names {
            guard let plantId = idByName[name.lowercased()] else { continue }
            // ignoreDuplicates → first_logged_at stays the lifetime first (§13).
            try? await repository.upsert("user_plant_collection", [
                "user_id": .string(userId),
                "plant_id": .string(plantId),
                "first_logged_at": .date(context.loggedAt),
            ], onConflict: "user_id,plant_id", ignoreDuplicates: true)
        }
    }

    // MARK: - Guild feeding (D's pure points → decay-then-add via GuildBloom)

    private func ingestGuilds(_ context: MealContext, userId: String, at feedingDate: Date) async {
        let points = GuildIngestor().guildFeedingPoints(for: context)
        guard !points.isEmpty else { return }
        let guilds = (try? await repository.fetchGuilds()) ?? []
        let idByInternal = Dictionary(guilds.map { ($0.internalName, $0.id) }, uniquingKeysWith: { a, _ in a })
        let nameByInternal = Dictionary(guilds.map { ($0.internalName, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let states = (try? await repository.select("guild_state") as [GuildStateRow]) ?? []
        let stateByGuild = Dictionary(states.map { ($0.guildId, $0) }, uniquingKeysWith: { a, _ in a })

        for (internalName, pts) in points {
            guard let guildId = idByInternal[internalName] else { continue }
            let row = stateByGuild[guildId]
            let outcome = GuildBloom.applyFeeding(
                storedScore: Double(row?.nourishmentScore ?? 0),
                lastFedAt: Self.parse(row?.lastFedAt),
                daysFedThisWeek: row?.daysFedThisWeek ?? 0,
                points: pts,
                at: feedingDate
            )
            let everBloomed = (row?.hasEverBloomed ?? false) || outcome.crossedIntoBlooming || outcome.state == .blooming
            try? await repository.upsert("guild_state", [
                "user_id": .string(userId),
                "guild_id": .string(guildId),
                "nourishment_score": .int(Int(outcome.score.rounded())),
                "bloom_state": .string(outcome.state.rawValue),
                "last_fed_at": .date(feedingDate),
                "days_fed_this_week": .int(outcome.daysFedThisWeek),
                "has_ever_bloomed": .bool(everBloomed),
            ], onConflict: "user_id,guild_id")

            if outcome.crossedIntoBlooming, let name = nameByInternal[internalName] {
                appState.celebrate(.guildBloom(displayName: name))
            }
        }
    }

    // MARK: - Progression (Tier-2 + sequential district unlocks, §13)

    /// Recompute and publish progression. Safe to call standalone (e.g. on app
    /// launch) as well as after a meal.
    func recomputeProgression(userId: String) async {
        // Maintain this week's `weekly_summaries` row first (nothing else writes
        // it — streaks, hit-30 history, and the Tier-2 gate all read it), then
        // run the week-one fiber unlock off the same snapshot.
        let goal = await goalRow()
        if let snapshot = await currentWeekSnapshot() {
            await refreshWeeklySummary(userId: userId, snapshot: snapshot, goalG: goal?.fiberGoalG)
            await maybeUnlockFiberGoal(userId: userId, goal: goal, snapshot: snapshot)
        }
        let guilds = (try? await repository.fetchGuilds()) ?? []
        let districts = (try? await repository.fetchDistricts()) ?? []
        let orderByDistrictId = Dictionary(districts.map { ($0.id, $0.order) }, uniquingKeysWith: { a, _ in a })
        let districtOrderByGuild = Dictionary(
            guilds.compactMap { g in orderByDistrictId[g.districtId].map { (g.id, $0) } },
            uniquingKeysWith: { a, _ in a }
        )
        let states = (try? await repository.select("guild_state") as [GuildStateRow]) ?? []

        let snapshots = states.compactMap { row -> GuildBloomSnapshot? in
            guard let order = districtOrderByGuild[row.guildId] else { return nil }
            let blooming = GuildBloom.currentState(
                storedScore: Double(row.nourishmentScore),
                lastFedAt: Self.parse(row.lastFedAt), asOf: Date()
            ) == .blooming
            return GuildBloomSnapshot(districtOrder: order, isBlooming: blooming, hasEverBloomed: row.hasEverBloomed)
        }

        // Tier-2 gate (§13): first full week, hit 30 once OR logged ≥5 days.
        // (Approximation: distinct logged days ≈ meal count; exact daily counters
        // are a follow-up, see consolidation notes.)
        let summaries = (try? await repository.select("weekly_summaries") as [WeeklySummaryRow]) ?? []
        let mealIds = (try? await repository.select("meals", columns: "id") as [MealIdRow]) ?? []
        let loggedDays = mealIds.count
        let isTier2 = summaries.contains(where: \.hit30) || loggedDays >= GameConfig.shared.tier2MinLoggedDaysFirstWeek
        let cumulativeTier2Days = isTier2 ? max(loggedDays, GameConfig.shared.tier2MinLoggedDaysFirstWeek) : 0

        var unlocked = Set<Int>()
        if isTier2 {
            unlocked = GuildIngestor().unlockedDistrictOrders(snapshots: snapshots, cumulativeTier2Days: cumulativeTier2Days)
            // Persist + celebrate any newly opened districts.
            let previously = appState.progression.unlockedDistrictOrders
            for order in unlocked {
                guard let district = districts.first(where: { $0.order == order }) else { continue }
                try? await repository.upsert("user_districts", [
                    "user_id": .string(userId),
                    "district_id": .string(district.id),
                    "unlocked_at": .date(Date()),
                ], onConflict: "user_id,district_id", ignoreDuplicates: true)
                if !previously.contains(order) {
                    appState.celebrate(.districtUnlock(name: district.name))
                }
            }
        }
        appState.updateProgression(ProgressionState(
            isTier2Unlocked: isTier2,
            unlockedDistrictOrders: unlocked,
            cumulativeTier2Days: cumulativeTier2Days
        ))
        // Fiber-goal titration is owned by the guardian engine (SPEC §11, Phase 1F):
        // it reads check-ins + fiber load and OFFERS an increase (Accept/Decline),
        // never auto-applies here. The one-time week-one UNLOCK runs above, off
        // the same weekly snapshot that feeds `weekly_summaries`.
    }

    // MARK: - This week's snapshot (feeds weekly_summaries + the fiber unlock)

    private struct GoalRow: Decodable {
        let fiberGoalState: String
        let fiberTargetG: Int?
        let fiberGoalG: Int?
    }

    private struct WeekSnapshot {
        let weekStart: String              // yyyy-MM-dd Monday (weekly_summaries.week_start)
        let distinctPlantCount: Int
        let fiberByDay: [String: Double]   // coarse/directional Σ est_fiber_g per logged day
    }

    private func goalRow() async -> GoalRow? {
        let rows: [GoalRow] = (try? await repository.select(
            "users", columns: "fiber_goal_state,fiber_target_g,fiber_goal_g")) ?? []
        return rows.first
    }

    /// This weekly window's confirmed meals → distinct plant foods (mirrors the
    /// Today hero count) + per-day directional fiber. nil when nothing is logged.
    private func currentWeekSnapshot() async -> WeekSnapshot? {
        let monday = ThrDates.currentMonday()
        let since = ThrDates.timestampString(monday)
        guard let meals: [MealRow] = try? await repository.select(
            "meals", columns: "id,photo_url,captured_at,confirmed,user_annotation",
            filters: ["captured_at": "gte.\(since)", "confirmed": "eq.true"]
        ), !meals.isEmpty else { return nil }
        let mealList = "(" + meals.map(\.id).joined(separator: ",") + ")"
        guard let items: [GuardianMealItemRow] = try? await repository.select(
            "meal_items", filters: ["meal_id": "in.\(mealList)"]), !items.isEmpty else { return nil }
        let foodList = "(" + Set(items.map(\.foodId)).joined(separator: ",") + ")"
        let foods: [ThrFoodNameRow] = (try? await repository.select(
            "foods", columns: "id,canonical_name", filters: ["id": "in.\(foodList)"])) ?? []
        let plantNames = Set(((try? await repository.fetchPlants()) ?? []).map { $0.name.lowercased() })
        let plantFoodIds = Set(foods.filter { plantNames.contains($0.canonicalName.lowercased()) }.map(\.id))
        let distinctPlantNames = Set(foods.filter { plantFoodIds.contains($0.id) }
            .map { $0.canonicalName.lowercased() })

        let dayByMeal = Dictionary(meals.map { ($0.id, String($0.capturedAt.prefix(10))) },
                                   uniquingKeysWith: { a, _ in a })
        var fiberByDay: [String: Double] = [:]
        for item in items {
            guard let day = dayByMeal[item.mealId] else { continue }
            fiberByDay[day, default: 0] += item.estFiberG ?? 0
        }

        return WeekSnapshot(weekStart: ThrDates.dateString(monday),
                            distinctPlantCount: distinctPlantNames.count,
                            fiberByDay: fiberByDay)
    }

    /// The SOLE writer of `weekly_summaries` (streaks, best week, hit-30 history,
    /// and the Tier-2 gate all read it; before this nothing populated it).
    private func refreshWeeklySummary(userId: String, snapshot: WeekSnapshot, goalG: Int?) async {
        let hit30 = snapshot.distinctPlantCount >= GameConfig.shared.weeklyPlantTarget
        let fiberDaysMet = goalG.map { g in
            snapshot.fiberByDay.values.filter { $0 >= Double(g) }.count
        } ?? 0
        try? await repository.upsert("weekly_summaries", [
            "user_id": .string(userId),
            "week_start": .string(snapshot.weekStart),
            "unique_plant_count": .int(snapshot.distinctPlantCount),
            "hit_30": .bool(hit30),
            "fiber_days_met": .int(fiberDaysMet),
        ], onConflict: "user_id,week_start")
    }

    // MARK: - Week-one fiber-goal unlock (SPEC §10; Fence 2)

    /// Completing the baseline quest (30 distinct plant foods within the weekly
    /// window, `GameConfig.fiberBaselineQuestPlants`) sets
    /// `fiber_goal_state = 'unlocked'` and surfaces the FIRST `fiber_goal_g` — a
    /// comfortable starting point informed by the observed baseline, never the
    /// full target on day one (SPEC §10). Idempotent: only fires while the state
    /// is still 'baseline_pending'.
    private func maybeUnlockFiberGoal(userId: String, goal: GoalRow?, snapshot: WeekSnapshot) async {
        guard goal?.fiberGoalState == "baseline_pending",
              snapshot.distinctPlantCount >= GameConfig.shared.fiberBaselineQuestPlants else { return }

        let startingGoal = GuardianEngine.initialFiberGoal(
            observedDailyFiberG: Array(snapshot.fiberByDay.values),
            targetG: goal?.fiberTargetG)
        try? await repository.update("users", set: [
            "fiber_goal_g": .int(startingGoal),
            "fiber_goal_state": .string("unlocked"),
            "fiber_goal_unlocked_at": .date(Date()),
        ], filters: ["id": "eq.\(userId)"])
        await appState.refreshProfile()
        appState.celebrate(.fiberGoalUnlocked(goalG: startingGoal))
    }
}

/// Tiny row for counting logged meals.
struct MealIdRow: Decodable, Sendable { let id: String }
