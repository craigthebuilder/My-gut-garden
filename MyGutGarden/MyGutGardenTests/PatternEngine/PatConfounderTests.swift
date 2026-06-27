//
//  PatConfounderTests.swift
//  MyGutGardenTests, Module F.
//
//  Confounder-heavy days are down-weighted in the fingerprint (SPEC §12) so the
//  engine doesn't blame food for an illness/stress flare. These tests show the
//  down-weight actually CHANGES which pattern leads, and that confounder days
//  still count toward the timing gate (they're down-weighted, not dropped).
//

import Testing
import Foundation
@testable import MyGutGarden

struct PatConfounderTests {
    let engine = PatPatternEngine()

    /// 8 days of a strong h2s signal + 6 days of a methane signal.
    /// - confounded: the h2s days are all flagged (sick) → down-weighted.
    private func splitLogs(confoundH2SDays: Bool) -> [SymptomLogRow] {
        let h2sConfounders = confoundH2SDays ? ["sick"] : []
        let h2s = PatFixtures.rows(count: 8, startOffset: 0, bss: 6, odor: "sulfur",
                                   confounders: h2sConfounders)
        let methane = PatFixtures.rows(count: 6, startOffset: 8, bss: 1, odor: "odorless")
        return h2s + methane
    }

    // Without confounders the (more numerous, stronger) h2s signal leads.
    @Test func withoutConfoundersH2SLeads() {
        let assessment = engine.assess(logs: splitLogs(confoundH2SDays: false),
                                       asOf: PatFixtures.asOf)
        #expect(assessment?.pattern == .h2s)
    }

    // Down-weighting the confounded h2s days flips the lead to the clean methane signal.
    @Test func confounderDownweightFlipsLead() {
        let assessment = engine.assess(logs: splitLogs(confoundH2SDays: true),
                                       asOf: PatFixtures.asOf)
        #expect(assessment?.pattern == .methane)
    }

    // The flip is purely from confounders, same days, only the tags differ.
    @Test func onlyDifferenceIsTheConfounderTag() {
        let clean = engine.assess(logs: splitLogs(confoundH2SDays: false), asOf: PatFixtures.asOf)
        let flared = engine.assess(logs: splitLogs(confoundH2SDays: true), asOf: PatFixtures.asOf)
        #expect(clean?.pattern != flared?.pattern)
    }

    // Confounder days still count toward the timing gate (down-weighted, not dropped):
    // 14 confounder-flagged symptomatic days still produce a (tentative) lean.
    @Test func confounderDaysStillCountForTiming() {
        let logs = PatFixtures.rows(count: 14, bss: 6, odor: "sulfur",
                                    confounders: ["stressed", "poor_sleep"])
        let assessment = engine.assess(logs: logs, asOf: PatFixtures.asOf)
        #expect(assessment?.confidence == .tentative)
        #expect(assessment?.pattern == .h2s)   // uniform down-weight cancels in the average
    }

    // The configured down-weight is the fenced placeholder value (< 1, > 0).
    @Test func downweightIsConfiguredAndFractional() {
        let w = GameConfig.shared.confounderDownweight
        #expect(w > 0 && w < 1)
    }
}
