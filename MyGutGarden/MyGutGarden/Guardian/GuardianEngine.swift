//
//  GuardianEngine.swift
//  MyGutGarden — the deterministic guardian (SPEC §11). Rules + curated copy,
//  NO live LLM (rule #8). Every threshold comes from GameConfig (Fences 2 & 3).
//
//  Three jobs, at most one prompt surfaced per run:
//   1. Titrate the fiber goal UP when the user is comfortably ahead (an OFFER).
//   2. Spot a food that recurs across off-days (a careful SUGGESTION, never a verdict).
//   3. Offer to bring a tolerated sensitivity food back (a gain).
//  It NEVER auto-applies a goal change and NEVER moves a food into a stricter tier —
//  the prompts are questions the user answers (AppShell writes on confirm).
//

import Foundation

enum GuardianEngine {
    static let cfg = GameConfig.shared

    // MARK: Job 1 — fiber titration OFFER (Fence 2). Never auto-applies.

    /// Offer `+fiberRampStepG` when the user has felt fine (discomfort 0) at/above the
    /// current goal for `fiberRampConsecutiveFineDaysToOffer` consecutive most-recent
    /// non-confounder days, the goal is unlocked, and it's below the cap (personalized
    /// target, and an absolute safety max). Confounder days are skipped, not counted.
    static func fiberTitration(goal: GuardianGoalState, days: [GuardianDay]) -> GuardianPrompt? {
        guard goal.unlocked, let current = goal.goalG else { return nil }
        let cap = min(goal.targetG ?? cfg.fiberGoalAbsoluteMaxG, cfg.fiberGoalAbsoluteMaxG)
        guard current < cap else { return nil }

        var fine = 0
        for d in days.sorted(by: { $0.date > $1.date }) {
            if d.hasConfounder { continue }                       // neither helps nor breaks the run
            if d.discomfort == 0 && d.fiberLoadG >= Double(current) { fine += 1 } else { break }
        }
        guard fine >= cfg.fiberRampConsecutiveFineDaysToOffer else { return nil }

        let proposed = min(current + cfg.fiberRampStepG, cap)
        guard proposed > current else { return nil }
        return .fiberGoalIncrease(currentG: current, proposedG: proposed)
    }

    // MARK: Job 2 — discomfort attribution (Fence 3). False-positive discernment.

    /// SUGGEST watching a food only when a not-yet-flagged food recurs (eaten in
    /// quantity) across at least `guardianMinOccurrences` NON-confounder off-days.
    /// A single off day, or a confounder-heavy day, never triggers a flag.
    static func attribution(days: [GuardianDay], flags: [GuardianFlag],
                            foodNames: [String: String]) -> GuardianPrompt? {
        let offDays = days.filter { $0.discomfort >= 2 && !$0.hasConfounder }
        guard !offDays.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        for d in offDays { for f in d.heavyFoodIds { counts[f, default: 0] += 1 } }

        let flagged: Set<String> = Set(flags.map(\.foodId))
        // Eligible = a not-yet-flagged food eaten in quantity across ≥ threshold off-days.
        let eligible: [(id: String, count: Int)] = counts.compactMap { key, value in
            (!flagged.contains(key) && value >= cfg.guardianMinOccurrences) ? (id: key, count: value) : nil
        }
        // Deterministic pick: most-recurring; ties broken by foodId.
        let candidate: String? = eligible
            .sorted { a, b in a.count != b.count ? a.count > b.count : a.id < b.id }
            .first?.id
        guard let foodId = candidate else { return nil }
        return .suggestWatching(foodName: foodNames[foodId] ?? "this food", foodId: foodId)
    }

    // MARK: Job 3 — "you've overcome it" demotion (a gain).

    /// Offer to bring a `sensitivity` food back when it's been eaten with no trouble
    /// across the recent comfort window (≥ 2 fine, non-confounder days with the food).
    static func overcame(days: [GuardianDay], flags: [GuardianFlag]) -> GuardianPrompt? {
        let sensitivities = flags.filter { $0.tier == .sensitivity }
        guard !sensitivities.isEmpty else { return nil }

        let window = days.sorted { $0.date > $1.date }.prefix(cfg.fiberRampConsecutiveFineDaysToOffer)
        for flag in sensitivities {
            let fineWithFood = window.filter {
                !$0.hasConfounder && $0.discomfort == 0 && $0.heavyFoodIds.contains(flag.foodId)
            }
            if fineWithFood.count >= 2 {
                return .overcameSensitivity(foodName: flag.foodName, foodId: flag.foodId)
            }
        }
        return nil
    }

    // MARK: The one decision to surface (gains first, then a careful suggestion).

    static func decide(goal: GuardianGoalState, days: [GuardianDay],
                       flags: [GuardianFlag], foodNames: [String: String]) -> GuardianDecision {
        if let p = fiberTitration(goal: goal, days: days) {
            return GuardianDecision(prompt: p, rationale: "sustained comfort at/above goal")
        }
        if let p = overcame(days: days, flags: flags) {
            return GuardianDecision(prompt: p, rationale: "sensitivity food tolerated repeatedly")
        }
        if let p = attribution(days: days, flags: flags, foodNames: foodNames) {
            return GuardianDecision(prompt: p, rationale: "food recurs across off-days")
        }
        return .none
    }
}
