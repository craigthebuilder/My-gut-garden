//
//  PatSafetyTests.swift
//  MyGutGardenTests, Module F.
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

    // MARK: - (a) Mood is CANONICAL high=better: a good mood is never "worse"

    // A high mood_score aggregates through unchanged (NOT inverted to 6 - score)
    // and never marks the day symptomatic.
    @Test func highMoodIsNotReadAsWorse() {
        let feats = PatPatternEngine.features(
            symptomEntries: [],
            moodEntries: [PatFixtures.moodEntry(dayOffset: 0, moodScore: 5)],   // 5 = regulated/best
            stoolEntries: [PatFixtures.stoolEntry(dayOffset: 0, bss: 4)]        // normal stool
        )
        guard let day0 = feats.first else {
            Issue.record("expected one aggregated day")
            return
        }
        #expect(day0.mood == 5)   // canonical high=better, NOT inverted to 1
        #expect(day0.mood != 1)
        #expect(PatRules.isSymptomatic(day0) == false)   // a good day is not symptomatic
    }

    // 14 high-mood, otherwise-fine days never manufacture a lean (mood polarity
    // is never misread into "something is wrong").
    @Test func highMoodWindowNeverProducesALean() {
        var moods: [MoodEntryRow] = []
        var stools: [StoolEntryRow] = []
        for d in 0..<14 {
            moods.append(PatFixtures.moodEntry(dayOffset: d, moodScore: 5))
            stools.append(PatFixtures.stoolEntry(dayOffset: d, bss: 4))
        }
        let feats = PatPatternEngine.features(
            symptomEntries: [], moodEntries: moods, stoolEntries: stools)
        #expect(engine.assess(features: feats, asOf: PatFixtures.asOf) == nil)
    }

    // MARK: - (b) The suggestion gate only SUGGESTS, never a verdict / avoid

    // The persisted body is a dismissible SUGGESTION: added_by=system,
    // status=suspect, and NO user_verdict / avoid / severity key (rule #4).
    @Test func suggestionBodyIsSuggestionOnly() {
        let body = PatPatternEngine.suspectSuggestionBody(userId: "u1", foodId: "food-onion")
        #expect((body["added_by"]?.json as? String) == "system")
        #expect((body["status"]?.json as? String) == "suspect")
        #expect(body["user_verdict"] == nil)   // the user authors every verdict
        #expect(body["avoid"] == nil)          // never an accusation / exclusion
        #expect(!body.keys.contains("severity"))
        #expect(!body.keys.contains("confidence"))
        #expect(!body.keys.contains("score"))
    }

    // The gate fires for a food repeatedly followed by a severe symptom, and only
    // ever returns a food id to SUGGEST, there is no verdict in its output.
    @Test func gateSuggestsAndNeverVerdicts() {
        let meals = (0..<3).map {
            PatFixtures.meal(id: "m\($0)", capturedAt: PatFixtures.day($0).addingTimeInterval(12 * 3600))
        }
        let items = meals.map { PatFixtures.mealItem(mealId: $0.id, foodId: "food-onion") }
        let symptoms = (0..<3).map {
            PatFixtures.symptomEntry(dayOffset: $0, type: "bloating", severity: 3,
                                     occurredAt: PatFixtures.day($0).addingTimeInterval(14 * 3600))
        }
        let suggested = PatPatternEngine.suspectFoodIdsToSuggest(
            meals: meals, mealItems: items, symptomEntries: symptoms)
        #expect(suggested == ["food-onion"])
    }

    // A medical_allergy food is NEVER suggested as a suspect (rule #1: the LOUD
    // allergy pass owns those foods; the soft suspect channel must not touch them).
    @Test func medicalAllergyFoodIsNeverSuggested() {
        let meals = (0..<3).map {
            PatFixtures.meal(id: "m\($0)", capturedAt: PatFixtures.day($0).addingTimeInterval(12 * 3600))
        }
        let items = meals.map { PatFixtures.mealItem(mealId: $0.id, foodId: "food-peanut") }
        let symptoms = (0..<3).map {
            PatFixtures.symptomEntry(dayOffset: $0, type: "pain", severity: 3,
                                     occurredAt: PatFixtures.day($0).addingTimeInterval(14 * 3600))
        }
        let suggested = PatPatternEngine.suspectFoodIdsToSuggest(
            meals: meals, mealItems: items, symptomEntries: symptoms,
            excluding: ["food-peanut"])
        #expect(suggested.isEmpty)
    }

    // The gate respects its thresholds: too-few meals, a symptom that PRECEDES the
    // meal, and a symptom outside the proximity window all fail to suggest.
    @Test func gateRespectsThresholds() {
        let onlyTwo = (0..<2).map {
            PatFixtures.meal(id: "m\($0)", capturedAt: PatFixtures.day($0).addingTimeInterval(12 * 3600))
        }
        let twoItems = onlyTwo.map { PatFixtures.mealItem(mealId: $0.id, foodId: "food-onion") }
        let afterSymptoms = (0..<2).map {
            PatFixtures.symptomEntry(dayOffset: $0, type: "gas", severity: 3,
                                     occurredAt: PatFixtures.day($0).addingTimeInterval(14 * 3600))
        }
        // Fewer than suspectSuggestionMinMeals qualifying meals → nothing.
        #expect(PatPatternEngine.suspectFoodIdsToSuggest(
            meals: onlyTwo, mealItems: twoItems, symptomEntries: afterSymptoms).isEmpty)

        // Three meals, but each symptom lands BEFORE its meal → not "followed".
        let meals = (0..<3).map {
            PatFixtures.meal(id: "m\($0)", capturedAt: PatFixtures.day($0).addingTimeInterval(12 * 3600))
        }
        let items = meals.map { PatFixtures.mealItem(mealId: $0.id, foodId: "food-onion") }
        let beforeSymptoms = (0..<3).map {
            PatFixtures.symptomEntry(dayOffset: $0, type: "gas", severity: 3,
                                     occurredAt: PatFixtures.day($0).addingTimeInterval(8 * 3600))
        }
        #expect(PatPatternEngine.suspectFoodIdsToSuggest(
            meals: meals, mealItems: items, symptomEntries: beforeSymptoms).isEmpty)

        // A severe symptom well outside the 12h window → not "followed".
        let farSymptoms = (0..<3).map {
            PatFixtures.symptomEntry(dayOffset: $0, type: "gas", severity: 3,
                                     occurredAt: PatFixtures.day($0).addingTimeInterval(36 * 3600))
        }
        #expect(PatPatternEngine.suspectFoodIdsToSuggest(
            meals: meals, mealItems: items, symptomEntries: farSymptoms).isEmpty)
    }

    // A below-threshold symptom severity never qualifies a food.
    @Test func gateIgnoresMildSymptoms() {
        let meals = (0..<3).map {
            PatFixtures.meal(id: "m\($0)", capturedAt: PatFixtures.day($0).addingTimeInterval(12 * 3600))
        }
        let items = meals.map { PatFixtures.mealItem(mealId: $0.id, foodId: "food-onion") }
        let mild = (0..<3).map {
            PatFixtures.symptomEntry(dayOffset: $0, type: "gas", severity: 1,   // below min severity
                                     occurredAt: PatFixtures.day($0).addingTimeInterval(14 * 3600))
        }
        #expect(PatPatternEngine.suspectFoodIdsToSuggest(
            meals: meals, mealItems: items, symptomEntries: mild).isEmpty)
    }

    // MARK: - (c) The NEW read path still never surfaces a diagnosis

    // End-to-end through the sub-entry aggregation: a real lean is produced and
    // its copy carries no diagnosis / named-condition language.
    @Test func subEntryReadPathProducesCleanLean() {
        let bundle = PatFixtures.h2sSubEntries(days: 14)
        let feats = PatPatternEngine.features(
            symptomEntries: bundle.symptoms, moodEntries: bundle.moods, stoolEntries: bundle.stools)
        guard let assessment = engine.assess(features: feats, asOf: PatFixtures.asOf) else {
            Issue.record("expected a lean from a 14-day sub-entry window")
            return
        }
        #expect(assessment.pattern == .h2s)   // sulfur + loose, read from the sub-entry tables
        #expect(!PatFixtures.containsDiagnosisLanguage(assessment.evidenceSummary))
    }
}
