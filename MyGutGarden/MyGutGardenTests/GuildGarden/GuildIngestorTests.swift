//
//  GuildIngestorTests.swift
//  MyGutGardenTests, Module D's `GuildIngesting` seam: feeding-point summation
//  and the sequential district-unlock gates (SPEC §13). Each gate is covered
//  independently so a regression in one doesn't hide behind another.
//

import Testing
import Foundation
@testable import MyGutGarden

struct GuildIngestorTests {

    private let ingestor = GuildIngestor()

    private func feed(_ internalName: String, _ relevance: String, claimRisk: Bool = false) -> GuildFeedAttr {
        GuildFeedAttr(internalName: internalName, displayName: internalName, relevance: relevance, claimRisk: claimRisk)
    }
    private func item(_ portion: PortionTier, _ feeds: [GuildFeedAttr]) -> IngestedItem {
        IngestedItem(attributes: Fixtures.food(name: "f-\(UUID().uuidString)", guildFeeds: feeds), portion: portion)
    }

    // MARK: Feeding points

    @Test func feedingPointsSumAcrossItemsAndGuilds() {
        let context = MealContext(loggedAt: Date(), items: [
            // lots(5) × primary(3) = 15 to base_layer; lots(5) × moderate(2) = 10 to arsenal
            item(.lots, [feed("base_layer", "primary"), feed("anti_inflammatory_arsenal", "moderate")]),
            // trace(1) × minor(1) = 1 more to base_layer
            item(.trace, [feed("base_layer", "minor")]),
        ])
        let points = ingestor.guildFeedingPoints(for: context)
        #expect(points["base_layer"] == 16)
        #expect(points["anti_inflammatory_arsenal"] == 10)
    }

    @Test func feedingPointsEmptyWhenNoGuildFeeds() {
        let context = MealContext(loggedAt: Date(), items: [item(.serving, [])])
        #expect(ingestor.guildFeedingPoints(for: context).isEmpty)
    }

    // MARK: District unlock gates (sequential)

    private func snap(_ order: Int, bloomed: Bool) -> GuildBloomSnapshot {
        GuildBloomSnapshot(districtOrder: order, isBlooming: bloomed, hasEverBloomed: bloomed)
    }

    @Test func d1AlwaysOpenWithTier2() {
        #expect(ingestor.unlockedDistrictOrders(snapshots: [], cumulativeTier2Days: 0) == [1])
    }

    @Test func d2NeedsTwoBackboneBlooms() {
        let oneBloom = [snap(1, bloomed: true), snap(1, bloomed: false)]
        #expect(ingestor.unlockedDistrictOrders(snapshots: oneBloom, cumulativeTier2Days: 0) == [1])

        let twoBlooms = [snap(1, bloomed: true), snap(1, bloomed: true)]
        #expect(ingestor.unlockedDistrictOrders(snapshots: twoBlooms, cumulativeTier2Days: 0) == [1, 2])
    }

    @Test func d3NeedsKeystoneBloomAndCumulativeDays() {
        let base = [snap(1, bloomed: true), snap(1, bloomed: true), snap(2, bloomed: true)]
        // Keystone bloomed but only 9 cumulative days → D3 stays closed.
        #expect(ingestor.unlockedDistrictOrders(snapshots: base, cumulativeTier2Days: 9) == [1, 2])
        // 10 cumulative days → D3 opens.
        #expect(ingestor.unlockedDistrictOrders(snapshots: base, cumulativeTier2Days: 10) == [1, 2, 3])
        // Enough days but no keystone bloom → D3 stays closed.
        let noKeystone = [snap(1, bloomed: true), snap(1, bloomed: true), snap(2, bloomed: false)]
        #expect(ingestor.unlockedDistrictOrders(snapshots: noKeystone, cumulativeTier2Days: 20) == [1, 2])
    }

    @Test func d4NeedsScientistBloomAfterD3() {
        let withScientist = [snap(1, bloomed: true), snap(1, bloomed: true),
                             snap(2, bloomed: true), snap(3, bloomed: true)]
        #expect(ingestor.unlockedDistrictOrders(snapshots: withScientist, cumulativeTier2Days: 12) == [1, 2, 3, 4])

        let noScientist = [snap(1, bloomed: true), snap(1, bloomed: true),
                           snap(2, bloomed: true), snap(3, bloomed: false)]
        #expect(ingestor.unlockedDistrictOrders(snapshots: noScientist, cumulativeTier2Days: 12) == [1, 2, 3])
    }

    @Test func gatesAreSequentialNotSkippable() {
        // A keystone + scientist bloom can't skip past a still-closed D2 (only
        // one backbone bloomed), and cumulative days alone can't help.
        let leapfrog = [snap(1, bloomed: true),
                        snap(2, bloomed: true), snap(3, bloomed: true)]
        #expect(ingestor.unlockedDistrictOrders(snapshots: leapfrog, cumulativeTier2Days: 99) == [1])
    }
}
