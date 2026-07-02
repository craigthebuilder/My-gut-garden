//
//  CapManualConfirmTests.swift
//  MyGutGardenTests, Module B: unmatched → manual-confirm selection (§4 step 4).
//
//  The canonical fixture resolves every item, so it has no unmatched entries
//  (asserted below). The selection logic itself is exercised on constructed
//  unmatched items: a resolved correction becomes a `manual` meal_item, an
//  unresolved guess is left out, we never log a food we aren't sure of.
//

import Testing
import Foundation
@testable import MyGutGarden

struct CapManualConfirmTests {

    @Test func canonicalFixtureHasNoUnmatchedItems() throws {
        let response = try Fixtures.recognition()
        #expect(CapManualConfirm.initialItems(response).isEmpty)
    }

    @Test func initialItemsMapEveryUnmatchedNameToAnUnresolvedRow() throws {
        let response = try Self.decodeResponse(unmatched: ["Dragonfruit", "Sumac"])
        let items = CapManualConfirm.initialItems(response)

        #expect(items.map(\.visionName) == ["Dragonfruit", "Sumac"])
        #expect(items.allSatisfy { !$0.isResolved })
    }

    @Test func resolvedKeepsOnlyCorrectedItems() {
        var corrected = CapUnmatchedItem(visionName: "Dragonfruit")
        corrected.resolvedFood = CapFoodSearchResult(id: "food-dragon", canonicalName: "Dragon fruit")
        let skipped = CapUnmatchedItem(visionName: "Sumac")

        let resolved = CapManualConfirm.resolved([corrected, skipped])
        #expect(resolved.count == 1)
        #expect(resolved.first?.visionName == "Dragonfruit")
    }

    @Test func manualItemsBuildFromResolvedSelectionsOnly() {
        var corrected = CapUnmatchedItem(visionName: "Dragonfruit")
        corrected.resolvedFood = CapFoodSearchResult(id: "food-dragon", canonicalName: "Dragon fruit")
        corrected.portion = .lots
        let skipped = CapUnmatchedItem(visionName: "Sumac")   // unresolved → dropped

        let items = CapMealDraftBuilder.manualItems([corrected, skipped])
        #expect(items.count == 1)
        #expect(items.first?.foodId == "food-dragon")
        #expect(items.first?.portion == .lots)
        #expect(items.first?.source == .manual)
    }

    // MARK: - Helper

    /// Decode a minimal recognize response with a chosen unmatched list.
    private static func decodeResponse(unmatched: [String]) throws -> RecognitionResponse {
        let names = unmatched.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
        {
          "provider": "test",
          "vision": { "foods": [], "scene_notes": null },
          "items": [],
          "unmatched": [\(names)],
          "hidden_ingredient_prompts": [],
          "allergy_alerts": [],
          "sensitivity_flags": [],
          "thrive": null
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RecognitionResponse.self, from: Data(json.utf8))
    }
}
