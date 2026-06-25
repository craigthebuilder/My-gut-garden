//
//  OnbFiberGoal.swift
//  MyGutGarden — Module A (Onboarding & intake): the fiber-goal derivation.
//
//  PURE, IO-free, and unit-tested in isolation (MyGutGardenTests/Onboarding).
//  Mifflin–St Jeor → est_daily_kcal → fiber_goal_g = round(14 * kcal / 1000)
//  (SPEC §10).
//
//  ⚠️ DUTY-OF-CARE FENCE (CLAUDE.md rule #6 / Fence 5, SPEC §10): `est_daily_kcal`
//  is INTERNAL ONLY. This type computes it so the caller can write it to
//  `users.est_daily_kcal`, but it is NEVER returned to a view for display, and
//  is NEVER framed as a calorie target, deficit, or weight-loss number. The ONLY
//  surfaced number from this whole derivation is `fiberGoalG` (grams). Height and
//  weight are never echoed back as a weight-loss frame anywhere in the app.
//

import Foundation

/// Biological sex, captured ONLY to sharpen the internal energy estimate behind
/// the fiber goal (SPEC §10). Never surfaced as identity, never tied to a
/// weight-loss frame.
enum OnbSex: String, CaseIterable, Sendable, Hashable {
    case female, male, unspecified

    /// Value for `users.sex` (nullable text). Unspecified → store nothing.
    var dbValue: String? { self == .unspecified ? nil : rawValue }

    /// The Mifflin–St Jeor sex constant. `unspecified` averages the two so a
    /// user who declines to share still gets a reasonable, directional estimate.
    var mifflinConstant: Double {
        switch self {
        case .male: 5
        case .female: -161
        case .unspecified: -78   // mean of +5 and −161
        }
    }

    var displayName: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        case .unspecified: "Prefer not to say"
        }
    }
}

/// Activity multiplier applied to BMR. Optional at intake (SPEC §6 — capture
/// "if cheaply available"); a single picker is cheap, so we always have a value.
enum OnbActivityLevel: String, CaseIterable, Sendable, Hashable {
    case sedentary, light, moderate, active, veryActive

    var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    var displayName: String {
        switch self {
        case .sedentary: "Mostly sitting"
        case .light: "Lightly active"
        case .moderate: "Moderately active"
        case .active: "Active"
        case .veryActive: "Very active"
        }
    }
}

/// The fiber-goal derivation (SPEC §10), kept PURE so it is unit-testable in
/// isolation. No UI, no IO, no app state.
enum OnbFiberGoal {
    /// 14 g fiber per 1,000 kcal — the framework constant (SPEC §10).
    static let gramsPerThousandKcal = 14.0

    /// Used only when the user declines to share an age. The estimate is
    /// internal + directional, so a neutral adult value is acceptable and never
    /// surfaced.
    static let defaultAge = 30

    /// Mifflin–St Jeor basal metabolic rate (kcal/day). ⚠️ Internal only.
    /// Men:   10·kg + 6.25·cm − 5·age + 5
    /// Women: 10·kg + 6.25·cm − 5·age − 161
    static func basalEnergy(heightCm: Double, weightKg: Double, age: Int, sex: OnbSex) -> Double {
        10 * weightKg + 6.25 * heightCm - 5 * Double(age) + sex.mifflinConstant
    }

    /// Estimated daily energy = BMR × activity factor. ⚠️ INTERNAL ONLY — write
    /// to `users.est_daily_kcal`, never display.
    static func estDailyKcal(heightCm: Double, weightKg: Double, age: Int?,
                             sex: OnbSex, activity: OnbActivityLevel) -> Double {
        let bmr = basalEnergy(heightCm: heightCm, weightKg: weightKg,
                              age: age ?? defaultAge, sex: sex)
        return bmr * activity.factor
    }

    /// `fiber_goal_g = round(14 * est_daily_kcal / 1000)` (SPEC §10). The ONLY
    /// surfaced derived number.
    static func fiberGoalGrams(estDailyKcal: Double) -> Int {
        Int((gramsPerThousandKcal * estDailyKcal / 1000).rounded())
    }

    /// One-shot derivation. Returns BOTH numbers; the caller writes
    /// `estDailyKcal` to the internal column and surfaces ONLY `fiberGoalG`.
    static func derive(heightCm: Double, weightKg: Double, age: Int?,
                       sex: OnbSex, activity: OnbActivityLevel) -> Derivation {
        let kcal = estDailyKcal(heightCm: heightCm, weightKg: weightKg,
                                age: age, sex: sex, activity: activity)
        return Derivation(estDailyKcal: kcal, fiberGoalG: fiberGoalGrams(estDailyKcal: kcal))
    }

    struct Derivation: Equatable, Sendable {
        /// ⚠️ INTERNAL ONLY — write to `users.est_daily_kcal`, never display.
        let estDailyKcal: Double
        /// The surfaced fiber goal, in grams.
        let fiberGoalG: Int
    }
}
