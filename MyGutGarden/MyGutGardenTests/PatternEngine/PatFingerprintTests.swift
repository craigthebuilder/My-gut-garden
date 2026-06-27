//
//  PatFingerprintTests.swift
//  MyGutGardenTests, Module F.
//
//  Each symptom fingerprint maps to the expected leaning pattern. These pin the
//  PLACEHOLDER (Fence 1) rules so a future RD rewrite is a deliberate, visible
//  change rather than a silent regression.
//

import Testing
import Foundation
@testable import MyGutGarden

struct PatFingerprintTests {
    let engine = PatPatternEngine()

    // methane-leaning: bloat + constipation, low-odor gas.
    @Test func constipationMapsToMethane() {
        let logs = PatFixtures.rows(count: 14, bss: 1, odor: nil)
        let assessment = engine.assess(logs: logs, asOf: PatFixtures.asOf)
        #expect(assessment?.pattern == .methane)
    }

    // h2s-leaning: sulfur gas + looser stools.
    @Test func sulfurPlusLooseMapsToH2S() {
        let logs = PatFixtures.rows(count: 14, bss: 6, odor: "sulfur")
        let assessment = engine.assess(logs: logs, asOf: PatFixtures.asOf)
        #expect(assessment?.pattern == .h2s)
    }

    // hydrogen/SIBO-leaning via rows: odorless gas + looser stools.
    @Test func odorlessPlusLooseMapsToHydrogenSibo() {
        let logs = PatFixtures.rows(count: 14, bss: 6, odor: "odorless")
        let assessment = engine.assess(logs: logs, asOf: PatFixtures.asOf)
        #expect(assessment?.pattern == .hydrogenSibo)
    }

    // hydrogen/SIBO-leaning via features: the canonical "odorless gas + bloat".
    @Test func odorlessPlusBloatMapsToHydrogenSibo() {
        let feats = PatFixtures.features(count: 14) {
            PatFixtures.feature(dayOffset: $0, stool: .normal, gasOdor: .odorless, bloating: 2)
        }
        let assessment = engine.assess(features: feats, asOf: PatFixtures.asOf)
        #expect(assessment?.pattern == .hydrogenSibo)
    }

    // proteolytic shift: sour gas on an otherwise normal-stool stretch.
    @Test func sourGasMapsToProteolytic() {
        let logs = PatFixtures.rows(count: 14, bss: 4, odor: "sour")
        let assessment = engine.assess(logs: logs, asOf: PatFixtures.asOf)
        #expect(assessment?.pattern == .proteolytic)
    }

    // fat-triggered: worse after fatty meals + looser stools (feature-only signal).
    @Test func worseAfterFattyMapsToFat() {
        let feats = PatFixtures.features(count: 14) {
            PatFixtures.feature(dayOffset: $0, stool: .loose, worseAfterFatty: true)
        }
        let assessment = engine.assess(features: feats, asOf: PatFixtures.asOf)
        #expect(assessment?.pattern == .fat)
    }

    // histamine: aged/fermented-food triggers (± flushing/headache), feature-only.
    @Test func agedFermentedTriggersMapToHistamine() {
        let feats = PatFixtures.features(count: 14) {
            PatFixtures.feature(dayOffset: $0,
                                agedOrFermentedTrigger: true,
                                flushingOrHeadache: true)
        }
        let assessment = engine.assess(features: feats, asOf: PatFixtures.asOf)
        #expect(assessment?.pattern == .histamine)
    }

    // The DB-facing raw values stay aligned with the `pattern_kind` enum.
    @Test func patternRawValuesMatchSchemaEnum() {
        #expect(PatPattern.methane.rawValue == "methane")
        #expect(PatPattern.h2s.rawValue == "h2s")
        #expect(PatPattern.hydrogenSibo.rawValue == "hydrogen_sibo")
        #expect(PatPattern.fat.rawValue == "fat")
        #expect(PatPattern.histamine.rawValue == "histamine")
        #expect(PatPattern.proteolytic.rawValue == "proteolytic")
        #expect(PatConfidence.tentative.rawValue == "tentative")
        #expect(PatConfidence.emerging.rawValue == "emerging")
        #expect(PatConfidence.consistent.rawValue == "consistent")
    }

    // BSS → coarse stool form bucketing (1–2 const · 3–5 normal · 6–7 loose).
    @Test func bristolBucketing() {
        #expect(PatStoolForm(bss: 1) == .constipated)
        #expect(PatStoolForm(bss: 2) == .constipated)
        #expect(PatStoolForm(bss: 3) == .normal)
        #expect(PatStoolForm(bss: 5) == .normal)
        #expect(PatStoolForm(bss: 6) == .loose)
        #expect(PatStoolForm(bss: 7) == .loose)
        #expect(PatStoolForm(bss: nil) == nil)
        #expect(PatStoolForm(bss: 9) == nil)
    }
}
