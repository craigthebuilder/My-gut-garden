//
//  GuildSampleData.swift
//  MyGutGarden, PREVIEW-ONLY sample roster for the guild garden showcase.
//
//  ⚠️ This is SwiftUI-preview / showcase scaffolding, NOT seed content. The real
//  districts/guilds/guild_state come from Supabase via `Repository` at runtime
//  (workstream G owns the seed in /data). It mirrors the framework §4 roster so
//  the map + cards render meaningfully offline. `claim_risk` is set exactly per
//  Fence 2 (Mood / Estrogen / Mitochondria / Tumor = true).
//

import Foundation

enum GuildSampleData {

    /// Fixed clock so preview scores render as authored (no wall-clock decay).
    static let previewNow = Date(timeIntervalSince1970: 1_750_000_000) // 2025-06-15

    private static var nowISO: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: previewNow)
    }

    /// Partial unlock, D1 + D2 open, D3 + D4 still fogged (shows the reveal).
    static let previewProgression = ProgressionState(
        isTier2Unlocked: true,
        unlockedDistrictOrders: [1, 2],
        cumulativeTier2Days: 8
    )

    // MARK: Districts (framework §4, four, in sequence)

    static let districts: [DistrictRow] = [
        DistrictRow(id: "d1", order: 1, name: "The Backbone District", unlockRuleKey: "backbone", worldId: nil),
        DistrictRow(id: "d2", order: 2, name: "The Keystones",          unlockRuleKey: "keystones", worldId: nil),
        DistrictRow(id: "d3", order: 3, name: "The Scientists",         unlockRuleKey: "scientists", worldId: nil),
        DistrictRow(id: "d4", order: 4, name: "The Hidden Gems",        unlockRuleKey: "hidden_gems", worldId: nil),
    ]

    // MARK: Guilds (framework §4 roster; claim_risk per Fence 2)

    static let guilds: [GuildRow] = [
        // ---- District 1, The Backbone District -----------------------------
        guild("anti_inflammatory_arsenal", "d1", "The Lining Keepers", "solid",
              fn: "Butyrate makers that fuel the gut lining — the backbone crew of a well-fed garden.",
              feeds: "resistant starch"),
        guild("appetite_crew", "d1", "The Appetite Crew", "solid",
              fn: "Turns fiber into fuel, studied for its role in feeling satisfied after meals.",
              feeds: "oats and barley"),
        guild("base_layer", "d1", "The Base Layer", "solid",
              fn: "A sturdy barrier builder that reinforces the gut lining and feeds everyone else.",
              feeds: "onion, garlic or chicory"),
        guild("recycling_engine", "d1", "The Recycling Engine", "solid",
              fn: "Tidies up what the Base Layer leaves behind and turns it into more good fuel.",
              feeds: "a steady mix of fibers"),

        // ---- District 2, The Keystones -------------------------------------
        guild("locksmith", "d2", "The Locksmith", "solid",
              fn: "Cracks open tough starch particles so the whole garden can feed.",
              feeds: "cooled rice or potato"),
        guild("knights_of_the_wall", "d2", "The Knights of the Wall", "maturing",
              fn: "Tends the protective mucus barrier that lines a healthy gut.",
              feeds: "pomegranate or green tea"),

        // ---- District 3, The Scientists ------------------------------------
        guild("vitamin_lab", "d3", "The Vitamin Lab", "solid",
              fn: "A micro-factory that helps make vitamins, this is where your 30 plants pay off.",
              feeds: "as much plant variety as you can"),
        // 🔒 Fence 1, claim_risk (renamed 2026-08-13 — de-claimed names for launch)
        guild("mood_regulators", "d3", "The Messengers", "frontier",
              fn: "Makes signal molecules that travel the gut–brain axis.",
              feeds: "oats, seeds and soy",
              claimRisk: true,
              substantiation: "Real research field; food→mood causality is unproven. // RD-REVIEW-REQUIRED"),

        // ---- District 4, The Hidden Gems (personal traits) -----------------
        // 🔒 Fence 1, claim_risk
        guild("estrogen_regulators", "d4", "The Alchemists", "emerging",
              fn: "A rare specialist crew — roughly 1 in 3 people host them — that transmutes soy compounds into equol.",
              feeds: "soy foods",
              claimRisk: true,
              substantiation: "Equol-producer trait; confirmable only by a urine test after a challenge. // RD-REVIEW-REQUIRED"),
        // 🔒 Fence 1, claim_risk
        guild("mitochondria_boosters", "d4", "The Spark Tenders", "emerging",
              fn: "Turns certain fruits into compounds studied for cellular energy.",
              feeds: "pomegranate, walnuts or berries",
              claimRisk: true,
              substantiation: "Urolithin metabotype; early human trials only. // RD-REVIEW-REQUIRED"),
        // 🔒 Fence 1, claim_risk
        guild("tumor_preventors", "d4", "The Lignan Weavers", "associational",
              fn: "Weaves seed lignans into enterolignans, a much-studied gut transformation.",
              feeds: "flax, sesame or rye",
              claimRisk: true,
              substantiation: "Associational only; all outcome language kept out of copy. // RD-REVIEW-REQUIRED"),
        guild("stone_breakers", "d4", "The Stone Breakers", "solid",
              fn: "A niche crew that breaks down oxalate, matters most for kidney-stone formers.",
              feeds: "a varied plant diet"),
    ]

    // MARK: guild_state (a spread of bloom states; fed "now" so no preview decay)

    static let states: [GuildStateRow] = [
        state("anti_inflammatory_arsenal", 86, daysFed: 4),  // Blooming, well-fed
        state("base_layer", 74, daysFed: 3),                 // Blooming, well-fed
        state("appetite_crew", 58, daysFed: 2),              // Growing
        state("recycling_engine", 30, daysFed: 1),           // Sprouting
        state("locksmith", 49, daysFed: 2),                  // Growing
        state("knights_of_the_wall", 24, daysFed: 1),        // Sprouting
        // D3/D4 are fogged in the preview, so they stay unfed (Dormant/.empty).
    ]

    // MARK: builders

    private static func guild(_ internalName: String, _ districtId: String, _ display: String,
                              _ confidence: String, fn: String, feeds: String,
                              claimRisk: Bool = false, substantiation: String? = nil) -> GuildRow {
        GuildRow(id: internalName, districtId: districtId, internalName: internalName,
                 displayName: display, functionCopy: fn, confidenceTag: confidence,
                 feedsCopy: feeds, introCopy: nil, claimRisk: claimRisk, substantiation: substantiation)
    }

    private static func state(_ guildId: String, _ score: Int, daysFed: Int) -> GuildStateRow {
        GuildStateRow(guildId: guildId, nourishmentScore: score,
                      bloomState: GuildBloomState.state(for: Double(score)).rawValue,
                      lastFedAt: nowISO, daysFedThisWeek: daysFed)
    }
}
