//
//  GuardianRunner.swift
//  MyGutGarden — the guardian's IO layer. Fetches the user's recent signals
//  (check-ins, meals, food flags), aggregates them into the pure engine's inputs,
//  runs GuardianEngine.decide, and surfaces AT MOST ONE calm prompt. Called on
//  launch and after a check-in. Never surfaces when a prompt is already pending.
//

import Foundation

@MainActor
struct GuardianRunner {
    let repository: Repository
    let appState: AppState

    private static let windowDays = 14

    func run(userId: String, asOf: Date = Date()) async {
        guard appState.pendingGuardianPrompt == nil else { return }

        // Goal state + the §17 comfort dial + balance cooldown (one users read).
        let profile = await profileState()
        let goal = profile.goal
        let comfort = profile.comfort

        // Recent check-ins define the days we can reason over (comfort must be reported).
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: asOf) ?? asOf
        let cutoffDay = Self.dayString(cutoff)
        let checkIns: [CheckInRow] = (try? await repository.select(
            "check_ins", filters: ["log_date": "gte.\(cutoffDay)"], order: "log_date")) ?? []
        guard !checkIns.isEmpty else { return }

        let dayByCheckIn = Dictionary(checkIns.map { ($0.id, $0.logDate) }, uniquingKeysWith: { a, _ in a })
        let entries: [CheckInEntryRow] = (try? await repository.select(
            "check_in_entries",
            filters: ["check_in_id": "in.(\(checkIns.map(\.id).joined(separator: ",")))"])) ?? []

        // Meals in the window → per-day fiber load + heavy foods.
        let meals: [MealRow] = (try? await repository.select(
            "meals", filters: ["captured_at": "gte.\(cutoffDay)"])) ?? []
        let mealDay = Dictionary(meals.map { ($0.id, Self.dayString(Self.parseISO($0.capturedAt) ?? asOf)) },
                                 uniquingKeysWith: { a, _ in a })
        let items: [GuardianMealItemRow] = meals.isEmpty ? [] : (try? await repository.select(
            "meal_items",
            filters: ["meal_id": "in.(\(meals.map(\.id).joined(separator: ",")))"])) ?? []

        // Food flags + names (for prompt copy + attribution) + serving anchors.
        let flagRows = (try? await repository.fetchFoodFlags()) ?? []
        let foodRef = await foodRefLookup()
        let foodNames = foodRef.names
        let flags: [GuardianFlag] = flagRows.compactMap { row in
            guard let fid = row.foodId, let tier = FlagTier(rawValue: row.flagTier) else { return nil }
            return GuardianFlag(foodId: fid, foodName: foodNames[fid] ?? "this food", tier: tier)
        }

        // §17 inputs: fast-fermenting grams per food + coarse balance tiers.
        let fastGramsByFood = await fastFermentGramsByFood()
        let days = Self.buildDays(checkIns: checkIns, dayByCheckIn: dayByCheckIn, entries: entries,
                                  items: items, mealDay: mealDay, fastGramsByFood: fastGramsByFood,
                                  typicalServingByFood: foodRef.servingG)
        let balanceSignals = await balanceSignals(items: items, mealDay: mealDay,
                                                  typicalServingByFood: foodRef.servingG,
                                                  promptedAt: profile.balancePromptedAt, asOf: asOf)

        let decision = GuardianEngine.decide(goal: goal, days: days, flags: flags,
                                             foodNames: foodNames, comfort: comfort,
                                             balanceSignals: balanceSignals)
        if let prompt = decision.prompt {
            // A balance prompt is informational; stamp the cooldown as it surfaces
            // so it never nags (SPEC §17).
            if case .balance = prompt {
                try? await repository.update("users",
                    set: ["balance_prompted_at": .date(asOf)], filters: ["id": "eq.\(userId)"])
            }
            appState.guardianPrompt(prompt)
        }
    }

    // MARK: - Aggregation (pure)

    static func buildDays(checkIns: [CheckInRow], dayByCheckIn: [String: String],
                          entries: [CheckInEntryRow], items: [GuardianMealItemRow],
                          mealDay: [String: String],
                          fastGramsByFood: [String: Double] = [:],
                          typicalServingByFood: [String: Double] = [:]) -> [GuardianDay] {
        // Symptom section keys whose value_int is a coarse 0–3 severity.
        let symptomKeys: Set<String> = ["felt_okay", "gas", "bloating", "cramping", "pain", "urgency"]
        let cfg = GameConfig.shared

        // Per-day symptom max + confounder presence, from the check-in entries.
        var discomfort: [String: Int] = [:]
        var confounder: [String: Bool] = [:]
        for e in entries {
            guard let day = dayByCheckIn[e.checkInId] else { continue }
            if e.sectionKey == "context" { confounder[day] = true }
            else if symptomKeys.contains(e.sectionKey), let v = e.valueInt {
                discomfort[day] = max(discomfort[day] ?? 0, v)
            }
        }

        // Per-day fiber load + heavy foods + fast-fermenting load (§17).
        var fiber: [String: Double] = [:]
        var fastFiber: [String: Double] = [:]
        var heavy: [String: Set<String>] = [:]
        let heavyTiers: Set<String> = cfg.guardianMinPortionToCount == .lots ? ["lots"] : ["serving", "lots"]
        for it in items {
            guard let day = mealDay[it.mealId] else { continue }
            fiber[day, default: 0] += it.estFiberG ?? 0
            let ratio = PortionMath.ratio(estGrams: it.estGrams,
                                          typicalServingG: typicalServingByFood[it.foodId],
                                          tier: it.portionTier)
            fastFiber[day, default: 0] += (fastGramsByFood[it.foodId] ?? 0) * ratio
            if heavyTiers.contains(it.portionTier) { heavy[day, default: []].insert(it.foodId) }
        }

        // One GuardianDay per check-in day (comfort must be known).
        let days = Set(dayByCheckIn.values)
        return days.compactMap { day in
            guard let date = Self.parseDay(day) else { return nil }
            return GuardianDay(
                date: date,
                discomfort: discomfort[day] ?? 0,
                hasConfounder: confounder[day] ?? false,
                fiberLoadG: fiber[day] ?? 0,
                heavyFoodIds: heavy[day] ?? [],
                fastFiberLoadG: fastFiber[day] ?? 0
            )
        }
    }

    // Portion scaling lives in the shared PortionMath (mirrors the DB trigger,
    // grams-ratio first with the coarse tier fallback).

    // MARK: - Fetches

    private struct ProfileState {
        let goal: GuardianGoalState
        let comfort: GasComfort
        let balancePromptedAt: Date?
    }

    private func profileState() async -> ProfileState {
        let rows: [GuardianGoalRow] = (try? await repository.select(
            "users", columns: "fiber_goal_g,fiber_target_g,fiber_goal_state,gas_comfort,balance_prompted_at")) ?? []
        let r = rows.first
        return ProfileState(
            goal: GuardianGoalState(goalG: r?.fiberGoalG, targetG: r?.fiberTargetG,
                                    unlocked: r?.fiberGoalState == "unlocked"),
            comfort: r?.gasComfort.flatMap(GasComfort.init(rawValue:)) ?? .balanced,
            balancePromptedAt: r?.balancePromptedAt.flatMap(Self.parseISO)
        )
    }

    /// Per-food directional grams of FAST-fermenting fiber (fibers.fermentability
    /// = 'high'), from food_fibers × fibers. Reference data; one read per run.
    private func fastFermentGramsByFood() async -> [String: Double] {
        struct FiberRow: Decodable { let id: String; let fermentability: String? }
        struct JunctionRow: Decodable { let foodId: String; let fiberId: String; let estGramsPerServing: Double? }
        let fibers: [FiberRow] = (try? await repository.select(
            "fibers", columns: "id,fermentability")) ?? []
        let fastIds = Set(fibers.filter { $0.fermentability == "high" }.map(\.id))
        guard !fastIds.isEmpty else { return [:] }
        let junctions: [JunctionRow] = (try? await repository.select(
            "food_fibers", columns: "food_id,fiber_id,est_grams_per_serving")) ?? []
        var grams: [String: Double] = [:]
        for j in junctions where fastIds.contains(j.fiberId) {
            grams[j.foodId, default: 0] += j.estGramsPerServing ?? 0
        }
        return grams
    }

    /// The §17 quiet-balance signals: coarse daily protein/energy scores from
    /// foods.protein_tier / energy_tier × portion ratio. Words downstream.
    private func balanceSignals(items: [GuardianMealItemRow], mealDay: [String: String],
                                typicalServingByFood: [String: Double],
                                promptedAt: Date?, asOf: Date) async -> GuardianBalance {
        let cooldownEnd = promptedAt.map {
            Calendar.current.date(byAdding: .day, value: GameConfig.shared.balancePromptCooldownDays, to: $0) ?? $0
        }
        let inCooldown = cooldownEnd.map { $0 > asOf } ?? false
        guard !items.isEmpty else { return .empty }

        struct TierRow: Decodable { let id: String; let proteinTier: String?; let energyTier: String? }
        let list = "(" + Set(items.map(\.foodId)).joined(separator: ",") + ")"
        let tiers: [TierRow] = (try? await repository.select(
            "foods", columns: "id,protein_tier,energy_tier", filters: ["id": "in.\(list)"])) ?? []
        func value(_ tier: String?) -> Double {
            switch tier {
            case "low": 1
            case "moderate": 2
            case "high": 3
            default: 0
            }
        }
        let proteinByFood = Dictionary(tiers.map { ($0.id, value($0.proteinTier)) }, uniquingKeysWith: { a, _ in a })
        let energyByFood = Dictionary(tiers.map { ($0.id, value($0.energyTier)) }, uniquingKeysWith: { a, _ in a })

        var protein: [String: Double] = [:]
        var energy: [String: Double] = [:]
        for it in items {
            guard let day = mealDay[it.mealId] else { continue }
            let mult = PortionMath.ratio(estGrams: it.estGrams,
                                         typicalServingG: typicalServingByFood[it.foodId],
                                         tier: it.portionTier)
            protein[day, default: 0] += (proteinByFood[it.foodId] ?? 0) * mult
            energy[day, default: 0] += (energyByFood[it.foodId] ?? 0) * mult
        }
        let days = Set(protein.keys).union(energy.keys)
        return GuardianBalance(
            dailyProteinScores: days.map { protein[$0] ?? 0 },
            dailyEnergyScores: days.map { energy[$0] ?? 0 },
            loggedDays: days.count,
            inCooldown: inCooldown
        )
    }

    /// One foods read → names (prompt copy) + typical-serving anchors (ratios).
    private func foodRefLookup() async -> (names: [String: String], servingG: [String: Double]) {
        let rows: [GuardianFoodNameRow] = (try? await repository.select(
            "foods", columns: "id,canonical_name,typical_serving_g")) ?? []
        let names = Dictionary(rows.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { a, _ in a })
        let servings = Dictionary(rows.compactMap { r in r.typicalServingG.map { (r.id, $0) } },
                                  uniquingKeysWith: { a, _ in a })
        return (names, servings)
    }

    // MARK: - Date helpers

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    static func dayString(_ d: Date) -> String { dayFmt.string(from: d) }
    static func parseDay(_ s: String) -> Date? { dayFmt.date(from: String(s.prefix(10))) }
    static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

// Row types local to the guardian (not shared).
struct GuardianMealItemRow: Decodable, Sendable {
    let mealId: String; let foodId: String; let portionTier: String
    let estFiberG: Double?
    var estGrams: Double? = nil   // v2 quantity estimate; nil on legacy rows
}
private struct GuardianGoalRow: Decodable {
    let fiberGoalG: Int?; let fiberTargetG: Int?; let fiberGoalState: String
    var gasComfort: String? = nil; var balancePromptedAt: String? = nil
}
private struct GuardianFoodNameRow: Decodable {
    let id: String; let canonicalName: String
    var typicalServingG: Double? = nil
}
