//
//  PatSafetyTests.swift
//  MyGutGardenTests — Module F.
//
//  The safety-critical invariant (CLAUDE.md hard rule #4, SPEC §11b/§14 Fence 1):
//  the engine NEVER emits a diagnosis, a named condition (SIBO/IBS/IMO), a named
//  bug, or an accumulating bad-guy meter. Every surfaced string stays
//  structurally pattern → experiment → "raise with a GI".
//

import Testing
import Foundation
@testable import MyGutGarden

struct PatSafetyTests {
    let engine = PatPatternEngine()
    let config = GameConfig.shared

    // No pattern's evidence copy contains diagnosis / named-bug language.
    @Test func noPatternCopyContainsDiagnosisLanguage() {
        for pattern in PatPattern.allCases {
            let summary = PatRules.evidenceSummary(for: pattern,
                                                   experimentDays: config.patternExperimentDays)
            #expect(!PatFixtures.containsDiagnosisLanguage(summary),
                    "diagnosis language leaked for \(pattern): \(summary)")
        }
    }

    // Every pattern's copy keeps the structural shape: signal → experiment → GI.
    @Test func everyPatternCopyIsSignalExperimentConfirm() {
        for pattern in PatPattern.allCases {
            let s = PatRules.evidenceSummary(for: pattern,
                                             experimentDays: config.patternExperimentDays).lowercased()
            #expect(s.contains("signal"), "missing signal framing for \(pattern)")
            #expect(s.contains("experiment"), "missing experiment for \(pattern)")
            #expect(s.contains("breath test"), "missing breath-test routing for \(pattern)")
            #expect(s.contains("raising with a gi"), "missing GI routing for \(pattern)")
        }
    }

    // The experiment length is read from config, not hardcoded.
    @Test func experimentLengthComesFromConfig() {
        let s = PatRules.evidenceSummary(for: .h2s, experimentDays: config.patternExperimentDays)
        #expect(s.contains("for \(config.patternExperimentDays) days"))
    }

    // The copy never names the leaning bug even though the pattern enum does
    // ("h2s", "hydrogen_sibo"): assert the raw enum token isn't surfaced.
    @Test func rawPatternTokensNeverSurfaceInCopy() {
        let sibo = PatRules.evidenceSummary(for: .hydrogenSibo,
                                            experimentDays: config.patternExperimentDays).lowercased()
        #expect(!sibo.contains("sibo"))
        #expect(!sibo.contains("hydrogen_sibo"))
    }

    // End-to-end: a real assessment for every reachable fingerprint is clean.
    @Test func endToEndAssessmentsAreClean() {
        let scenarios: [[SymptomLogRow]] = [
            PatFixtures.rows(count: 14, bss: 1, odor: nil),        // methane
            PatFixtures.rows(count: 14, bss: 6, odor: "sulfur"),   // h2s
            PatFixtures.rows(count: 14, bss: 6, odor: "odorless"), // hydrogen_sibo
            PatFixtures.rows(count: 14, bss: 4, odor: "sour"),     // proteolytic
        ]
        for logs in scenarios {
            guard let assessment = engine.assess(logs: logs, asOf: PatFixtures.asOf) else {
                Issue.record("expected a lean for a 14-day symptomatic window")
                continue
            }
            #expect(!PatFixtures.containsDiagnosisLanguage(assessment.evidenceSummary))
        }
    }

    // The "still gathering" copy is calm and non-clinical too.
    @Test func gatheringCopyIsClean() {
        let result = engine.evaluate(logs: PatFixtures.rows(count: 5, bss: 6, odor: "sulfur"),
                                     asOf: PatFixtures.asOf)
        guard case let .gathering(progress) = result else {
            Issue.record("expected .gathering")
            return
        }
        #expect(!PatFixtures.containsDiagnosisLanguage(progress.message))
    }

    // The guard itself works (defends the other assertions from false-negatives).
    @Test func diagnosisGuardDetectsBannedTokens() {
        #expect(PatFixtures.containsDiagnosisLanguage("this looks like SIBO"))
        #expect(PatFixtures.containsDiagnosisLanguage("you have an overgrowth"))
        #expect(!PatFixtures.containsDiagnosisLanguage("your pattern leans toward a sulfur signal"))
    }
}
