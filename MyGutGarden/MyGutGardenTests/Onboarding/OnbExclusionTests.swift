//
//  OnbExclusionTests.swift
//  MyGutGardenTests, Module A: the two-faced exclusion model (SPEC §9).
//
//  ⚠️ THE load-bearing invariant (CLAUDE.md hard rule #1). These tests pin that
//  the type drives OPPOSITE behavior and is NEVER collapsed with the scope into
//  one flat list, the single most important thing to keep from regressing.
//

import Testing
@testable import MyGutGarden

struct OnbExclusionTests {

    // MARK: - Two-faced behavior table (§9)

    @Test func medicalAllergyIsLoudAcrossBothModes() {
        let b = OnbExclusionBehavior.of(.medicalAllergy)
        #expect(b.isLoud)
        #expect(b.elevatedHiddenIngredientSensitivity)
        #expect(b.silentlyOmitted == false)
    }

    @Test func preferenceIntoleranceIsQuiet() {
        let b = OnbExclusionBehavior.of(.preferenceIntolerance)
        #expect(b.isLoud == false)
        #expect(b.elevatedHiddenIngredientSensitivity == false)
        #expect(b.silentlyOmitted)
    }

    @Test func theTwoTypesNeverShareBehavior() {
        // The whole point of §9: opposite behavior, never collapsed.
        #expect(OnbExclusionBehavior.of(.medicalAllergy) != OnbExclusionBehavior.of(.preferenceIntolerance))
    }

    // MARK: - Write body: scope (food XOR category) + type preserved

    @Test func categoryExclusionWritesCategoryNotFood() {
        let draft = OnbDraftExclusion(
            scope: .category(key: "allium", label: "Onion & garlic"),
            exclusionType: .preferenceIntolerance)
        let body = OnbExclusionWriter.insertBody(userId: "user-1", draft: draft)

        #expect(body["category"]?.asString == "allium")
        #expect(body["food_id"] == nil)                         // never both
        #expect(body["user_id"]?.asString == "user-1")
        #expect(body["exclusion_type"]?.asString == "preference_intolerance")
    }

    @Test func foodExclusionWritesFoodIdNotCategory() {
        let draft = OnbDraftExclusion(
            scope: .food(id: "food-42", name: "Garlic"),
            exclusionType: .medicalAllergy)
        let body = OnbExclusionWriter.insertBody(userId: "user-1", draft: draft)

        #expect(body["food_id"]?.asString == "food-42")
        #expect(body["category"] == nil)                        // never both
        #expect(body["exclusion_type"]?.asString == "medical_allergy")
    }

    @Test func exclusionTypeRawValuesMatchPostgresEnum() {
        // The DB enum is exactly these strings (20260625000001_schema.sql).
        #expect(ExclusionType.medicalAllergy.rawValue == "medical_allergy")
        #expect(ExclusionType.preferenceIntolerance.rawValue == "preference_intolerance")
    }

    // MARK: - Curated categories: suggestion leans safe, never auto-classifies

    @Test func likelyAllergensPreSelectLoud() {
        let gluten = OnbExclusionCategory.curated.first { $0.key == "gluten" }
        #expect(gluten?.suggestedType == .medicalAllergy)
    }

    @Test func preferenceCategoriesPreSelectQuiet() {
        let allium = OnbExclusionCategory.curated.first { $0.key == "allium" }
        #expect(allium?.suggestedType == .preferenceIntolerance)
    }

    // MARK: - Soft routing (SPEC §6), suggestion, never a gate

    @Test func reliefSignalRoutesToSurvive() {
        #expect(OnbRouting.suggestedMode(goals: [.increaseEnergy], hasReliefSignal: true) == .survive)
    }

    @Test func optimizationGoalsRouteToThrive() {
        #expect(OnbRouting.suggestedMode(goals: [.increaseEnergy, .decreaseBrainFog],
                                         hasReliefSignal: false) == .thrive)
    }

    @Test func reliefGoalsRouteToSurvive() {
        #expect(OnbRouting.suggestedMode(goals: [.calmIbs, .findTriggers],
                                         hasReliefSignal: false) == .survive)
    }

    @Test func noSignalDefaultsToThrive() {
        #expect(OnbRouting.suggestedMode(goals: [], hasReliefSignal: false) == .thrive)
    }
}

// Test-only readout of a PGValue's string payload (the production type is a
// write-only enum; this keeps the assertions readable without touching it).
private extension PGValue {
    var asString: String? {
        if case let .string(s) = self { return s }
        return nil
    }
}
