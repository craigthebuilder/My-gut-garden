//
//  GuardianEngineTests.swift
//  MyGutGardenTests — the deterministic guardian (SPEC §11).
//
//  Load-bearing invariants: titration only ever OFFERS (never auto-applies) and is
//  capped; attribution needs REPETITION across non-confounder off-days (no single-day
//  or confounder-driven flag); the engine is pure + deterministic. All thresholds
//  read from GameConfig so the tests track the fenced values.
//

import Testing
import Foundation
@testable import MyGutGarden

struct GuardianEngineTests {
    static let cfg = GameConfig.shared

    /// `ago` days before a fixed base date (day 0 = most recent).
    static func day(_ ago: Int, discomfort: Int = 0, confounder: Bool = false,
                    fiber: Double = 0, heavy: Set<String> = []) -> GuardianDay {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        return GuardianDay(date: base.addingTimeInterval(TimeInterval(-ago * 86_400)),
                           discomfort: discomfort, hasConfounder: confounder,
                           fiberLoadG: fiber, heavyFoodIds: heavy)
    }

    // MARK: Job 1 — titration

    @Test func offersAfterEnoughFineDaysAtOrAboveGoal() {
        let goal = GuardianGoalState(goalG: 20, targetG: 40, unlocked: true)
        let days = (0..<Self.cfg.fiberRampConsecutiveFineDaysToOffer).map { Self.day($0, fiber: 22) }
        #expect(GuardianEngine.fiberTitration(goal: goal, days: days)
                == .fiberGoalIncrease(currentG: 20, proposedG: 20 + Self.cfg.fiberRampStepG))
    }

    @Test func silentWhileBaselinePending() {
        let goal = GuardianGoalState(goalG: nil, targetG: 40, unlocked: false)
        let days = (0..<6).map { Self.day($0, fiber: 30) }
        #expect(GuardianEngine.fiberTitration(goal: goal, days: days) == nil)
    }

    @Test func silentBelowTheConsecutiveThreshold() {
        let goal = GuardianGoalState(goalG: 20, targetG: 40, unlocked: true)
        let days = (0..<(Self.cfg.fiberRampConsecutiveFineDaysToOffer - 1)).map { Self.day($0, fiber: 22) }
        #expect(GuardianEngine.fiberTitration(goal: goal, days: days) == nil)
    }

    @Test func brokenByAMostRecentOffDay() {
        let goal = GuardianGoalState(goalG: 20, targetG: 40, unlocked: true)
        var days = [Self.day(0, discomfort: 2, fiber: 22)]
        days += (1...3).map { Self.day($0, fiber: 22) }
        #expect(GuardianEngine.fiberTitration(goal: goal, days: days) == nil)
    }

    @Test func confounderDaysAreSkippedNotCounted() {
        let goal = GuardianGoalState(goalG: 20, targetG: 40, unlocked: true)
        let days = [
            Self.day(0, fiber: 22),
            Self.day(1, discomfort: 3, confounder: true, fiber: 5),   // skipped
            Self.day(2, fiber: 22),
            Self.day(3, fiber: 22),
        ]
        #expect(GuardianEngine.fiberTitration(goal: goal, days: days) != nil)
    }

    @Test func needsFiberAtOrAboveTheCurrentGoal() {
        let goal = GuardianGoalState(goalG: 25, targetG: 40, unlocked: true)
        let days = (0..<Self.cfg.fiberRampConsecutiveFineDaysToOffer).map { Self.day($0, fiber: 10) }
        #expect(GuardianEngine.fiberTitration(goal: goal, days: days) == nil)
    }

    @Test func capsTheOfferAtThePersonalizedTarget() {
        let goal = GuardianGoalState(goalG: 39, targetG: 40, unlocked: true)
        let days = (0..<Self.cfg.fiberRampConsecutiveFineDaysToOffer).map { Self.day($0, fiber: 45) }
        #expect(GuardianEngine.fiberTitration(goal: goal, days: days)
                == .fiberGoalIncrease(currentG: 39, proposedG: 40))
    }

    @Test func silentOnceAtTarget() {
        let goal = GuardianGoalState(goalG: 40, targetG: 40, unlocked: true)
        let days = (0..<Self.cfg.fiberRampConsecutiveFineDaysToOffer).map { Self.day($0, fiber: 45) }
        #expect(GuardianEngine.fiberTitration(goal: goal, days: days) == nil)
    }

    // MARK: The comfort layer (SPEC §17, Fences 2/3/4)

    @Test func boldComfortOffersSoonerAndBigger() {
        let goal = GuardianGoalState(goalG: 20, targetG: 40, unlocked: true)
        let days = (0..<2).map { Self.day($0, fiber: 22) }   // only 2 fine days
        #expect(GuardianEngine.fiberTitration(goal: goal, days: days, comfort: .bold)
                == .fiberGoalIncrease(currentG: 20, proposedG: 24))
        #expect(GuardianEngine.fiberTitration(goal: goal, days: days, comfort: .balanced) == nil)
    }

    @Test func gentleComfortStepsSmaller() {
        let goal = GuardianGoalState(goalG: 20, targetG: 40, unlocked: true)
        let days = (0..<4).map { Self.day($0, fiber: 22) }
        #expect(GuardianEngine.fiberTitration(goal: goal, days: days, comfort: .gentle)
                == .fiberGoalIncrease(currentG: 20, proposedG: 22))
    }

    @Test func adaptationIsTheFirstHypothesisAfterAFastFermentDay() {
        var day = Self.day(0, discomfort: 2, fiber: 20)
        day = GuardianDay(date: day.date, discomfort: 2, hasConfounder: false,
                          fiberLoadG: 20, heavyFoodIds: ["f1"], fastFiberLoadG: 8)
        #expect(GuardianEngine.adaptationCheck(days: [day], comfort: .balanced)
                == .rampSlower(currentComfort: .balanced))
        // decide() must prefer it over attribution for the same signals.
        let decision = GuardianEngine.decide(
            goal: GuardianGoalState(goalG: nil, targetG: nil, unlocked: false),
            days: [day], flags: [], foodNames: [:], comfort: .balanced)
        #expect(decision.prompt == .rampSlower(currentComfort: .balanced))
    }

    @Test func adaptationSilentWhenAlreadyGentleOrConfoundedOrLowFastFiber() {
        let hot = GuardianDay(date: Self.day(0).date, discomfort: 2, hasConfounder: false,
                              fiberLoadG: 20, heavyFoodIds: [], fastFiberLoadG: 8)
        #expect(GuardianEngine.adaptationCheck(days: [hot], comfort: .gentle) == nil)
        let confounded = GuardianDay(date: hot.date, discomfort: 2, hasConfounder: true,
                                     fiberLoadG: 20, heavyFoodIds: [], fastFiberLoadG: 8)
        #expect(GuardianEngine.adaptationCheck(days: [confounded], comfort: .balanced) == nil)
        let lowFast = GuardianDay(date: hot.date, discomfort: 2, hasConfounder: false,
                                  fiberLoadG: 20, heavyFoodIds: [], fastFiberLoadG: 2)
        #expect(GuardianEngine.adaptationCheck(days: [lowFast], comfort: .balanced) == nil)
    }

    @Test func balancePromptsOnlyWithDataAndOutsideCooldown() {
        let light = GuardianBalance(dailyProteinScores: Array(repeating: 1.0, count: 10),
                                    dailyEnergyScores: Array(repeating: 4.0, count: 10),
                                    loggedDays: 10, inCooldown: false)
        #expect(GuardianEngine.balance(light) == .balance(kind: .proteinLight))

        let cooled = GuardianBalance(dailyProteinScores: light.dailyProteinScores,
                                     dailyEnergyScores: light.dailyEnergyScores,
                                     loggedDays: 10, inCooldown: true)
        #expect(GuardianEngine.balance(cooled) == nil)

        let thin = GuardianBalance(dailyProteinScores: [1, 1], dailyEnergyScores: [1, 1],
                                   loggedDays: 2, inCooldown: false)
        #expect(GuardianEngine.balance(thin) == nil)

        let heavy = GuardianBalance(dailyProteinScores: Array(repeating: 10.0, count: 10),
                                    dailyEnergyScores: Array(repeating: 4.0, count: 10),
                                    loggedDays: 10, inCooldown: false)
        #expect(GuardianEngine.balance(heavy) == .balance(kind: .proteinHeavy))

        let steady = GuardianBalance(dailyProteinScores: Array(repeating: 4.0, count: 10),
                                     dailyEnergyScores: Array(repeating: 4.0, count: 10),
                                     loggedDays: 10, inCooldown: false)
        #expect(GuardianEngine.balance(steady) == nil)
    }

    // MARK: Week-one unlock — the first surfaced goal (SPEC §10, Fence 2)

    @Test func initialGoalIsBaselineMeanPlusBuffer() {
        let goal = GuardianEngine.initialFiberGoal(observedDailyFiberG: [18, 22, 20], targetG: 40)
        #expect(goal == 20 + Self.cfg.fiberInitialGoalBufferG)
    }

    @Test func initialGoalIsFlooredWhenBaselineIsTiny() {
        let goal = GuardianEngine.initialFiberGoal(observedDailyFiberG: [1, 2], targetG: 40)
        #expect(goal == Self.cfg.fiberInitialGoalMinG)
    }

    @Test func initialGoalNeverExceedsThePersonalizedTarget() {
        let goal = GuardianEngine.initialFiberGoal(observedDailyFiberG: [60, 60], targetG: 30)
        #expect(goal == 30)
    }

    @Test func initialGoalNeverExceedsTheAbsoluteMax() {
        let goal = GuardianEngine.initialFiberGoal(observedDailyFiberG: [90, 90], targetG: 200)
        #expect(goal == Self.cfg.fiberGoalAbsoluteMaxG)
    }

    @Test func initialGoalCapWinsOverTheFloor() {
        // A pathologically low target still caps the goal — safety beats the floor.
        let goal = GuardianEngine.initialFiberGoal(observedDailyFiberG: [], targetG: 8)
        #expect(goal == 8)
    }

    // MARK: Job 2 — attribution

    @Test func silentOnASingleOffDay() {
        let days = [Self.day(0, discomfort: 3, heavy: ["onion"])]
        #expect(GuardianEngine.attribution(days: days, flags: [], foodNames: ["onion": "Onion"]) == nil)
    }

    @Test func suggestsAFoodRecurringAcrossOffDays() {
        let days = [
            Self.day(0, discomfort: 2, heavy: ["onion", "rice"]),
            Self.day(1, discomfort: 2, heavy: ["onion"]),
            Self.day(2, discomfort: 2, heavy: ["onion"]),
        ]
        #expect(GuardianEngine.attribution(days: days, flags: [], foodNames: ["onion": "Onion", "rice": "Rice"])
                == .suggestWatching(foodName: "Onion", foodId: "onion"))
    }

    @Test func ignoresConfounderOffDays() {
        let days = (0..<3).map { Self.day($0, discomfort: 3, confounder: true, heavy: ["onion"]) }
        #expect(GuardianEngine.attribution(days: days, flags: [], foodNames: ["onion": "Onion"]) == nil)
    }

    @Test func neverRe_suggestsAnAlreadyFlaggedFood() {
        let days = (0..<3).map { Self.day($0, discomfort: 2, heavy: ["onion"]) }
        let flags = [GuardianFlag(foodId: "onion", foodName: "Onion", tier: .watching)]
        #expect(GuardianEngine.attribution(days: days, flags: flags, foodNames: ["onion": "Onion"]) == nil)
    }

    // MARK: Job 3 — overcame

    @Test func offersToBringBackAToleratedSensitivity() {
        let flags = [GuardianFlag(foodId: "garlic", foodName: "Garlic", tier: .sensitivity)]
        let days = [
            Self.day(0, heavy: ["garlic"]),
            Self.day(1, heavy: ["garlic"]),
            Self.day(2),
        ]
        #expect(GuardianEngine.overcame(days: days, flags: flags)
                == .overcameSensitivity(foodName: "Garlic", foodId: "garlic"))
    }

    @Test func silentWithoutRepeatedTolerance() {
        let flags = [GuardianFlag(foodId: "garlic", foodName: "Garlic", tier: .sensitivity)]
        #expect(GuardianEngine.overcame(days: [Self.day(0, heavy: ["garlic"])], flags: flags) == nil)
    }

    // MARK: Job 2b — care escalation (watching → "worth a check?"). 🔒 Fence 3.

    @Test func escalatesAWatchedFoodWithSevereRepeatedReactions() {
        let flags = [GuardianFlag(foodId: "shrimp", foodName: "Shrimp", tier: .watching)]
        let days = (0..<Self.cfg.guardianCareMinOccurrences).map {
            Self.day($0, discomfort: Self.cfg.guardianCareDiscomfort, heavy: ["shrimp"])
        }
        #expect(GuardianEngine.careEscalation(days: days, flags: flags, foodNames: ["shrimp": "Shrimp"])
                == .couldBeAllergy(foodName: "Shrimp", foodId: "shrimp"))
    }

    @Test func careNeverEscalatesAnUnwatchedFood() {
        // An unflagged food reacting severely is attribution's job (suggest a
        // watch), NEVER a jump straight to the allergy care prompt.
        let days = (0..<3).map { Self.day($0, discomfort: 3, heavy: ["shrimp"]) }
        #expect(GuardianEngine.careEscalation(days: days, flags: [], foodNames: ["shrimp": "Shrimp"]) == nil)
    }

    @Test func careRequiresSevereNotMerelyModerateDays() {
        let flags = [GuardianFlag(foodId: "shrimp", foodName: "Shrimp", tier: .watching)]
        let days = (0..<3).map { Self.day($0, discomfort: 2, heavy: ["shrimp"]) }  // moderate, below care bar
        #expect(GuardianEngine.careEscalation(days: days, flags: flags, foodNames: ["shrimp": "Shrimp"]) == nil)
    }

    @Test func careIgnoresConfounderDays() {
        let flags = [GuardianFlag(foodId: "shrimp", foodName: "Shrimp", tier: .watching)]
        let days = (0..<3).map { Self.day($0, discomfort: 3, confounder: true, heavy: ["shrimp"]) }
        #expect(GuardianEngine.careEscalation(days: days, flags: flags, foodNames: ["shrimp": "Shrimp"]) == nil)
    }

    @Test func careStaysQuietInCooldown() {
        let flags = [GuardianFlag(foodId: "shrimp", foodName: "Shrimp", tier: .watching)]
        let days = (0..<3).map { Self.day($0, discomfort: 3, heavy: ["shrimp"]) }
        #expect(GuardianEngine.careEscalation(days: days, flags: flags,
                                              foodNames: ["shrimp": "Shrimp"], inCooldown: true) == nil)
    }

    @Test func decidePrefersCareEscalationOverANewWatch() {
        // A watched food reacting severely outranks suggesting a NEW watch.
        let flags = [GuardianFlag(foodId: "shrimp", foodName: "Shrimp", tier: .watching)]
        let days = (0..<3).map { Self.day($0, discomfort: 3, heavy: ["shrimp", "crab"]) }
        let d = GuardianEngine.decide(goal: GuardianGoalState(goalG: nil, targetG: 40, unlocked: false),
                                      days: days, flags: flags,
                                      foodNames: ["shrimp": "Shrimp", "crab": "Crab"])
        #expect(d.prompt == .couldBeAllergy(foodName: "Shrimp", foodId: "shrimp"))
    }

    // MARK: decide() precedence — a gain (titration) is offered before a suggestion

    @Test func decidePrefersTitrationOverANewSuggestion() {
        let goal = GuardianGoalState(goalG: 20, targetG: 40, unlocked: true)
        let days = [
            Self.day(0, fiber: 25), Self.day(1, fiber: 25), Self.day(2, fiber: 25),
            Self.day(3, discomfort: 3, heavy: ["onion"]),
            Self.day(4, discomfort: 3, heavy: ["onion"]),
            Self.day(5, discomfort: 3, heavy: ["onion"]),
        ]
        let d = GuardianEngine.decide(goal: goal, days: days, flags: [], foodNames: ["onion": "Onion"])
        #expect(d.prompt == .fiberGoalIncrease(currentG: 20, proposedG: 23))
    }
}
