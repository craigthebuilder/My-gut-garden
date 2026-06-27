//
//  SrvReintroAndPatternTests.swift
//  MyGutGardenTests, Module E. Reintro leveling transitions (Fence 3 durations
//  come from GameConfig) + the READ-ONLY pattern rendering guards (Fence 1,
//  rule #4: never a diagnosis / named bug; experiment only when steady).
//

import Foundation
import Testing
@testable import MyGutGarden

// (The legacy time-based SrvReintroEngine was retired in R5; reintro is now the
// event-driven food-suspect system tested via FoodStatusStore.)

@MainActor
struct SrvPatternPresenterTests {

    private func row(_ pattern: SrvPattern, _ confidence: SrvPatternConfidence) -> PatternAssessmentRow {
        PatternAssessmentRow(
            id: "\(pattern.rawValue)-\(confidence.rawValue)",
            computedAt: "2026-06-20T10:00:00Z",
            pattern: pattern.rawValue,
            confidence: confidence.rawValue,
            evidenceSummary: "placeholder"
        )
    }

    @Test func steadyPatternOffersTheExperiment() {
        let p = SrvPatternPresenter.present(row(.h2s, .consistent))
        #expect(p?.experiment != nil)
        // Routing always points back to a clinician (SPEC §11b).
        #expect(p?.routing.contains("GI") == true)
    }

    @Test func tentativeAndEmergingWithholdTheExperiment() {
        #expect(SrvPatternPresenter.present(row(.h2s, .tentative))?.experiment == nil)
        #expect(SrvPatternPresenter.present(row(.h2s, .emerging))?.experiment == nil)
    }

    @Test func neverSurfacesADiagnosisOrNamedBug() {
        // 🔒 rule #4 / Fence 1: no condition or bug names in user-facing copy.
        // "hydrogen_sibo" must render as a hydrogen-type-gas lean, never "SIBO".
        let banned = ["sibo", "ibs", "imo", "overgrowth", "diagnos", "disease", "infection"]
        for pattern in [SrvPattern.methane, .h2s, .hydrogenSibo, .fat, .histamine, .proteolytic] {
            for confidence in [SrvPatternConfidence.tentative, .emerging, .consistent] {
                guard let p = SrvPatternPresenter.present(row(pattern, confidence)) else {
                    Issue.record("expected a presentation for \(pattern.rawValue)")
                    continue
                }
                let blob = ([p.insight, p.experiment ?? "", p.routing]).joined(separator: " ").lowercased()
                for term in banned {
                    #expect(!blob.contains(term), "‘\(term)’ leaked for \(pattern.rawValue)/\(confidence.rawValue)")
                }
            }
        }
    }

    @Test func unknownEnumValuesFailSafe() {
        // Never guess a clinical claim from an unrecognized value (rule #8).
        let bad = PatternAssessmentRow(id: "x", computedAt: "2026-06-20T10:00:00Z",
                                       pattern: "made_up", confidence: "consistent", evidenceSummary: nil)
        #expect(SrvPatternPresenter.present(bad) == nil)
    }
}
