//
//  SrvStreakEngineTests.swift
//  MyGutGardenTests, Module E. The symptom-free streak math, INCLUDING the
//  confounder-freeze rule (SPEC §12, §13). Deterministic inputs only.
//
//  The contract under test (CLAUDE.md §5 testing): a good day advances, a bad
//  day resets, and a confounder-heavy day FREEZES, it neither advances nor
//  breaks the streak. This is the positive-outcome streak ("days feeling
//  good"), never restriction (rule #7).
//

import Foundation
import Testing
@testable import MyGutGarden

@MainActor
struct SrvStreakEngineTests {

    // MARK: - Classifier: day → outcome

    @Test func goodDayIsFeltGood() {
        // All severities none/mild, no confounders → a good day.
        let day = SrvDaySymptoms(bristol: .type4, bloating: .mild, gas: .none, pain: .none, urgency: .mild)
        #expect(SrvStreakEngine.outcome(for: day) == .feltGood)
    }

    @Test func aboveMildIsSymptomatic() {
        // Anything above "mild" (moderate/strong) → a symptomatic day.
        let day = SrvDaySymptoms(bloating: .moderate)
        #expect(SrvStreakEngine.outcome(for: day) == .hadSymptoms)
    }

    @Test func bristolExtremeCountsAsSymptom() {
        // A watery/hard-lumps day is a real symptom even with no other severity.
        let watery = SrvDaySymptoms(bristol: .type7)
        #expect(SrvStreakEngine.outcome(for: watery) == .hadSymptoms)

        let normal = SrvDaySymptoms(bristol: .type4)
        #expect(SrvStreakEngine.outcome(for: normal) == .feltGood)
    }

    @Test func confounderFreezesEvenWhenSymptomatic() {
        // A confounder-tagged day freezes regardless of symptoms, the
        // confounder explains it, so it's set aside (SPEC §12).
        let day = SrvDaySymptoms(bloating: .severe, pain: .severe, confounders: [.sick])
        #expect(SrvStreakEngine.outcome(for: day) == .confounded)
    }

    @Test func confounderFreezesEvenWhenSymptomFree() {
        // Frozen means frozen in BOTH directions, a good-but-confounded day
        // does not advance either.
        let day = SrvDaySymptoms(bloating: .none, confounders: [.menstruating])
        #expect(SrvStreakEngine.outcome(for: day) == .confounded)
    }

    // MARK: - Reducer: the three behaviors

    @Test func goodDayAdvances() {
        let result = SrvStreakEngine.reduce([.feltGood, .feltGood, .feltGood])
        #expect(result.current == 3)
        #expect(result.longest == 3)
    }

    @Test func badDayResets() {
        let result = SrvStreakEngine.reduce([.feltGood, .feltGood, .hadSymptoms])
        #expect(result.current == 0)
        #expect(result.longest == 2)
    }

    @Test func confounderNeitherAdvancesNorBreaks() {
        // good, good, FREEZE, good → the frozen day is bridged: streak = 3.
        let result = SrvStreakEngine.reduce([.feltGood, .feltGood, .confounded, .feltGood])
        #expect(result.current == 3)
        #expect(result.longest == 3)
    }

    @Test func confounderDoesNotAdvance() {
        // A frozen day on its own must NOT bump the count.
        let result = SrvStreakEngine.reduce([.feltGood, .confounded])
        #expect(result.current == 1)
    }

    @Test func confounderDoesNotShieldALaterBadDay() {
        // Freeze ≠ immunity: a real bad day after a freeze still resets.
        let result = SrvStreakEngine.reduce([.feltGood, .feltGood, .confounded, .hadSymptoms])
        #expect(result.current == 0)
        #expect(result.longest == 2)
    }

    @Test func longestTracksThePeakAcrossAReset() {
        // 3 good → reset → 1 good. Current is 1 but the best-ever stays 3.
        let result = SrvStreakEngine.reduce(
            [.feltGood, .feltGood, .feltGood, .hadSymptoms, .feltGood]
        )
        #expect(result.current == 1)
        #expect(result.longest == 3)
    }

    @Test func emptyHistoryIsZero() {
        let result = SrvStreakEngine.reduce([])
        #expect(result.current == 0)
        #expect(result.longest == 0)
    }

    // MARK: - End-to-end through the classifier

    @Test func classifyThenFold() {
        // A deterministic fortnight: two good, one rough (reset), one good,
        // one confounded (freeze), three good. Current run = 4 (bridged), best = 4.
        let days: [SrvDaySymptoms] = [
            SrvDaySymptoms(bristol: .type4),                                   // good
            SrvDaySymptoms(bristol: .type4, gas: .mild),                       // good
            SrvDaySymptoms(bristol: .type6, bloating: .severe, gas: .severe),  // rough → reset
            SrvDaySymptoms(bristol: .type4),                                   // good (1)
            SrvDaySymptoms(bloating: .moderate, confounders: [.stressed]),     // freeze
            SrvDaySymptoms(bristol: .type4),                                   // good (2)
            SrvDaySymptoms(bristol: .type3),                                   // good (3)
            SrvDaySymptoms(bristol: .type4)                                    // good (4)
        ]
        let result = SrvStreakEngine.streak(for: days)
        #expect(result.current == 4)
        #expect(result.longest == 4)
    }

    // MARK: - Daily grouping (worst-of-day merge)

    @Test func multipleLogsSameDayTakeTheWorst() {
        // Two logs on the same calendar day collapse to one, worst-severity-wins,
        // so a single rough log isn't averaged away.
        let morning = "2026-06-20T09:00:00Z"
        let evening = "2026-06-20T20:00:00Z"

        let calm = makeLog(id: "a", at: morning, bloating: 0, gas: 1)
        let rough = makeLog(id: "b", at: evening, bloating: 3, gas: 2)

        let days = SrvStore.dailySymptoms(from: [calm, rough])
        #expect(days.count == 1)
        #expect(SrvStreakEngine.outcome(for: days[0].symptoms) == .hadSymptoms)
        #expect(days[0].symptoms.bloating == .severe)
    }

    @Test func unionOfConfoundersAcrossSameDay() {
        let a = makeLog(id: "a", at: "2026-06-20T09:00:00Z", confounders: ["stressed"])
        let b = makeLog(id: "b", at: "2026-06-20T20:00:00Z", confounders: ["poor_sleep"])
        let days = SrvStore.dailySymptoms(from: [a, b])
        #expect(days.count == 1)
        #expect(days[0].symptoms.confounders.count == 2)
        #expect(SrvStreakEngine.outcome(for: days[0].symptoms) == .confounded)
    }

    // MARK: - Helpers

    private func makeLog(
        id: String, at: String,
        bss: Int? = 4, bloating: Int = 0, gas: Int = 0, pain: Int = 0, urgency: Int = 0,
        confounders: [String] = []
    ) -> SrvSymptomLogRow {
        SrvSymptomLogRow(
            id: id, loggedAt: at, bss: bss,
            bloating: bloating, gas: gas, pain: pain, urgency: urgency,
            mood: nil, brainFog: nil, gasOdor: nil, mealTiming: nil,
            foodCorrelation: nil, confounders: confounders, notes: nil
        )
    }
}
