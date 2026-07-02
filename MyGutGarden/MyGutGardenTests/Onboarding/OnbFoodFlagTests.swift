//
//  OnbFoodFlagTests.swift
//  MyGutGardenTests, Module A: the intake food-flag writer (SPEC §9).
//
//  Single-mode: the retired two-faced exclusion model is replaced by the
//  three-tier `food_flags` model. These tests pin that the write body keeps
//  scope (food XOR category) and tier distinct, never collapsed, and always
//  stamps source='user' + user_confirmed=true (CLAUDE.md hard rule #1 / §5).
//

import Testing
@testable import MyGutGarden

struct OnbFoodFlagTests {

    // MARK: - Write body: scope (food XOR category) + tier preserved

    @Test func categoryFlagWritesCategoryNotFood() {
        let draft = OnbDraftFlag(
            scope: .category(key: "allium", label: "Onion & garlic"),
            flagTier: .sensitivity)
        let body = OnbFlagWriter.insertBody(userId: "user-1", draft: draft)

        #expect(body["category"]?.asString == "allium")
        #expect(body["food_id"] == nil)                         // never both
        #expect(body["user_id"]?.asString == "user-1")
        #expect(body["flag_tier"]?.asString == "sensitivity")
    }

    @Test func foodFlagWritesFoodIdNotCategory() {
        let draft = OnbDraftFlag(
            scope: .food(id: "food-42", name: "Garlic"),
            flagTier: .allergy)
        let body = OnbFlagWriter.insertBody(userId: "user-1", draft: draft)

        #expect(body["food_id"]?.asString == "food-42")
        #expect(body["category"] == nil)                        // never both
        #expect(body["flag_tier"]?.asString == "allergy")
    }

    @Test func writerAlwaysStampsUserSource() {
        let draft = OnbDraftFlag(
            scope: .category(key: "gluten", label: "Gluten / wheat"),
            flagTier: .allergy)
        let body = OnbFlagWriter.insertBody(userId: "user-1", draft: draft)

        #expect(body["source"]?.asString == "user")
        #expect(body["user_confirmed"]?.asBool == true)
    }

    @Test func flagTierRawValuesMatchPostgresEnum() {
        // The DB enum is exactly these strings (food_flags.flag_tier, SPEC §9).
        #expect(FlagTier.allergy.rawValue == "allergy")
        #expect(FlagTier.sensitivity.rawValue == "sensitivity")
        #expect(FlagTier.watching.rawValue == "watching")
    }

    // MARK: - Curated categories: suggestion leans safe, never auto-classifies

    @Test func likelyAllergensPreSelectAllergy() {
        let gluten = OnbFlagCategory.curated.first { $0.key == "gluten" }
        #expect(gluten?.suggestedTier == .allergy)
    }

    @Test func nonAllergenCategoriesPreSelectSensitivity() {
        // The old pure-preference path is dropped; a non-allergen category leans
        // to the softer HEALTH tier (sensitivity), never a bare preference.
        let allium = OnbFlagCategory.curated.first { $0.key == "allium" }
        #expect(allium?.suggestedTier == .sensitivity)
    }
}

// Test-only readout of a PGValue's payload (the production type is a write-only
// enum; this keeps the assertions readable without touching it).
private extension PGValue {
    var asString: String? {
        if case let .string(s) = self { return s }
        return nil
    }
    var asBool: Bool? {
        if case let .bool(b) = self { return b }
        return nil
    }
}
