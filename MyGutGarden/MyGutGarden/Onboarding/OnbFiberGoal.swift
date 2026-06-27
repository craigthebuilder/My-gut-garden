//
//  OnbFiberGoal.swift
//  MyGutGarden, Module A (Onboarding & intake): the fiber-goal derivation.
//
//  PURE, IO-free, and unit-tested in isolation (MyGutGardenTests/Onboarding).
//  Mifflin-St Jeor -> est_daily_kcal -> baseFiberGoalG = round(14 * kcal / 1000)
//  -> fiber_goal_g = round(baseFiberGoalG * plantConsumptionMultipliers[level])
//  (SPEC §10, Phase-2 Batch B).
//
//  DUTY-OF-CARE FENCE (CLAUDE.md rule #6 / Fence 5, SPEC §10):
//    `est_daily_kcal` is INTERNAL ONLY. Computed and written to the DB column
//    but NEVER returned to a view for display, and NEVER framed as a calorie
//    target, deficit, or weight-loss number.
//    `baseFiberGoalG` is also INTERNAL (never surfaced).
//    The ONLY surfaced derived number is `fiberGoalG` (grams, Thrive only).
//    Height and weight are never echoed back as a weight-loss frame.
//
//  RD-REVIEW-REQUIRED: plantConsumptionMultipliers values are clinical.
//

import Foundation

/// Biological sex, captured ONLY to sharpen the internal energy estimate behind
/// the fiber goal (SPEC §10). Never surfaced as identity, never tied to a
/// weight-loss frame.
enum OnbSex: String, CaseIterable, Sendable, Hashable {
    case female, male, unspecified

    /// Value for `users.sex` (nullable text). Unspecified -> store nothing.
    var dbValue: String? { self == .unspecified ? nil : rawValue }

    /// The Mifflin-St Jeor sex constant. `unspecified` averages the two so a
    /// user who declines to share still gets a reasonable, directional estimate.
    var mifflinConstant: Double {
        switch self {
        case .male:        5
        case .female:    -161
        case .unspecified: -78   // mean of +5 and -161
        }
    }

    var displayName: String {
        switch self {
        case .female:      "Female"
        case .male:        "Male"
        case .unspecified: "Prefer not to say"
        }
    }
}

/// Activity multiplier applied to BMR. Optional at intake (SPEC §6, capture
/// "if cheaply available"); a single picker is cheap, so we always have a value.
enum OnbActivityLevel: String, CaseIterable, Sendable, Hashable {
    case sedentary, light, moderate, active, veryActive

    var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light:     1.375
        case .moderate:  1.55
        case .active:    1.725
        case .veryActive: 1.9
        }
    }

    var displayName: String {
        switch self {
        case .sedentary:  "Mostly sitting"
        case .light:      "Lightly active"
        case .moderate:   "Moderately active"
        case .active:     "Active"
        case .veryActive: "Very active"
        }
    }
}

/// The fiber-goal derivation (SPEC §10, Phase-2 Batch B), kept PURE so it is
/// unit-testable in isolation. No UI, no IO, no app state.
enum OnbFiberGoal {
    /// 14 g fiber per 1,000 kcal, the framework constant (SPEC §10).
    static let gramsPerThousandKcal = 14.0

    /// Used only when the user declines to share an age. The estimate is
    /// internal + directional, so a neutral adult value is acceptable.
    static let defaultAge = 30

    /// Mifflin-St Jeor basal metabolic rate (kcal/day). INTERNAL only.
    /// Men:   10·kg + 6.25·cm - 5·age + 5
    /// Women: 10·kg + 6.25·cm - 5·age - 161
    static func basalEnergy(heightCm: Double, weightKg: Double, age: Int, sex: OnbSex) -> Double {
        10 * weightKg + 6.25 * heightCm - 5 * Double(age) + sex.mifflinConstant
    }

    /// Estimated daily energy = BMR x activity factor. INTERNAL ONLY, write
    /// to `users.est_daily_kcal`, never display.
    static func estDailyKcal(heightCm: Double, weightKg: Double, age: Int?,
                             sex: OnbSex, activity: OnbActivityLevel) -> Double {
        let bmr = basalEnergy(heightCm: heightCm, weightKg: weightKg,
                              age: age ?? defaultAge, sex: sex)
        return bmr * activity.factor
    }

    /// Base fiber goal: `round(14 * est_daily_kcal / 1000)`. INTERNAL before
    /// the plant-consumption multiplier is applied.
    static func baseFiberGoalGrams(estDailyKcal: Double) -> Int {
        Int((gramsPerThousandKcal * estDailyKcal / 1000).rounded())
    }

    /// One-shot derivation. Returns all computed values; the caller writes
    /// `estDailyKcal` to the internal column and surfaces ONLY `fiberGoalG`
    /// (Thrive only).
    ///
    /// Phase-2 (Batch B): `plantConsumptionLevel` applies the multiplier from
    /// `GameConfig.plantConsumptionMultipliers`. // RD-REVIEW-REQUIRED on values.
    static func derive(heightCm: Double, weightKg: Double, age: Int?,
                       sex: OnbSex, activity: OnbActivityLevel,
                       plantConsumptionLevel: PlantConsumptionTier = .moderate) -> Derivation {
        let kcal = estDailyKcal(heightCm: heightCm, weightKg: weightKg,
                                age: age, sex: sex, activity: activity)
        let baseG = baseFiberGoalGrams(estDailyKcal: kcal)
        // Apply plant-consumption multiplier. RD-REVIEW-REQUIRED: clinical values.
        let multiplier = GameConfig.shared.plantConsumptionMultipliers[plantConsumptionLevel.rawValue] ?? 0.60
        let adjustedG = Int((Double(baseG) * multiplier).rounded())
        return Derivation(estDailyKcal: kcal, baseFiberGoalG: baseG, fiberGoalG: adjustedG)
    }

    struct Derivation: Equatable, Sendable {
        /// INTERNAL ONLY. Write to `users.est_daily_kcal`; never display. (Fence 5)
        let estDailyKcal: Double
        /// INTERNAL base goal before the plant-consumption multiplier. Never surfaced.
        let baseFiberGoalG: Int
        /// The plant-adjusted fiber goal in grams. The ONLY surfaced derived
        /// number, and ONLY for Thrive. Never shown in Survive. (Fence 5)
        let fiberGoalG: Int
    }
}
