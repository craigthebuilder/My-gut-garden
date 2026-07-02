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

        // Goal state (internal fiber_target_g included; never surfaced).
        let goal = await goalState()

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

        // Food flags + names (for prompt copy + attribution).
        let flagRows = (try? await repository.fetchFoodFlags()) ?? []
        let foodNames = await foodNameLookup()
        let flags: [GuardianFlag] = flagRows.compactMap { row in
            guard let fid = row.foodId, let tier = FlagTier(rawValue: row.flagTier) else { return nil }
            return GuardianFlag(foodId: fid, foodName: foodNames[fid] ?? "this food", tier: tier)
        }

        let days = Self.buildDays(checkIns: checkIns, dayByCheckIn: dayByCheckIn, entries: entries,
                                  items: items, mealDay: mealDay)

        let decision = GuardianEngine.decide(goal: goal, days: days, flags: flags, foodNames: foodNames)
        if let prompt = decision.prompt {
            appState.guardianPrompt(prompt)
        }
    }

    // MARK: - Aggregation (pure)

    static func buildDays(checkIns: [CheckInRow], dayByCheckIn: [String: String],
                          entries: [CheckInEntryRow], items: [GuardianMealItemRow],
                          mealDay: [String: String]) -> [GuardianDay] {
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

        // Per-day fiber load + heavy foods, from the meal items.
        var fiber: [String: Double] = [:]
        var heavy: [String: Set<String>] = [:]
        let heavyTiers: Set<String> = cfg.guardianMinPortionToCount == .lots ? ["lots"] : ["serving", "lots"]
        for it in items {
            guard let day = mealDay[it.mealId] else { continue }
            fiber[day, default: 0] += it.estFiberG ?? 0
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
                heavyFoodIds: heavy[day] ?? []
            )
        }
    }

    // MARK: - Fetches

    private func goalState() async -> GuardianGoalState {
        let rows: [GuardianGoalRow] = (try? await repository.select(
            "users", columns: "fiber_goal_g,fiber_target_g,fiber_goal_state")) ?? []
        let r = rows.first
        return GuardianGoalState(goalG: r?.fiberGoalG, targetG: r?.fiberTargetG,
                                 unlocked: r?.fiberGoalState == "unlocked")
    }

    private func foodNameLookup() async -> [String: String] {
        let rows: [GuardianFoodNameRow] = (try? await repository.select("foods", columns: "id,canonical_name")) ?? []
        return Dictionary(rows.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { a, _ in a })
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
struct GuardianMealItemRow: Decodable, Sendable { let mealId: String; let foodId: String; let portionTier: String; let estFiberG: Double? }
private struct GuardianGoalRow: Decodable { let fiberGoalG: Int?; let fiberTargetG: Int?; let fiberGoalState: String }
private struct GuardianFoodNameRow: Decodable { let id: String; let canonicalName: String }
