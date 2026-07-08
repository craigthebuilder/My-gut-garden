//
//  GuardianModels.swift
//  MyGutGarden — the quiet back-end guardian (SPEC §11).
//
//  Pure input/output types for the deterministic engine. The engine takes the
//  user's own logged signals + the food-attribute DB and returns AT MOST ONE
//  calm, user-confirmed prompt. No live LLM (rule #8); no severity/score is ever
//  persisted (rule #7); the user authors every move into a stricter tier.
//

import Foundation

/// One day's derived comfort + intake — the guardian's per-day input (SPEC §11).
/// `discomfort` is the worst symptom that day on a coarse 0–3 scale (0 = felt fine).
struct GuardianDay: Sendable, Equatable {
    let date: Date
    let discomfort: Int            // 0 fine .. 3 rough (max of the day's symptom/felt-okay entries)
    let hasConfounder: Bool        // sick / stressed / poor sleep / off food that day → down-weighted
    let fiberLoadG: Double         // estimated fiber grams that day (Σ meal_items.est_fiber_g)
    let heavyFoodIds: Set<String>  // foods eaten at ≥ guardianMinPortionToCount that day
    /// Directional grams of FAST-fermenting fiber that day (SPEC §17). Lets the
    /// engine treat "big prebiotic day + felt off" as ADAPTATION first.
    var fastFiberLoadG: Double = 0
}

/// The quiet-balance signals (SPEC §17): coarse daily protein/energy scores
/// (tier value × portion multiplier, summed per day). Words downstream only.
struct GuardianBalance: Sendable, Equatable {
    let dailyProteinScores: [Double]
    let dailyEnergyScores: [Double]
    let loggedDays: Int
    /// True while the balance-prompt cooldown is running (users.balance_prompted_at).
    let inCooldown: Bool

    static let empty = GuardianBalance(dailyProteinScores: [], dailyEnergyScores: [],
                                       loggedDays: 0, inCooldown: true)
}

/// A food the user already flags (SPEC §9) — used for attribution + demotion.
struct GuardianFlag: Sendable, Equatable {
    let foodId: String
    let foodName: String
    let tier: FlagTier
}

/// The engine's read of the user's fiber-goal state. `targetG` is the INTERNAL
/// personalized ceiling (never surfaced, SPEC §10) — used only to cap an offer.
struct GuardianGoalState: Sendable, Equatable {
    let goalG: Int?                // surfaced goal; nil = baseline-pending (week 1)
    let targetG: Int?             // internal ceiling
    let unlocked: Bool
}

/// The single decision the engine returns: at most one prompt, plus a rationale
/// (for logs/tests only — never surfaced raw).
struct GuardianDecision: Sendable, Equatable {
    let prompt: GuardianPrompt?
    let rationale: String
    static let none = GuardianDecision(prompt: nil, rationale: "no action")
}
