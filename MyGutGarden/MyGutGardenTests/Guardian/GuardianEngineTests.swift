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
