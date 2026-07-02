//
//  CapMealAssemblyTests.swift
//  MyGutGardenTests, Module B: meal_items assembly across the three sources
//  (vision / manual / hidden_confirmed), SPEC §5, §9.
//
//  Covers the load-bearing rules: surfaced vision items map straight through,
//  unmatched-with-no-attributes are skipped, the source enum matches the DB
//  exactly, and the combined set de-duplicates by food.
//

import Testing
import Foundation
@testable import MyGutGarden

struct CapMealAssemblyTests {

    @Test func visionItemsFromFixturePreservePortionsAndFoodIds() throws {
        let items = CapMealDraftBuilder.visionItems(try Fixtures.recognition())

        #expect(items.count == 4)
        #expect(items.map(\.foodId) == ["demo-garlic", "demo-oats", "demo-spinach", "demo-blueberry"])
        #expect(items.map(\.portion) == [.serving, .lots, .serving, .trace])
        #expect(items.allSatisfy { $0.source == .vision })
    }

    @Test func unmatchedItemsAreDroppedButSurfacedItemsAreKept() {
        // Single-mode (§9): sensitivity foods are still eaten + logged; only items
        // the DB could not resolve (attributes == nil) are dropped.
        let kept = ResolvedItem(
            vision: VisionFood(name: "Kale", portionTier: .serving, confidence: 0.9, dishType: nil),
            attributes: Fixtures.food(name: "Kale")
        )
        let alsoKept = ResolvedItem(
            vision: VisionFood(name: "Onion", portionTier: .serving, confidence: 0.9, dishType: nil),
            attributes: Fixtures.food(name: "Onion")
        )
        let unresolvable = ResolvedItem(
            vision: VisionFood(name: "Mystery", portionTier: .serving, confidence: 0.3, dishType: nil),
            attributes: nil
        )

        let items = CapMealDraftBuilder.visionItems(items: [kept, alsoKept, unresolvable])
        #expect(items.count == 2)
        #expect(Set(items.map(\.foodId)) == ["demo-kale", "demo-onion"])
    }

    @Test func hiddenConfirmedItemsUseTheConfirmedSourceAndCoarseDefault() {
        let items = CapMealDraftBuilder.hiddenConfirmedItems([CapResolvedHidden(foodId: "demo-onion")])
        #expect(items.first?.source == .hiddenConfirmed)
        #expect(items.first?.portion == .serving)   // coarse default, hidden aromatics aren't sized
    }

    @Test func sourceRawValuesMatchTheDatabaseEnum() {
        #expect(CapItemSource.vision.rawValue == "vision")
        #expect(CapItemSource.manual.rawValue == "manual")
        #expect(CapItemSource.hiddenConfirmed.rawValue == "hidden_confirmed")
    }

    @Test func allItemsDeduplicateByFoodKeepingTheFirstSource() throws {
        let vision = CapMealDraftBuilder.visionItems(try Fixtures.recognition())   // includes demo-garlic
        let manual = [
            CapMealItem(foodId: "demo-garlic", portion: .lots, source: .manual),   // duplicate → dropped
            CapMealItem(foodId: "demo-leek", portion: .serving, source: .manual)   // new → kept
        ]

        let all = CapMealDraftBuilder.allItems(vision: vision, manual: manual, hidden: [])
        #expect(all.count == vision.count + 1)
        #expect(all.contains { $0.foodId == "demo-leek" })
        // The earlier vision source wins for the duplicate.
        #expect(all.first { $0.foodId == "demo-garlic" }?.source == .vision)
    }
}
