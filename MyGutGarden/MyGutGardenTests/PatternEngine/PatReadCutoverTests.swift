//
//  PatReadCutoverTests.swift
//  MyGutGardenTests, Module F.
//
//  The Batch-D read cutover: the engine now aggregates per-`log_date` from the
//  sub-entry tables (symptom_entries / mood_entries / stool_entries), with the
//  flat `symptom_logs` table kept ONLY as a fallback for uncovered days. These
//  tests pin the aggregation so the H2S/odor lean and correlations don't go dark.
//

import Testing
import Foundation
@testable import MyGutGarden

struct PatReadCutoverTests {
    let engine = PatPatternEngine()

    // A 14-day sulfur+loose window expressed through the NEW sub-entry tables
    // produces the same tentative h2s lean the legacy flat path would.
    @Test func subEntryWindowGivesTentativeH2S() {
        let b = PatFixtures.h2sSubEntries(days: 14)
        let feats = PatPatternEngine.features(
            symptomEntries: b.symptoms, moodEntries: b.moods, stoolEntries: b.stools)
        let a = engine.assess(features: feats, asOf: PatFixtures.asOf)
        #expect(a?.confidence == .tentative)
        #expect(a?.pattern == .h2s)
    }

    // Legacy fallback fills ONLY days the sub-entry tables don't already cover:
    // a conflicting legacy day-0 is dropped (sub-entry wins), a unique legacy
    // day-5 is kept.
    @Test func legacyFallbackOnlyFillsUncoveredDays() {
        let subSym = [PatFixtures.symptomEntry(dayOffset: 0, type: "gas", severity: 2, gasOdor: "sulfur")]
        let subStool = [PatFixtures.stoolEntry(dayOffset: 0, bss: 6)]   // loose
        let legacy = [
            PatFixtures.row(dayOffset: 0, bss: 1, odor: "odorless"),    // conflicting day → dropped
            PatFixtures.row(dayOffset: 5, bss: 1, odor: "odorless"),    // uncovered day → kept
        ]
        let feats = PatPatternEngine.features(
            symptomEntries: subSym, moodEntries: [], stoolEntries: subStool, legacyLogs: legacy)
        #expect(feats.count == 2)
        let d0 = feats.first { PatPatternEngine.dayString($0.day) == PatFixtures.logDate(0) }
        let d5 = feats.first { PatPatternEngine.dayString($0.day) == PatFixtures.logDate(5) }
        #expect(d0?.stool == .loose)         // sub-entry beat the legacy row
        #expect(d5?.stool == .constipated)   // legacy filled an uncovered day
    }

    // Stool aggregation keeps the day's most extreme reading (furthest from 4).
    @Test func stoolAggregationPicksMostExtreme() {
        let stools = [
            PatFixtures.stoolEntry(dayOffset: 0, bss: 4),   // normal
            PatFixtures.stoolEntry(dayOffset: 0, bss: 7),   // loose, furthest from 4
        ]
        let feats = PatPatternEngine.features(
            symptomEntries: [], moodEntries: [], stoolEntries: stools)
        #expect(feats.first?.stool == .loose)
    }

    // Gas-odor aggregation prefers the most discriminating cue (sulfur > odorless),
    // so the H2S lean isn't masked by an also-logged odorless reading.
    @Test func gasOdorPrefersMostDiscriminating() {
        let syms = [
            PatFixtures.symptomEntry(dayOffset: 0, type: "gas", severity: 2, gasOdor: "odorless"),
            PatFixtures.symptomEntry(dayOffset: 0, type: "gas", severity: 2, gasOdor: "sulfur"),
        ]
        let feats = PatPatternEngine.features(
            symptomEntries: syms, moodEntries: [], stoolEntries: [])
        #expect(feats.first?.gasOdor == .sulfur)
    }

    // Symptom severity maps to the right per-type slot (max per type per day).
    @Test func severityMapsByType() {
        let syms = [
            PatFixtures.symptomEntry(dayOffset: 0, type: "bloating", severity: 3),
            PatFixtures.symptomEntry(dayOffset: 0, type: "pain", severity: 2),
        ]
        let feats = PatPatternEngine.features(
            symptomEntries: syms, moodEntries: [], stoolEntries: [])
        #expect(feats.first?.bloating == 3)
        #expect(feats.first?.pain == 2)
        #expect(feats.first?.urgency == nil)
    }

    // Empty sub-entry tables with no legacy fallback → no features → gathering.
    @Test func emptySubEntriesGather() {
        let feats = PatPatternEngine.features(
            symptomEntries: [], moodEntries: [], stoolEntries: [])
        #expect(feats.isEmpty)
        #expect(engine.assess(features: feats, asOf: PatFixtures.asOf) == nil)
    }
}
