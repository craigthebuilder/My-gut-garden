//
//  ThrIngestorTests.swift
//  MyGutGardenTests, Module C: the Thrive streak math + per-meal derivations.
//
//  These are the parts most likely to silently regress (CLAUDE.md §5 testing):
//  the weekly 30-plant streak, the daily 3-P streak, their resets, and the
//  positive-outcome-only framing (rule #7). All inputs are deterministic.
//

import Foundation
import Testing
@testable import MyGutGarden

// MARK: - Fixtures

private enum Fix {
    static func attr(
        name: String,
        isPlant: Bool = true,
        rarity: RarityTier = .common,
        isFermented: Bool = false,
        fibers: [FiberAttr] = [],
        colors: [String] = [],
        phytos: [PhytochemicalAttr] = [],
        guildFeeds: [GuildFeedAttr] = []
    ) -> FoodAttributes {
        FoodAttributes(
            foodId: "id-\(name)",
            canonicalName: name,
            isPlant: isPlant,
            plant: isPlant ? PlantRef(name: name, rarityTier: rarity) : nil,
            isFermented: isFermented,
            histamineLevel: nil,
            fibers: fibers,
            colors: colors,
            phytochemicals: phytos,
            guildFeeds: guildFeeds,
            fodmap: nil
        )
    }

    static func fiber(_ name: String) -> FiberAttr {
        FiberAttr(name: name, relativeAmount: "moderate", isFodmapTrigger: false, estGramsPerServing: 1.0)
    }

    static func context(_ attrs: [FoodAttributes]) -> MealContext {
        MealContext(loggedAt: .init(timeIntervalSince1970: 0),
                    items: attrs.map { IngestedItem(attributes: $0, portion: .serving) })
    }

    static func threePs(pre: Bool, pro: Bool, poly: Bool) -> ThreePs {
        ThreePs(prebiotic: pre, probiotic: pro, polyphenol: poly)
    }
}

// MARK: - Streak transition (updatedStreaks)

@Suite("ThrIngestor streaks")
struct ThrIngestorStreakTests {
    let ingestor = ThrIngestor()

    @Test("Weekly 30 streak increments on consecutive hit weeks")
    func weeklyIncrements() {
        var s = ThriveStreaks()
        let allThree = Fix.threePs(pre: true, pro: true, poly: true)
        s = ingestor.updatedStreaks(s, weekHit30: true, threePsToday: allThree)
        #expect(s.weekly30Streak == 1)
        s = ingestor.updatedStreaks(s, weekHit30: true, threePsToday: allThree)
        s = ingestor.updatedStreaks(s, weekHit30: true, threePsToday: allThree)
        #expect(s.weekly30Streak == 3)
    }

    @Test("Missing the 30 target resets the weekly streak to zero")
    func weeklyResets() {
        var s = ThriveStreaks(weekly30Streak: 5, dailyThreePStreak: 0)
        s = ingestor.updatedStreaks(s, weekHit30: false, threePsToday: Fix.threePs(pre: false, pro: false, poly: false))
        #expect(s.weekly30Streak == 0)
        // ...and it can build again from scratch.
        s = ingestor.updatedStreaks(s, weekHit30: true, threePsToday: Fix.threePs(pre: false, pro: false, poly: false))
        #expect(s.weekly30Streak == 1)
    }

    @Test("Daily 3-P streak increments only when all three P's are hit")
    func dailyThreePIncrements() {
        var s = ThriveStreaks()
        let all = Fix.threePs(pre: true, pro: true, poly: true)
        s = ingestor.updatedStreaks(s, weekHit30: false, threePsToday: all)
        #expect(s.dailyThreePStreak == 1)
        s = ingestor.updatedStreaks(s, weekHit30: false, threePsToday: all)
        #expect(s.dailyThreePStreak == 2)
    }

    @Test("A day missing any P resets the daily 3-P streak")
    func dailyThreePResets() {
        var s = ThriveStreaks(weekly30Streak: 0, dailyThreePStreak: 4)
        // Two of three is not enough.
        s = ingestor.updatedStreaks(s, weekHit30: false, threePsToday: Fix.threePs(pre: true, pro: true, poly: false))
        #expect(s.dailyThreePStreak == 0)
    }

    @Test("The two streaks advance independently in one call")
    func streaksIndependent() {
        let s0 = ThriveStreaks(weekly30Streak: 2, dailyThreePStreak: 9)
        // Hit the week, but break the day.
        let s1 = ingestor.updatedStreaks(s0, weekHit30: true, threePsToday: Fix.threePs(pre: true, pro: false, poly: true))
        #expect(s1.weekly30Streak == 3)
        #expect(s1.dailyThreePStreak == 0)
        // Break the week, keep the day.
        let s2 = ingestor.updatedStreaks(s1, weekHit30: false, threePsToday: Fix.threePs(pre: true, pro: true, poly: true))
        #expect(s2.weekly30Streak == 0)
        #expect(s2.dailyThreePStreak == 1)
    }
}

// MARK: - History helpers (display-side streak)

@Suite("ThrIngestor history helpers")
struct ThrIngestorHistoryTests {

    @Test("Consecutive weekly hits counts only the leading run")
    func consecutiveLeadingRun() {
        #expect(ThrIngestor.consecutiveWeeklyHits(mostRecentFirst: [true, true, true]) == 3)
        #expect(ThrIngestor.consecutiveWeeklyHits(mostRecentFirst: [true, true, false, true]) == 2)
        #expect(ThrIngestor.consecutiveWeeklyHits(mostRecentFirst: [false, true, true]) == 0)
        #expect(ThrIngestor.consecutiveWeeklyHits(mostRecentFirst: []) == 0)
    }

    @Test("weekHit30 is presence at the target (30 is a target, not a cap)")
    func weekHit30Boundary() {
        #expect(ThrIngestor.weekHit30(uniquePlantCount: 29, target: 30) == false)
        #expect(ThrIngestor.weekHit30(uniquePlantCount: 30, target: 30) == true)
        #expect(ThrIngestor.weekHit30(uniquePlantCount: 42, target: 30) == true)
    }
}

// MARK: - Per-meal derivations

@Suite("ThrIngestor per-meal")
struct ThrIngestorMealTests {
    let ingestor = ThrIngestor()

    @Test("plantNames is unique and preserves first-seen order; skips non-plants")
    func plantNamesUniqueOrdered() {
        let ctx = Fix.context([
            Fix.attr(name: "Oats"),
            Fix.attr(name: "Garlic"),
            Fix.attr(name: "Oats"),                       // duplicate
            Fix.attr(name: "Olive oil", isPlant: false),  // not a plant
            Fix.attr(name: "Spinach"),
        ])
        #expect(ingestor.plantNames(for: ctx) == ["Oats", "Garlic", "Spinach"])
    }

    @Test("threePs detects prebiotic, probiotic, and polyphenol")
    func threePsAllThree() {
        let ctx = Fix.context([
            Fix.attr(name: "Oats", fibers: [Fix.fiber("beta_glucan")]),          // prebiotic
            Fix.attr(name: "Kimchi", isFermented: true),                          // probiotic
            Fix.attr(name: "Blueberry", colors: ["blue_purple"],
                     phytos: [PhytochemicalAttr(name: "anthocyanin", category: "polyphenol")]), // polyphenol
        ])
        let p = ingestor.threePs(for: ctx)
        #expect(p.prebiotic && p.probiotic && p.polyphenol)
        #expect(p.allThree)
        #expect(p.count == 3)
    }

    @Test("threePs: a guild-feeding food counts as prebiotic even without listed fibers")
    func prebioticViaGuildFeed() {
        let ctx = Fix.context([
            Fix.attr(name: "Chicory", guildFeeds: [
                GuildFeedAttr(internalName: "base_layer", displayName: "The Base Layer",
                              relevance: "primary", claimRisk: false)
            ])
        ])
        #expect(ingestor.threePs(for: ctx).prebiotic)
    }

    @Test("threePs is all-false for a meal with no qualifying foods")
    func threePsNone() {
        let ctx = Fix.context([Fix.attr(name: "White rice", fibers: [])])
        let p = ingestor.threePs(for: ctx)
        #expect(!p.prebiotic && !p.probiotic && !p.polyphenol)
        #expect(p.count == 0)
    }
}
