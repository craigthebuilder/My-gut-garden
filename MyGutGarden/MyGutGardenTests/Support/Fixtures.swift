//
//  Fixtures.swift
//  MyGutGardenTests, canonical test data shared by every module's test suite,
//  so nobody re-invents a sample. Add module-specific fixtures in your own
//  MyGutGardenTests/<Module>/ folder; put anything shared here.
//

import Foundation
@testable import MyGutGarden

enum Fixtures {
    /// Deterministic timestamp (avoid wall-clock in tests).
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// The canonical recognize response (sample meal joined against the seed).
    static func recognition() throws -> RecognitionResponse {
        try RecognitionService.offlineFixture()
    }

    /// A surfaced meal context built from the canonical response.
    static func mealContext(loggedAt: Date = fixedDate) throws -> MealContext {
        MealContext.from(try recognition(), loggedAt: loggedAt)
    }

    /// Build a FoodAttributes for targeted tests.
    static func food(
        name: String,
        isPlant: Bool = true,
        isFermented: Bool = false,
        fibers: [FiberAttr] = [],
        colors: [String] = [],
        phytochemicals: [PhytochemicalAttr] = [],
        guildFeeds: [GuildFeedAttr] = [],
        fodmap: FodmapAttr? = nil
    ) -> FoodAttributes {
        FoodAttributes(
            foodId: "demo-\(name.lowercased())",
            canonicalName: name,
            isPlant: isPlant,
            plant: isPlant ? PlantRef(name: name, rarityTier: .common) : nil,
            isFermented: isFermented,
            histamineLevel: nil,
            fibers: fibers,
            colors: colors,
            phytochemicals: phytochemicals,
            guildFeeds: guildFeeds,
            fodmap: fodmap
        )
    }
}
