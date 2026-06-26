//
//  SrvReintroEngine.swift
//  MyGutGarden — Module E. Reintro-as-leveling (SPEC §11b, §13; Fence 3).
//
//  Clearing a FODMAP group is the hook: it UNLOCKS that food back into the
//  collection (a visible win) and advances the positive symptom-free streak.
//  This is relief + progress, never gamified restriction (CLAUDE.md rule #7).
//
//  🔒 FENCE 3 (CLAUDE.md §3 / SPEC §14): reintro phase lengths and sequencing
//  are clinical. Every duration here comes from GameConfig placeholders marked
//  RD-REVIEW-REQUIRED — none is invented in this file.
//

import Foundation

/// One challenge as the surface sees it (decoded from `reintro_challenges`).
struct SrvChallenge: Identifiable, Sendable, Equatable {
    let id: String
    let group: SrvFodmapGroup
    var status: SrvReintroStatus
    var startedAt: Date?
    var endedAt: Date?
}

enum SrvReintroEngine {

    private static let config = GameConfig.shared

    // MARK: Durations (Fence 3 — read straight from GameConfig)

    /// How long a single group is challenged. // RD-REVIEW-REQUIRED (Fence 3)
    static var challengeDays: Int { config.reintroChallengeDays }
    /// Calm gap between challenges so signals don't bleed. // RD-REVIEW-REQUIRED (Fence 3)
    static var washoutDays: Int { config.reintroWashoutDays }

    // MARK: Progress

    /// Fraction of the challenge window elapsed (0…1), for the progress ring.
    nonisolated static func progress(_ challenge: SrvChallenge, now: Date, calendar: Calendar = .current) -> Double {
        guard challenge.status == .testing, let started = challenge.startedAt else {
            return challenge.status == .passed ? 1 : 0
        }
        let elapsed = calendar.dateComponents([.day], from: started, to: now).day ?? 0
        return max(0, min(1, Double(elapsed) / Double(max(1, challengeDays))))
    }

    /// Whether the challenge window has fully elapsed (ready to call it).
    nonisolated static func isWindowComplete(_ challenge: SrvChallenge, now: Date, calendar: Calendar = .current) -> Bool {
        guard let started = challenge.startedAt else { return false }
        let elapsed = calendar.dateComponents([.day], from: started, to: now).day ?? 0
        return elapsed >= challengeDays
    }

    /// The next group worth testing: the first not-yet-cleared, not-currently-
    /// testing group, in canonical order. (Sequencing is Fence 3 placeholder.)
    nonisolated static func nextSuggestedGroup(given challenges: [SrvChallenge]) -> SrvFodmapGroup? {
        let blocked = Set(challenges.filter { $0.status == .testing || $0.status == .passed }.map(\.group))
        return SrvFodmapGroup.allCases.first { !blocked.contains($0) }
    }

    // MARK: Status transitions (pure — the store persists the result)

    /// Begin testing a group now.
    nonisolated static func started(_ challenge: SrvChallenge, at date: Date) -> SrvChallenge {
        var c = challenge
        c.status = .testing
        c.startedAt = date
        c.endedAt = nil
        return c
    }

    /// Resolve a finished challenge. `tolerated` → passed (food unlocks back);
    /// otherwise → failed (a blameless "needs a rest", retry-able later).
    nonisolated static func resolved(_ challenge: SrvChallenge, tolerated: Bool, at date: Date) -> SrvChallenge {
        var c = challenge
        c.status = tolerated ? .passed : .failed
        c.endedAt = date
        return c
    }

    // MARK: Unlock derivation

    /// Groups the user has cleared — every food whose only trigger is one of
    /// these is now safe to fold back into the collection (the visible win).
    nonisolated static func clearedGroups(_ challenges: [SrvChallenge]) -> Set<SrvFodmapGroup> {
        Set(challenges.filter { $0.status == .passed }.map(\.group))
    }
}
