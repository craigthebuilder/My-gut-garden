//
//  GameConfig.swift
//  MyGutGarden — every tunable gamification + guardian number in ONE place
//  (CLAUDE.md §5, SPEC §13). Modules read these; nobody hardcodes a magic number.
//
//  ⚠️ The fiber-titration block (Fence 2) and the guardian discomfort-attribution
//  block (Fence 3) are RD-review-fenced: build the machinery, fence the values.
//

import Foundation

struct GameConfig: Sendable {
    static let shared = GameConfig()

    // MARK: Guild bloom (§13), feeding event = portionWeight × relevanceWeight.
    let portionWeight: [PortionTier: Int] = [.trace: 1, .serving: 3, .lots: 5]
    let relevanceWeight: [String: Int] = ["minor": 1, "moderate": 2, "primary": 3]
    /// ≈12%/day (score roughly halves every 5–6 days); sustained intake blooms.
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

    // MARK: Tier 2 + world/district unlocks (§13)
    let tier2MinLoggedDaysFirstWeek = 5   // first full week: hit 30 once OR log ≥5 days
    let district3MinCumulativeTier2Days = 10

    // MARK: Fiber goal derivation (§10). Plant-food consumption → target multiplier.
    // 🔒 RD-REVIEW-REQUIRED (clinical).
    let plantConsumptionMultipliers: [String: Double] =
        ["low": 0.25, "moderate": 0.60, "high": 0.90, "most_of_diet": 1.10]
    // At 1.10 the target intentionally exceeds the Mifflin base for heavy plant eaters. RD-REVIEW-REQUIRED.

    // MARK: Fiber goal unlock + titration (§10, §11). 🔒 FENCE 2 — RD-REVIEW-REQUIRED.
    // Week 1 has NO goal; completing the baseline quest unlocks it; the guardian
    // then OFFERS increases (Accept/Decline + a water reminder), never auto-applies,
    // never faster than the tolerance signal, capped at users.fiber_target_g + this max.
    let fiberBaselineQuestPlants = 30              // week-1 quest: 30 plants unlocks the goal
    let fiberRampConsecutiveFineDaysToOffer = 3    // RD-REVIEW: fine days at/above goal before an offer
    let fiberRampStepG = 3                         // RD-REVIEW: grams per offered step
    let fiberGoalAbsoluteMaxG = 50                 // RD-REVIEW: hard safety cap (also capped at fiber_target_g)
    // The first surfaced goal on unlock = observed baseline mean + buffer, floored
    // so it reads as a real goal, always capped at the personalized target (§10).
    let fiberInitialGoalBufferG = 2                // RD-REVIEW: grams above the observed baseline mean
    let fiberInitialGoalMinG = 10                  // RD-REVIEW: floor for the first surfaced goal

    // MARK: The comfort layer (SPEC §17). 🔒 FENCES 2/3/4 — RD-REVIEW-REQUIRED.
    // The gas-comfort dial tunes ramp speed + thresholds; `balanced` reproduces
    // the pre-§17 fenced values exactly, so existing behavior is the default.

    /// Grams-per-offer step by comfort (balanced == fiberRampStepG).
    func fiberRampStepG(for comfort: GasComfort) -> Int {
        switch comfort {
        case .gentle: 2
        case .balanced: fiberRampStepG
        case .bold: 4
        }
    }

    /// Consecutive fine days before an increase is offered (balanced == default).
    func fiberRampFineDays(for comfort: GasComfort) -> Int {
        switch comfort {
        case .gentle: 4
        case .balanced: fiberRampConsecutiveFineDaysToOffer
        case .bold: 2
        }
    }

    /// The coarse discomfort level (0–3) that counts a day as "off" for the
    /// attribution engine. Bold users tolerate more before a day counts.
    func guardianOffDayThreshold(for comfort: GasComfort) -> Int {
        switch comfort {
        case .gentle, .balanced: 2
        case .bold: 3
        }
    }

    /// Directional grams of FAST-fermenting fiber in one meal before the
    /// post-snap fermentation note shows ("your crews feasting").
    func fermentationNoteThresholdG(for comfort: GasComfort) -> Double {
        switch comfort {
        case .gentle: 3
        case .balanced: 5
        case .bold: 8
        }
    }

    /// Fast-fermenting grams in a DAY that make "adaptation" the guardian's
    /// FIRST hypothesis for discomfort (before any food flag).
    let adaptationFastFiberDayG: Double = 6

    /// The "Your fiber" 5-dot fast-fermenting day band (owner, 2026-07-08:
    /// dots + a word, never grams — no gram scale for fermentable load means
    /// anything to a person). Dot n lights when the day's fast-fermenting
    /// grams reach thresholds[n-1]. 🔒 FENCE 2/4 (RD-REVIEW-REQUIRED).
    let fastFermentBandThresholdsG: [Double] = [1, 4, 8, 13, 19]
    let fastFermentBandLabels = ["quiet", "mild", "steady", "medium", "lively", "a big day"]

    func fastFermentBandLevel(dayG: Double) -> Int {
        fastFermentBandThresholdsG.filter { dayG >= $0 }.count
    }

    func fastFermentBandLabel(dayG: Double) -> String {
        fastFermentBandLabels[fastFermentBandLevel(dayG: dayG)]
    }

    // Quiet balance (words only, never numbers — rule #6 as amended).
    // Daily balance score = Σ tier value (none 0 / low 1 / moderate 2 / high 3)
    // × portion multiplier. Thresholds are coarse placeholder clinical values.
    let balanceMinLoggedDays = 8           // enough data in the 14-day window before any prompt
    let balanceProteinLightScore = 2.0     // mean daily protein score below this → "running light"
    let balanceProteinHeavyScore = 9.0     // mean above this → "quite protein-heavy lately"
    let balanceEnergyLightScore = 2.0      // mean daily energy score below this → "running light on fuel"
    let balancePromptCooldownDays = 14     // at most one balance prompt per this window

    // MARK: Guardian discomfort-attribution gate (§11). 🔒 FENCE 3 — RD-REVIEW-REQUIRED.
    // False-positive discernment: NEVER flag on a single off day or a confounder-heavy
    // day. The engine only SUGGESTS a 'watching' flag; the user confirms every step.
    let guardianMinOccurrences = 3                 // RD-REVIEW: meals-with-food before SUGGESTING a watch
    let guardianProximityHours = 12                // RD-REVIEW: discomfort must follow the meal within this window
    let guardianMinPortionToCount: PortionTier = .serving  // RD-REVIEW: portion that counts as "a lot"
    let guardianConfounderDownweight: Double = 0.4         // RD-REVIEW: down-weight confounder-heavy days

    // MARK: Guardian care-prompt escalation (§11, §15 Fence 3). 🔒 RD-REVIEW-REQUIRED.
    // The "could this be an allergy? — worth raising with a doctor/allergist" prompt.
    // ONLY escalates a food the user is ALREADY WATCHING (never unflagged→allergy),
    // requires a STRONGER pattern than a new watch (SEVERE off-days), stays
    // wellness-only + user-confirmed (never a diagnosis), and is cooldown-limited
    // so it never nags on a sensitive topic.
    let guardianCareDiscomfort = 3                 // RD-REVIEW: only SEVERE off-days count (0–3 scale)
    let guardianCareMinOccurrences = 3             // RD-REVIEW: severe off-days with the watched food before suggesting
    let carePromptCooldownDays = 21                // RD-REVIEW: at most one care prompt per this window

    // MARK: Field-guide gap insights (tunable, not fenced)
    let phytoGapInsightDays = 30                   // "not eaten lycopene in over a month"
}
