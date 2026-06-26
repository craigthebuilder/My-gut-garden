//
//  GameConfig.swift
//  MyGutGarden — every tunable gamification number in ONE place (CLAUDE.md §5,
//  SPEC §13). Modules read these; nobody hardcodes a magic number. Adjustable
//  without code changes.
//
//  ⚠️ Two blocks here are RD-review-fenced (build the machinery, fence the
//  values): pattern-engine timing (Fence 1) and reintro durations (Fence 3).
//

import Foundation

struct GameConfig: Sendable {
    static let shared = GameConfig()

    // MARK: Guild bloom (§13) — feeding event = portionWeight × relevanceWeight.
    let portionWeight: [PortionTier: Int] = [.trace: 1, .serving: 3, .lots: 5]
    let relevanceWeight: [String: Int] = ["minor": 1, "moderate": 2, "primary": 3]
    /// ≈12%/day (score roughly halves every 5–6 days) — sustained intake blooms.
    let guildDecayPerDay: Double = 0.12
    /// Bloom thresholds: Dormant 0–20 · Sprouting 21–45 · Growing 46–70 · Blooming 71–100.
    let bloomDormantMax = 20
    let bloomSproutingMax = 45
    let bloomGrowingMax = 70
    /// Feeding a guild on 3+ distinct days/week → bonus + "well-fed".
    let consistentFeedingDaysPerWeek = 3
    let consistentFeedingBonus = 10

    /// One feeding event's contribution to a guild's nourishment_score.
    func feedingPoints(portion: PortionTier, relevance: String) -> Int {
        (portionWeight[portion] ?? 1) * (relevanceWeight[relevance] ?? 1)
    }

    // MARK: Plant variety (§8, §13)
    let weeklyPlantTarget = 30          // target, not a cap
    /// Weekly variety resets Sunday 23:59 local; lifetime collection is permanent.
    let plantWeekResetsOnSunday = true

    // MARK: Tier 2 unlock (§13) — first full week: hit 30 once OR log ≥5 days.
    let tier2MinLoggedDaysFirstWeek = 5
    /// D3 Scientists also needs ~this many cumulative days in Tier 2.
    let district3MinCumulativeTier2Days = 10

    // MARK: Survive pattern timing — 🔒 FENCE 1 (RD-REVIEW-REQUIRED placeholders)
    let patternMinDays = 14             // < 14 days: "still gathering signal"
    let patternMinSymptomDays = 10      // of the window, ≥ this many with symptoms
    let patternEmergingDays = 21
    let patternConsistentDays = 28
    /// Confounder-heavy days are down-weighted in the fingerprint (§12).
    let confounderDownweight: Double = 0.4

    // MARK: Reintro durations — 🔒 FENCE 3 (RD-REVIEW-REQUIRED placeholders)
    let reintroChallengeDays = 3        // placeholder challenge length
    let reintroWashoutDays = 3          // placeholder washout between groups
    let patternExperimentDays = 10      // "drop these for ten days, we'll watch"
}
