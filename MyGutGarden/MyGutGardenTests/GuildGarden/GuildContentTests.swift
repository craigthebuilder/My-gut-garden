//
//  GuildContentTests.swift
//  MyGutGardenTests, Module D content: collectible numbering (must match the
//  reference cards), 🔒 Fence-2 claim-risk propagation, and gain-framed,
//  Fence-2-safe notification copy.
//

import Testing
import Foundation
@testable import MyGutGarden

struct GuildContentTests {

    // MARK: Numbering matches the reference cards

    @Test func collectibleNumberingMatchesReferenceCards() {
        let numbers = GuildGardenAssembler.numbering(districts: GuildSampleData.districts,
                                                     guilds: GuildSampleData.guilds)
        // District order, then alphabetical sans "The". The 2026-08-13
        // de-claiming renames re-alphabetized district 1: Appetite Crew,
        // Base Layer, Lining Keepers (né Anti-inflammatory Arsenal),
        // Recycling Engine.
        #expect(numbers["appetite_crew"] == 1)
        #expect(numbers["base_layer"] == 2)
        #expect(numbers["anti_inflammatory_arsenal"] == 3) // "The Lining Keepers"
        #expect(numbers["estrogen_regulators"] == 9)       // "The Alchemists"
    }

    @Test func numberingIsContiguousAcrossWholeRoster() {
        let numbers = GuildGardenAssembler.numbering(districts: GuildSampleData.districts,
                                                     guilds: GuildSampleData.guilds)
        #expect(Set(numbers.values) == Set(1...GuildSampleData.guilds.count))
    }

    // MARK: Fence 2, claim_risk flags survive the join (Mood/Estrogen/Mito/Tumor)

    @Test func claimRiskGuildsAreFlagged() {
        let built = GuildGardenAssembler.build(districts: GuildSampleData.districts,
                                               guilds: GuildSampleData.guilds,
                                               states: GuildSampleData.states,
                                               unlockedOrders: [1, 2, 3, 4],
                                               now: GuildSampleData.previewNow)
        let byName = Dictionary(built.flatMap(\.guilds).map { ($0.internalName, $0) }) { a, _ in a }
        for risky in ["mood_regulators", "estrogen_regulators", "mitochondria_boosters", "tumor_preventors"] {
            #expect(byName[risky]?.claimRisk == true, "\(risky) must be claim_risk (Fence 2)")
        }
        // Backbone crews are established science, not claim-risk.
        #expect(byName["base_layer"]?.claimRisk == false)
        #expect(byName["anti_inflammatory_arsenal"]?.claimRisk == false)
    }

    // MARK: On-read decay flows through the assembler

    @Test func assemblerAppliesOnReadDecay() {
        let cal = Calendar(identifier: .gregorian)
        let fedAt = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000))
        let state = GuildStateRow(guildId: "base_layer", nourishmentScore: 100,
                                  bloomState: "blooming", lastFedAt: fedAt, daysFedThisWeek: 1)
        let sixDaysLater = Date(timeIntervalSince1970: 1_700_000_000 + 6 * 86_400)
        let display = GuildGardenAssembler.bloomDisplay(for: state, now: sixDaysLater, calendar: cal)
        #expect(display.score < 50)               // 100 faded past half in 6 days
        #expect(display.state != .blooming)        // and dropped out of Blooming
    }

    // MARK: Notification content, gain-framed + Fence-2-safe

    @Test func hungryNotificationIsGainFramed() {
        let n = GuildNotifications.hungry(displayName: "The Anti-inflammatory Arsenal",
                                          feedSuggestion: "resistant starch", claimRisk: false)
        #expect(n.body.contains("hungry"))
        #expect(n.body.contains("resistant starch"))
        #expect(!n.body.lowercased().contains("emerging science"))
    }

    @Test func noNotificationCarriesTheRetiredEmergingScienceQualifier() {
        // Owner (2026-07-02): the visible emerging-science disclaimer is retired
        // app-wide, pushes included. claim_risk stays in the data as the
        // RD-review ledger (FENCES.md Fence 1) but must not alter user copy.
        let hungry = GuildNotifications.hungry(displayName: "The Messengers",
                                               feedSuggestion: "oats and seeds", claimRisk: true)
        let bloomed = GuildNotifications.bloomed(displayName: "The Alchemists", claimRisk: true)
        let wellFed = GuildNotifications.wellFed(displayName: "The Lignan Weavers", claimRisk: true)
        let unlocked = GuildNotifications.guildUnlocked(displayName: "The Spark Tenders", claimRisk: true)
        for n in [hungry, bloomed, wellFed, unlocked] {
            #expect(!n.body.lowercased().contains("emerging science"), "retired qualifier resurfaced: \(n.body)")
        }
    }

    @Test func districtNotificationNeedsNoClaimQualifier() {
        // District names are place-names, not health claims.
        let n = GuildNotifications.districtUnlocked(name: "The Keystones")
        #expect(n.body.contains("The Keystones"))
        #expect(!n.body.lowercased().contains("emerging science"))
    }
}
