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
        // never auto-applies here.
    }
}

/// Tiny row for counting logged meals.
struct MealIdRow: Decodable, Sendable { let id: String }
