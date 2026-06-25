//
//  GuildConfig.swift
//  MyGutGarden — Module D (Guild Garden) tunables that aren't already in
//  GameConfig. Kept in ONE place (CLAUDE.md §5): nobody hardcodes a magic
//  number for a district-unlock gate.
//
//  The shared bloom/decay/feeding numbers live in `GameConfig` (portion +
//  relevance weights, `guildDecayPerDay`, bloom thresholds, the consistent-
//  feeding bonus, `district3MinCumulativeTier2Days`). This struct only adds the
//  district-unlock bloom counts that GameConfig doesn't carry, so the §13 gates
//  are expressed against named constants, not literals.
//

import Foundation

/// District-unlock thresholds (SPEC §13). Adjustable without code changes.
struct GuildConfig: Sendable {
    static let shared = GuildConfig()

    /// D2 Keystones unlock when ≥ this many Backbone (D1) guilds have ever bloomed.
    let backboneBloomsForD2 = 2
    /// D3 Scientists unlock when ≥ this many Keystone (D2) guilds have ever
    /// bloomed (plus `GameConfig.district3MinCumulativeTier2Days` cumulative days).
    let keystoneBloomsForD3 = 1
    /// D4 Hidden Gems unlock "after D3 engagement": ≥ this many Scientist (D3)
    /// guilds have ever bloomed (the endgame gate).
    let scientistBloomsForD4 = 1

    /// District `order` values, in sequence (SPEC §8/§13).
    let backboneOrder = 1
    let keystoneOrder = 2
    let scientistOrder = 3
    let hiddenGemsOrder = 4
}
