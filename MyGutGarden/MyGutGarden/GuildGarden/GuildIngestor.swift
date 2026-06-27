//
//  GuildIngestor.swift
//  MyGutGarden, Module D's implementation of the `GuildIngesting` seam.
//
//  PURE functions only (no I/O, no state). The MealIngestion coordinator calls
//  these, then owns the `guild_state` decay-then-add write (via GuildBloom) and
//  the `user_districts` write, Module D never writes from here. Keeping this
//  pure is what lets the coordinator wire it at consolidation without edits.
//

import Foundation

struct GuildIngestor: GuildIngesting {

    init() {}

    // MARK: Feeding points (SPEC §13)

    /// `internal_name → feeding points` for one meal. Sums
    /// `GameConfig.feedingPoints(portion:relevance:)` across every guild-feed
    /// relevance of every surfaced item. (preference_intolerance items are
    /// already dropped upstream in `MealContext.from`, §9.)
    ///
    /// Example: a hearty (`lots`=5) serving of a `primary` (×3) feeder = +15;
    /// a `trace` (1) of a `minor` (×1) feeder = +1 (SPEC §13).
    func guildFeedingPoints(for context: MealContext) -> [String: Int] {
        var totals: [String: Int] = [:]
        for item in context.items {
            for feed in item.attributes.guildFeeds {
                let points = GameConfig.shared.feedingPoints(portion: item.portion,
                                                             relevance: feed.relevance)
                guard points > 0 else { continue }
                totals[feed.internalName, default: 0] += points
            }
        }
        return totals
    }

    // MARK: District unlocks (SPEC §13, sequential)

    /// Which district `order`s should be unlocked, given the current per-guild
    /// bloom snapshots and cumulative days in Tier 2. Sequential and monotonic:
    /// each district gates on a bloom achievement in the previous one.
    ///
    /// - D1 Backbone: unlocks with Tier 2 (everyone hosts these) → always present.
    /// - D2 Keystones: ≥2 Backbone guilds have *ever* bloomed.
    /// - D3 Scientists: D2 open + ≥1 Keystone ever bloomed + ≥10 cumulative
    ///   Tier-2 days (`GameConfig.district3MinCumulativeTier2Days`).
    /// - D4 Hidden Gems: D3 open + ≥1 Scientist ever bloomed (the endgame).
    ///
    /// Precondition: this is only meaningful once Tier 2 itself is unlocked
    /// (`ProgressionState.isTier2Unlocked`); the coordinator checks that first.
    func unlockedDistrictOrders(snapshots: [GuildBloomSnapshot],
                                cumulativeTier2Days: Int) -> Set<Int> {
        let g = GuildConfig.shared
        let everBloomed: (Int) -> Int = { order in
            snapshots.filter { $0.districtOrder == order && $0.hasEverBloomed }.count
        }

        var unlocked: Set<Int> = [g.backboneOrder] // D1 opens with Tier 2

        let d2Open = everBloomed(g.backboneOrder) >= g.backboneBloomsForD2
        guard d2Open else { return unlocked }
        unlocked.insert(g.keystoneOrder)

        let d3Open = everBloomed(g.keystoneOrder) >= g.keystoneBloomsForD3
            && cumulativeTier2Days >= GameConfig.shared.district3MinCumulativeTier2Days
        guard d3Open else { return unlocked }
        unlocked.insert(g.scientistOrder)

        let d4Open = everBloomed(g.scientistOrder) >= g.scientistBloomsForD4
        guard d4Open else { return unlocked }
        unlocked.insert(g.hiddenGemsOrder)

        return unlocked
    }
}
