//
//  GuildNotifications.swift
//  MyGutGarden, Module D's guild-notification CONTENT (SPEC §11a, §13).
//
//  Content only, scheduling is the NotificationScheduler's job. Everything is
//  GAIN-framed (DESIGN.md §6: "feed your Anti-inflammatory Arsenal", never
//  loss/shame) and 🔒 Fence-2-safe: a `claim_risk` guild (Mood/Estrogen/
//  Mitochondria/Tumor) keeps claim_risk as an RD-review ledger hook only — no
//  qualifier is appended to user copy (owner, 2026-07-02; see FENCES.md).
//

import Foundation

/// A ready-to-schedule notification (title + body). Pure data.
struct GuildNotificationContent: Sendable, Equatable {
    let title: String
    let body: String
}

enum GuildNotifications {

    /// Owner (2026-07-02): the emerging-science disclaimer no longer renders in
    /// user-facing surfaces, pushes included. `claimRisk` stays in the signatures
    /// as the RD-review ledger hook (FENCES.md) but adds nothing to the copy.
    private static func qualified(_ body: String, claimRisk: Bool) -> String {
        _ = claimRisk
        return body
    }

    /// "Your Anti-inflammatory Arsenal is hungry, feed it some resistant starch."
    /// Nudge a guild whose nourishment has faded. `feedSuggestion` is a food/fiber
    /// from the guild's `feeds_copy` (curated seed data, never an LLM call, §9).
    static func hungry(displayName: String,
                       feedSuggestion: String?,
                       claimRisk: Bool) -> GuildNotificationContent {
        let tail = feedSuggestion.map { ", feed it some \($0)" } ?? ", give it something to eat"
        return GuildNotificationContent(
            title: "\(displayName) is hungry",
            body: qualified("Your \(displayName) is hungry\(tail).", claimRisk: claimRisk)
        )
    }

    /// Celebrate a guild reaching Blooming (the marquee moment, in push form).
    static func bloomed(displayName: String, claimRisk: Bool) -> GuildNotificationContent {
        GuildNotificationContent(
            title: "\(displayName) is blooming",
            body: qualified("Your \(displayName) just bloomed, sustained feeding paid off.",
                            claimRisk: claimRisk)
        )
    }

    /// Reward rhythm: 3+ distinct days fed this week (SPEC §13 well-fed bonus).
    static func wellFed(displayName: String, claimRisk: Bool) -> GuildNotificationContent {
        GuildNotificationContent(
            title: "\(displayName) is well-fed",
            body: qualified("Three days running, your \(displayName) is thriving on the rhythm.",
                            claimRisk: claimRisk)
        )
    }

    /// A new guild becomes visible (guild-unlock celebration).
    static func guildUnlocked(displayName: String, claimRisk: Bool) -> GuildNotificationContent {
        GuildNotificationContent(
            title: "New crew discovered",
            body: qualified("You've unlocked \(displayName), meet your newest guild.",
                            claimRisk: claimRisk)
        )
    }

    /// A whole district opens (district-unlock celebration). District names are
    /// place-names, not health claims, so no qualifier needed here.
    static func districtUnlocked(name: String) -> GuildNotificationContent {
        GuildNotificationContent(
            title: "A new district is open",
            body: "\(name) just opened, new crews to meet and feed."
        )
    }
}
