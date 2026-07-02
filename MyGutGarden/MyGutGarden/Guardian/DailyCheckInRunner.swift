//
//  DailyCheckInRunner.swift
//  MyGutGarden — the soft daily "did you feel okay yesterday?" pop-up (SPEC §12).
//
//  Decides whether to surface the one-tap pop-up: only when yesterday had logged
//  meals (real activity) AND no check-in exists for yesterday yet. The answer writes
//  a `daily_popup` check-in that the guardian then reasons over. Never nags on an
//  empty day.
//

import Foundation

@MainActor
struct DailyCheckInRunner {
    let repository: Repository
    let appState: AppState

    private struct IdRow: Decodable { let id: String }
    private struct FiberRow: Decodable { let estFiberG: Double? }

    /// Stage the pop-up if due. Returns true if staged (so the caller can hold the
    /// guardian back — they don't stack).
    func offerIfDue(userId: String, asOf: Date = Date()) async -> Bool {
        guard appState.pendingDailyCheckIn == nil, appState.isOnboarded else {
            return appState.pendingDailyCheckIn != nil
        }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: asOf)
        guard let yStart = cal.date(byAdding: .day, value: -1, to: todayStart) else { return false }
        let yStr = GuardianRunner.dayString(yStart)

        // Already checked in for yesterday? Then nothing to ask.
        let existing: [IdRow] = (try? await repository.select(
            "check_ins", columns: "id", filters: ["log_date": "eq.\(yStr)"], limit: 1)) ?? []
        guard existing.isEmpty else { return false }

        // Yesterday's meals gate the offer (no activity → no nag) and give the fiber number.
        let meals: [MealRow] = (try? await repository.select(
            "meals", filters: ["captured_at": "gte.\(Self.iso(yStart))"])) ?? []
        let yMealIds = meals.filter { m in
            guard let d = GuardianRunner.parseISO(m.capturedAt) else { return false }
            return d >= yStart && d < todayStart
        }.map(\.id)
        guard !yMealIds.isEmpty else { return false }

        let items: [FiberRow] = (try? await repository.select(
            "meal_items", columns: "est_fiber_g",
            filters: ["meal_id": "in.(\(yMealIds.joined(separator: ",")))"])) ?? []
        let fiberG = Int(items.compactMap(\.estFiberG).reduce(0, +).rounded())

        appState.pendingDailyCheckIn = DailyCheckInOffer(date: yStart, fiberG: fiberG)
        return true
    }

    private static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
}
