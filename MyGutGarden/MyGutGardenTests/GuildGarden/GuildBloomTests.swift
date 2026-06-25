//
//  GuildBloomTests.swift
//  MyGutGardenTests — Module D bloom/decay math (SPEC §13). The most
//  regression-prone code in the module (CLAUDE.md §5): on-read decay, the
//  threshold state machine, decay-then-add feeding, the consistent-feeding
//  bonus, and the bloom-crossing signal.
//

import Testing
import Foundation
@testable import MyGutGarden

struct GuildBloomTests {

    // Deterministic UTC, Monday-first calendar (no wall-clock, no DST surprises).
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    private let config = GameConfig.shared

    // MARK: Decay (~12%/day, halves every 5–6 days)

    @Test func decayHalvesBetweenFiveAndSixDays() {
        let day0 = date(2024, 1, 1)
        let after5 = GuildBloom.decayedScore(storedScore: 100, lastFedAt: day0, asOf: date(2024, 1, 6))
        let after6 = GuildBloom.decayedScore(storedScore: 100, lastFedAt: day0, asOf: date(2024, 1, 7))
        #expect(after5 > 50)   // not halved yet at 5 days
        #expect(after6 < 50)   // halved by 6 days
    }

    @Test func decayHitsHalfAtTheHalfLife() {
        let day0 = date(2024, 1, 1)
        // 0.88^t = 0.5  →  t ≈ 5.422 days
        let halfLife = day0.addingTimeInterval(5.422 * 86_400)
        let score = GuildBloom.decayedScore(storedScore: 100, lastFedAt: day0, asOf: halfLife)
        #expect(abs(score - 50) < 0.5)
    }

    @Test func decayNoOpWithoutBasis() {
        let day0 = date(2024, 1, 1)
        // Never fed → nothing to decay.
        #expect(GuildBloom.decayedScore(storedScore: 42, lastFedAt: nil, asOf: day0) == 42)
        // Same instant → unchanged.
        #expect(GuildBloom.decayedScore(storedScore: 42, lastFedAt: day0, asOf: day0) == 42)
        // Clock skew (now before lastFed) → unchanged, never inflated.
        #expect(GuildBloom.decayedScore(storedScore: 42, lastFedAt: day0, asOf: date(2023, 12, 31)) == 42)
    }

    // MARK: Threshold state machine (Dormant 0–20 · Sprouting 21–45 · Growing 46–70 · Blooming 71–100)

    @Test func bloomStateBoundaries() {
        #expect(GuildBloomState.state(for: 0) == .dormant)
        #expect(GuildBloomState.state(for: 20) == .dormant)
        #expect(GuildBloomState.state(for: 21) == .sprouting)
        #expect(GuildBloomState.state(for: 45) == .sprouting)
        #expect(GuildBloomState.state(for: 46) == .growing)
        #expect(GuildBloomState.state(for: 70) == .growing)
        #expect(GuildBloomState.state(for: 71) == .blooming)
        #expect(GuildBloomState.state(for: 100) == .blooming)
    }

    // MARK: Feeding adds correctly (decay-then-add, portion × relevance)

    @Test func feedingAddsPortionTimesRelevance() {
        // A trace of a minor feeder = +1; nothing to decay on a fresh guild.
        let small = GuildBloom.applyFeeding(storedScore: 0, lastFedAt: nil, daysFedThisWeek: 0,
                                            points: config.feedingPoints(portion: .trace, relevance: "minor"),
                                            at: date(2024, 1, 1), calendar: cal)
        #expect(small.score == 1)
        #expect(small.state == .dormant)

        // A hearty serving of a primary feeder = +15.
        let big = GuildBloom.applyFeeding(storedScore: 0, lastFedAt: nil, daysFedThisWeek: 0,
                                          points: config.feedingPoints(portion: .lots, relevance: "primary"),
                                          at: date(2024, 1, 1), calendar: cal)
        #expect(big.score == 15)
    }

    @Test func feedingDecaysBeforeAdding() {
        let day0 = date(2024, 1, 1)
        // 80, one day later (×0.88 = 70.4), then +10 = 80.4.
        let out = GuildBloom.applyFeeding(storedScore: 80, lastFedAt: day0, daysFedThisWeek: 1,
                                          points: 10, at: date(2024, 1, 2), calendar: cal)
        #expect(abs(out.score - 80.4) < 0.0001)
    }

    @Test func scoreClampsToHundred() {
        let out = GuildBloom.applyFeeding(storedScore: 98, lastFedAt: nil, daysFedThisWeek: 0,
                                          points: 50, at: date(2024, 1, 1), calendar: cal)
        #expect(out.score == 100)
        #expect(out.state == .blooming)
    }

    // MARK: Bloom crossing (the marquee trigger)

    @Test func crossingIntoBloomingIsDetected() {
        let day0 = date(2024, 1, 1)
        // Growing (70) + 10 = 80 → crosses into Blooming.
        let crossed = GuildBloom.applyFeeding(storedScore: 70, lastFedAt: day0, daysFedThisWeek: 2,
                                              points: 10, at: day0, calendar: cal)
        #expect(crossed.state == .blooming)
        #expect(crossed.crossedIntoBlooming)
    }

    @Test func alreadyBloomingDoesNotReCross() {
        let day0 = date(2024, 1, 1)
        let out = GuildBloom.applyFeeding(storedScore: 80, lastFedAt: day0, daysFedThisWeek: 2,
                                          points: 5, at: day0, calendar: cal)
        #expect(out.state == .blooming)
        #expect(!out.crossedIntoBlooming)
    }

    // MARK: Consistent feeding (3+ distinct days in a week → bonus + well-fed)

    @Test func consistencyBonusAtThirdDistinctDay() {
        let mon = date(2024, 1, 1), tue = date(2024, 1, 2), wed = date(2024, 1, 3)

        let d1 = GuildBloom.applyFeeding(storedScore: 0, lastFedAt: nil, daysFedThisWeek: 0,
                                         points: 10, at: mon, calendar: cal)
        #expect(d1.daysFedThisWeek == 1)
        #expect(!d1.earnedConsistencyBonus)
        #expect(!d1.isWellFed)

        let d2 = GuildBloom.applyFeeding(storedScore: d1.score, lastFedAt: mon,
                                         daysFedThisWeek: d1.daysFedThisWeek,
                                         points: 10, at: tue, calendar: cal)
        #expect(d2.daysFedThisWeek == 2)
        #expect(!d2.earnedConsistencyBonus)

        let d3 = GuildBloom.applyFeeding(storedScore: d2.score, lastFedAt: tue,
                                         daysFedThisWeek: d2.daysFedThisWeek,
                                         points: 10, at: wed, calendar: cal)
        #expect(d3.daysFedThisWeek == 3)
        #expect(d3.earnedConsistencyBonus)
        #expect(d3.isWellFed)
        // The +10 feeding plus the +10 consistency bonus both land this event.
        let expected = GuildBloom.clampScore(GuildBloom.decayedScore(storedScore: d2.score, lastFedAt: tue, asOf: wed)
                                             + 10 + Double(config.consistentFeedingBonus))
        #expect(abs(d3.score - expected) < 0.0001)
    }

    @Test func feedingTwiceSameDayDoesNotDoubleCountOrReBonus() {
        let mon = date(2024, 1, 1), tue = date(2024, 1, 2), wed = date(2024, 1, 3, 9)
        let wedLater = date(2024, 1, 3, 21)

        // Build up to 3 distinct days.
        let d1 = GuildBloom.applyFeeding(storedScore: 0, lastFedAt: nil, daysFedThisWeek: 0, points: 10, at: mon, calendar: cal)
        let d2 = GuildBloom.applyFeeding(storedScore: d1.score, lastFedAt: mon, daysFedThisWeek: d1.daysFedThisWeek, points: 10, at: tue, calendar: cal)
        let d3 = GuildBloom.applyFeeding(storedScore: d2.score, lastFedAt: tue, daysFedThisWeek: d2.daysFedThisWeek, points: 10, at: wed, calendar: cal)
        #expect(d3.earnedConsistencyBonus)

        // Second feed the same (Wednesday) day: no new distinct day, no re-bonus.
        let again = GuildBloom.applyFeeding(storedScore: d3.score, lastFedAt: wed,
                                            daysFedThisWeek: d3.daysFedThisWeek,
                                            points: 10, at: wedLater, calendar: cal)
        #expect(again.daysFedThisWeek == 3)
        #expect(!again.earnedConsistencyBonus)
        #expect(again.isWellFed)
    }

    @Test func weekBoundaryResetsDistinctDayCount() {
        let sun = date(2024, 1, 7)        // Sunday — end of week 1
        let nextMon = date(2024, 1, 8)    // Monday — new week
        let out = GuildBloom.applyFeeding(storedScore: 50, lastFedAt: sun, daysFedThisWeek: 3,
                                          points: 10, at: nextMon, calendar: cal)
        #expect(out.daysFedThisWeek == 1)        // reset
        #expect(!out.earnedConsistencyBonus)
        #expect(!out.isWellFed)
    }

    @Test func weekHelperBucketsMondayThroughSunday() {
        let mon = date(2024, 1, 1), sun = date(2024, 1, 7), nextMon = date(2024, 1, 8)
        #expect(GuildWeek.sameWeek(mon, sun, calendar: cal))
        #expect(!GuildWeek.sameWeek(sun, nextMon, calendar: cal))
    }
}
