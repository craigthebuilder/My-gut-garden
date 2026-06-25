//
//  ThrIngestor.swift
//  MyGutGarden — Module C: the Thrive ingestion seam (PURE functions only).
//
//  Conforms to `ThriveIngesting` (App/Seams.swift). The MealIngestion
//  coordinator owns ALL persistence (`user_plant_collection`, `weekly_summaries`,
//  streak writes); this type only *computes*. Keeping it pure is what makes the
//  streak math unit-testable with deterministic inputs (CLAUDE.md §5 testing).
//
//  Streaks attach to POSITIVE outcomes only — weeks hitting the 30-plant target
//  and days completing the 3 P's. Never "days restricted" (CLAUDE.md rule #7 /
//  SPEC §14 Fence 5).
//

import Foundation

struct ThrIngestor: ThriveIngesting {

    init() {}

    // MARK: - Per-meal derivations (reuse the Phase-0 join — no new science here)

    /// Unique plant names this meal contributes, in first-seen order. Variety
    /// is presence-based (one garlic counts once — SPEC §8).
    func plantNames(for context: MealContext) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in context.items {
            guard let name = item.attributes.plant?.name else { continue }
            if seen.insert(name).inserted { ordered.append(name) }
        }
        return ordered
    }

    /// Which of the 3 P's this meal hits. Reuses `FoodAttributeJoin` so the
    /// definition of prebiotic/probiotic/polyphenol stays in one place (§11a).
    func threePs(for context: MealContext) -> ThreePs {
        FoodAttributeJoin.threePs(for: context.items.map(\.attributes))
    }

    // MARK: - Streak transition (positive outcomes only — rule #7)

    /// Pure transition for the two Thrive streaks (SPEC §13):
    /// - `weekly30Streak` counts consecutive weeks hitting the 30-plant target;
    ///   call at a week boundary with `weekHit30` for the week that just closed.
    /// - `dailyThreePStreak` counts consecutive days completing all 3 P's;
    ///   call at a day boundary with that day's `threePsToday`.
    /// A non-qualifying period resets the relevant counter to 0. The coordinator
    /// decides *when* to call (boundary detection); this only computes the next
    /// value, which is why it is trivially testable.
    func updatedStreaks(_ current: ThriveStreaks, weekHit30: Bool, threePsToday: ThreePs) -> ThriveStreaks {
        ThriveStreaks(
            weekly30Streak: weekHit30 ? current.weekly30Streak + 1 : 0,
            dailyThreePStreak: threePsToday.allThree ? current.dailyThreePStreak + 1 : 0
        )
    }

    // MARK: - History helpers (used by the home view to *display* a streak)

    /// Consecutive completed weeks that hit 30, given each completed week's
    /// `hit_30` flag ordered most-recent-first. The in-progress week is the
    /// caller's responsibility to drop before calling (it can't break a streak
    /// it hasn't had a chance to complete). Pure + deterministic for testing.
    static func consecutiveWeeklyHits(mostRecentFirst flags: [Bool]) -> Int {
        var streak = 0
        for hit in flags {
            guard hit else { break }
            streak += 1
        }
        return streak
    }

    /// Whether a week's unique-plant count met the target (SPEC §8/§13). 30 is a
    /// target, not a cap — logging past it still counts (`>=`).
    static func weekHit30(uniquePlantCount: Int, target: Int = GameConfig.shared.weeklyPlantTarget) -> Bool {
        uniquePlantCount >= target
    }
}
