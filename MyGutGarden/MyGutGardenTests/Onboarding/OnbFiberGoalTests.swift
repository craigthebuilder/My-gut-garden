//
//  OnbFiberGoalTests.swift
//  MyGutGardenTests, Module A: the fiber-goal derivation (SPEC §10).
//
//  Pins the Mifflin–St Jeor → est_daily_kcal → fiber_goal_g chain against known
//  inputs so it can't silently regress (CLAUDE.md §5 testing).
//

import Testing
@testable import MyGutGarden

struct OnbFiberGoalTests {

    // MARK: - Mifflin–St Jeor (internal energy estimate)

    @Test func femaleBmrMatchesFormula() {
        // 10·60 + 6.25·165 − 5·30 − 161 = 600 + 1031.25 − 150 − 161 = 1320.25
        let bmr = OnbFiberGoal.basalEnergy(heightCm: 165, weightKg: 60, age: 30, sex: .female)
        #expect(abs(bmr - 1320.25) < 0.0001)
    }

    @Test func maleBmrMatchesFormula() {
        // 10·80 + 6.25·180 − 5·30 + 5 = 800 + 1125 − 150 + 5 = 1780
        let bmr = OnbFiberGoal.basalEnergy(heightCm: 180, weightKg: 80, age: 30, sex: .male)
        #expect(abs(bmr - 1780) < 0.0001)
    }

    @Test func unspecifiedSexAveragesTheConstant() {
        let male = OnbFiberGoal.basalEnergy(heightCm: 175, weightKg: 70, age: 40, sex: .male)
        let female = OnbFiberGoal.basalEnergy(heightCm: 175, weightKg: 70, age: 40, sex: .female)
        let unspecified = OnbFiberGoal.basalEnergy(heightCm: 175, weightKg: 70, age: 40, sex: .unspecified)
        #expect(abs(unspecified - (male + female) / 2) < 0.0001)
    }

    // MARK: - est_daily_kcal × activity (INTERNAL ONLY)

    @Test func estDailyKcalAppliesActivityFactor() {
        // BMR 1320.25 × sedentary 1.2 = 1584.3
        let kcal = OnbFiberGoal.estDailyKcal(heightCm: 165, weightKg: 60, age: 30,
                                             sex: .female, activity: .sedentary)
        #expect(abs(kcal - 1584.3) < 0.0001)
    }

    @Test func missingAgeFallsBackToDefault() {
        let withDefault = OnbFiberGoal.estDailyKcal(heightCm: 170, weightKg: 70, age: nil,
                                                    sex: .unspecified, activity: .moderate)
        let explicit30 = OnbFiberGoal.estDailyKcal(heightCm: 170, weightKg: 70,
                                                   age: OnbFiberGoal.defaultAge,
                                                   sex: .unspecified, activity: .moderate)
        #expect(abs(withDefault - explicit30) < 0.0001)
    }

    // MARK: - fiber_goal_g = round(14 * kcal / 1000) (the ONLY surfaced number)

    @Test func baseFiberGoalRoundsCorrectly() {
        // The pre-multiplier base: 14 * 1584.3 / 1000 = 22.1802 → 22
        #expect(OnbFiberGoal.baseFiberGoalGrams(estDailyKcal: 1584.3) == 22)
        // 14 * 2759 / 1000 = 38.626 → 39
        #expect(OnbFiberGoal.baseFiberGoalGrams(estDailyKcal: 2759) == 39)
        // exact half-up: 14 * 2000 / 1000 = 28
        #expect(OnbFiberGoal.baseFiberGoalGrams(estDailyKcal: 2000) == 28)
    }

    @Test func deriveProducesBothNumbers() {
        // Female 165cm/60kg/30/sedentary → kcal 1584.3, base 22 g.
        // Default plant consumption (.moderate = 0.60): 22 × 0.60 = 13.2 → 13.
        let d = OnbFiberGoal.derive(heightCm: 165, weightKg: 60, age: 30,
                                    sex: .female, activity: .sedentary)
        #expect(abs(d.estDailyKcal - 1584.3) < 0.0001)
        #expect(d.baseFiberGoalG == 22)
        #expect(d.fiberGoalG == 13)
    }

    @Test func plantConsumptionScalesTheGoal() {
        // Same female base 22 g, scaled by each plant-consumption tier (Batch B).
        func goal(_ tier: PlantConsumptionTier) -> Int {
            OnbFiberGoal.derive(heightCm: 165, weightKg: 60, age: 30,
                                sex: .female, activity: .sedentary,
                                plantConsumptionLevel: tier).fiberGoalG
        }
        #expect(goal(.low) == 6)          // 22 × 0.25 = 5.5  → 6
        #expect(goal(.moderate) == 13)    // 22 × 0.60 = 13.2 → 13
        #expect(goal(.high) == 20)        // 22 × 0.90 = 19.8 → 20
        #expect(goal(.mostOfDiet) == 24)  // 22 × 1.10 = 24.2 → 24
    }

    @Test func maleModerateEndToEnd() {
        // Male 180cm/80kg/30/moderate → kcal 2759, base 39 g.
        // .moderate (0.60): 39 × 0.60 = 23.4 → 23.
        let d = OnbFiberGoal.derive(heightCm: 180, weightKg: 80, age: 30,
                                    sex: .male, activity: .moderate)
        #expect(abs(d.estDailyKcal - 2759) < 0.0001)
        #expect(d.baseFiberGoalG == 39)
        #expect(d.fiberGoalG == 23)
    }

    @Test func sexDbValueOmitsUnspecified() {
        #expect(OnbSex.female.dbValue == "female")
        #expect(OnbSex.male.dbValue == "male")
        #expect(OnbSex.unspecified.dbValue == nil)
    }
}
