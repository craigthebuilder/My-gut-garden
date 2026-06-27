//
//  PatTimingGateTests.swift
//  MyGutGardenTests, Module F.
//
//  The §13 confidence ladder (config-driven): < patternMinDays (with ≥
//  patternMinSymptomDays symptomatic) → nil; 14 → tentative; 21 → emerging;
//  28+ → consistent. Uses an unambiguous sulfur+loose (h2s) signal so the
//  assertions are about TIMING, not fingerprint.
//

import Testing
import Foundation
@testable import MyGutGarden

struct PatTimingGateTests {
    let engine = PatPatternEngine()
    let config = GameConfig.shared

    private func h2sLogs(days: Int) -> [SymptomLogRow] {
        PatFixtures.rows(count: days, bss: 6, odor: "sulfur")
    }

    @Test func justUnderMinDaysReturnsNil() {
        let logs = h2sLogs(days: config.patternMinDays - 1)   // 13
        #expect(engine.assess(logs: logs, asOf: PatFixtures.asOf) == nil)
    }

    @Test func underMinDaysSurfacesGatheringProgress() {
        let logs = h2sLogs(days: config.patternMinDays - 1)   // 13
        let result = engine.evaluate(logs: logs, asOf: PatFixtures.asOf)
        guard case let .gathering(progress) = result else {
            Issue.record("expected .gathering, got \(result)")
            return
        }
        #expect(progress.loggedDays == 13)
        #expect(progress.message.contains("1 more day"))   // 14 - 13 = 1 (singular)
        #expect(!PatFixtures.containsDiagnosisLanguage(progress.message))
    }

    @Test func minDaysGivesTentative() {
        let logs = h2sLogs(days: config.patternMinDays)      // 14
        let assessment = engine.assess(logs: logs, asOf: PatFixtures.asOf)
        #expect(assessment?.confidence == .tentative)
        #expect(assessment?.pattern == .h2s)
    }

    @Test func twentyOneDaysGivesEmerging() {
        let logs = h2sLogs(days: config.patternEmergingDays) // 21
        #expect(engine.assess(logs: logs, asOf: PatFixtures.asOf)?.confidence == .emerging)
    }

    @Test func twentyEightDaysGivesConsistent() {
        let logs = h2sLogs(days: config.patternConsistentDays) // 28
        #expect(engine.assess(logs: logs, asOf: PatFixtures.asOf)?.confidence == .consistent)
    }

    @Test func wellPastConsistentStaysConsistent() {
        let logs = h2sLogs(days: config.patternConsistentDays + 20) // 48
        #expect(engine.assess(logs: logs, asOf: PatFixtures.asOf)?.confidence == .consistent)
    }

    // 14 logged days but only 9 symptomatic (< patternMinSymptomDays) → not ready.
    @Test func enoughDaysButTooFewSymptomaticReturnsNil() {
        let symptomatic = PatFixtures.rows(count: 9, startOffset: 0, bss: 6, odor: "sulfur")
        let asymptomatic = PatFixtures.rows(count: 5, startOffset: 9, bss: 4, odor: nil)
        let logs = symptomatic + asymptomatic
        #expect(logs.count == 14)
        #expect(engine.assess(logs: logs, asOf: PatFixtures.asOf) == nil)
    }

    // Exactly patternMinSymptomDays symptomatic over 14 days → tentative.
    @Test func exactlyMinSymptomaticIsEnough() {
        let symptomatic = PatFixtures.rows(count: 10, startOffset: 0, bss: 6, odor: "sulfur")
        let asymptomatic = PatFixtures.rows(count: 4, startOffset: 10, bss: 4, odor: nil)
        let assessment = engine.assess(logs: symptomatic + asymptomatic, asOf: PatFixtures.asOf)
        #expect(assessment?.confidence == .tentative)
        #expect(assessment?.pattern == .h2s)
    }

    @Test func emptyLogsGather() {
        let result = engine.evaluate(logs: [], asOf: PatFixtures.asOf)
        guard case let .gathering(progress) = result else {
            Issue.record("expected .gathering")
            return
        }
        #expect(progress.loggedDays == 0)
        #expect(progress.message.contains("14 more days"))
    }

    // Logs dated after `asOf` are ignored (defensive windowing).
    @Test func futureLogsAreIgnored() {
        let logs = h2sLogs(days: 14)                          // days 0…13
        let asOfBeforeAll = PatFixtures.day(-1)
        #expect(engine.assess(logs: logs, asOf: asOfBeforeAll) == nil)
    }

    // Multiple logs on the SAME calendar day count as one logged day.
    @Test func sameDayLogsCountOnce() {
        // 14 sulfur+loose days, plus a duplicate on day 0 → still 14 logged days.
        var logs = h2sLogs(days: 14)
        logs.append(PatFixtures.row(dayOffset: 0, bss: 7, odor: "sulfur"))
        let assessment = engine.assess(logs: logs, asOf: PatFixtures.asOf)
        #expect(assessment?.confidence == .tentative)   // 14, not 15, logged days
    }

    // Unparseable timestamps are skipped, never fatal.
    @Test func unparseableTimestampSkipped() {
        let bad = SymptomLogRow(id: "bad", loggedAt: "not-a-date", bss: 6,
                                gasOdor: "sulfur", confounders: [])
        #expect(PatPatternEngine.features(from: bad) == nil)
    }
}
