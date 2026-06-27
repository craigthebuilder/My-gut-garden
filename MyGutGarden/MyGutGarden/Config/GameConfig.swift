//
//  GameConfig.swift
//  MyGutGarden, every tunable gamification number in ONE place (CLAUDE.md §5,
//  SPEC §13). Modules read these; nobody hardcodes a magic number. Adjustable
//  without code changes.
//
//  ⚠️ Two blocks here are RD-review-fenced (build the machinery, fence the
//  values): pattern-engine timing (Fence 1) and reintro durations (Fence 3).
//

import Foundation

struct GameConfig: Sendable {
    static let shared = GameConfig()

    // MARK: Guild bloom (§13), feeding event = portionWeight × relevanceWeight.
    let portionWeight: [PortionTier: Int] = [.trace: 1, .serving: 3, .lots: 5]
    let relevanceWeight: [String: Int] = ["minor": 1, "moderate": 2, "primary": 3]
    /// ≈12%/day (score roughly halves every 5–6 days), sustained intake blooms.
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

    // MARK: Tier 2 unlock (§13), first full week: hit 30 once OR log ≥5 days.
    let tier2MinLoggedDaysFirstWeek = 5
    /// D3 Scientists also needs ~this many cumulative days in Tier 2.
    let district3MinCumulativeTier2Days = 10

    // MARK: Survive pattern timing, 🔒 FENCE 1 (RD-REVIEW-REQUIRED placeholders)
    let patternMinDays = 14             // < 14 days: "still gathering signal"
    let patternMinSymptomDays = 10      // of the window, ≥ this many with symptoms
    let patternEmergingDays = 21
    let patternConsistentDays = 28
    /// Confounder-heavy days are down-weighted in the fingerprint (§12).
    let confounderDownweight: Double = 0.4

    // MARK: Reintro durations, 🔒 FENCE 3 (RD-REVIEW-REQUIRED placeholders)
    // These are TIME-BASED and apply to FODMAP challenges ONLY. Food-suspect
    // challenges (Batch E) are EVENT-DRIVEN and must never read these (rule #7).
    let reintroChallengeDays = 3        // placeholder challenge length (FODMAP only)
    let reintroWashoutDays = 3          // placeholder washout between groups (FODMAP only)
    let patternExperimentDays = 10      // "drop these for ten days, we'll watch"

    // MARK: Plant-food consumption → fiber multiplier (Batch B). 🔒 RD-REVIEW-REQUIRED (clinical)
    let plantConsumptionMultipliers: [String: Double] =
        ["low": 0.25, "moderate": 0.60, "high": 0.90, "most_of_diet": 1.10]
    // At 1.10 the goal intentionally exceeds the Mifflin base for heavy plant eaters. RD-REVIEW-REQUIRED.

    // MARK: Thrive fiber auto-increase (Batch B; tunable, NOT fenced)
    let fiberGoalAutoIncreaseConsecutiveWeeks = 2   // consecutive qualifying weeks before a step
    let fiberGoalAutoIncreaseMinDaysPerWeek = 5     // weekly_summaries.fiber_days_met threshold
    let fiberGoalAutoIncrementG = 5                 // grams per step

    // MARK: Survive residue ceiling (Batch B). INTERNAL ONLY, never surfaced. 🔒 RD-REVIEW-REQUIRED
    let surviveResidueCeilingStartG = 15            // placeholder starting ceiling (Survive only)

    // MARK: Suspect reintro pass/fail (Batch E). 🔒 FENCE 3 (extended), all RD-REVIEW-REQUIRED
    let reintroMealsToPass = 3                      // felt-fine meals at ≥ minPortion to auto-clear
    let reintroMinPortionToCount: PortionTier = .serving  // minimum portion that counts toward passing
    let avoidOfferAfterUnwellCount = 2              // consecutive low-amount unwell tries → Avoid OFFER

    // MARK: Avoid → mode-switch prompt (Batch E)
    let avoidFoodsForSurviveSwitchPrompt = 5        // informational care prompt; re-fires on each subsequent add

    // MARK: Aggressive Survive reset (Batch E). 🔒 FENCE 6, ALL RD-REVIEW-REQUIRED
    enum ResetProgressMetric: Sendable { case symptomFreeDays, daysElapsed }
    /// Phase ADVANCEMENT stays relief-informed (you add foods back when symptoms
    /// settle), so this stays `.symptomFreeDays`. R5 owner decision: Survive is now
    /// an intentional low-residue PROGRAM, so a NEUTRAL "Day N" display is fine; the
    /// duty-of-care valves are the clinician disclaimer + frictionless Pause + Return
    /// to Thrive. Still NO gamified rewards or streaks ON the restriction itself.
    let resetProgressMetric: ResetProgressMetric = .symptomFreeDays
    let resetNoImprovementThresholdDays = 14        // re-fire the clinician prompt
    let resetSymptomFreeDaysToAdvance = 3           // relief days before suggesting additions
    let resetLowFiberAdditionCheckDays = 7          // days between reintroduction steps
    let resetTypicalDurationWeeksLow = 1            // informational copy only, never a bar denominator
    let resetTypicalDurationWeeksHigh = 3          // informational copy only

    // MARK: Pattern-engine suspect auto-suggestion gate (Batch E). 🔒 FENCE 7, RD-REVIEW-REQUIRED
    let suspectSuggestionMinMeals = 3              // meals-with-food before SUGGESTING a suspect
    let suspectSuggestionMinSeverity = 2           // symptom severity that qualifies
    let suspectSuggestionProximityHours = 12       // symptom must follow the meal within this window

    // MARK: Survive episode notifications (R3 Batch E; cadence = post-meal + evening only)
    let surviveReintroFollowupMinutes = 30         // "how did that sit?" nudge after a meal photo
    let surviveEveningCheckinHour = 20             // local hour for the evening check-in reminder

    // MARK: Reset diet-break auto-track (R3 Batch E). 🔒 FENCE 6, RD-REVIEW-REQUIRED
    // During an active reset, a meal food above this fiber tier is "not low-residue"
    // (a break); if the user then logs feeling unwell within the window, that food is
    // auto-added to Checking with a calm, removable note. Investigation, not accusation.
    let resetBreakFoodFiberThresholdG: Double = 2.5  // grams/serving above which a food breaks the reset
    let resetBreakUnwellProximityHours = 6           // unwell within this window of a break -> auto-add

    // MARK: Field-guide gap insights (R3 Batch B; tunable, not fenced)
    let phytoGapInsightDays = 30                   // "not eaten lycopene in over a month"
}
