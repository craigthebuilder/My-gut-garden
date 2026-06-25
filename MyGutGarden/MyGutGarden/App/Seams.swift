//
//  Seams.swift
//  MyGutGarden — the inter-module contracts, fixed BEFORE fan-out so the
//  orchestrator can wire modules at consolidation without editing any of them.
//  Modules conform to these; the MealIngestion coordinator + AppShell consume
//  them. (Red-team mitigation: removes the shared-write-path collisions.)
//

import SwiftUI

// MARK: - Meal context (input to the ingestion seam)

/// One confirmed, surfaced meal item (preference_intolerance items are already
/// dropped per §9). Portion drives feeding weight; attributes drive everything.
struct IngestedItem: Sendable {
    let attributes: FoodAttributes
    let portion: PortionTier
}

/// The confirmed meal as the ingestors see it.
struct MealContext: Sendable {
    let loggedAt: Date
    let items: [IngestedItem]

    /// Build from a recognize response, keeping only surfaced (non-omitted) items.
    static func from(_ response: RecognitionResponse, loggedAt: Date) -> MealContext {
        let items = response.items.compactMap { item -> IngestedItem? in
            guard item.silentlyOmitted != true, let attrs = item.attributes else { return nil }
            return IngestedItem(attributes: attrs, portion: item.vision.portionTier)
        }
        return MealContext(loggedAt: loggedAt, items: items)
    }
}

// MARK: - Guild ingestion (Module D owns; coordinator applies decay-then-add)

/// Minimal guild-state snapshot D needs to evaluate district unlocks (§13).
struct GuildBloomSnapshot: Sendable {
    let districtOrder: Int
    let isBlooming: Bool
    let hasEverBloomed: Bool
}

/// D provides PURE functions; the coordinator owns the `guild_state` writes
/// (decay from `last_fed_at`, then add) and the `user_districts` writes.
protocol GuildIngesting: Sendable {
    /// internal_name → feeding points for this meal (GameConfig.feedingPoints).
    func guildFeedingPoints(for context: MealContext) -> [String: Int]
    /// Which district `order`s should be unlocked given current bloom snapshots
    /// + cumulative days in Tier 2.
    func unlockedDistrictOrders(snapshots: [GuildBloomSnapshot], cumulativeTier2Days: Int) -> Set<Int>
}

// MARK: - Thrive collection/streak ingestion (Module C owns; coordinator writes)

/// Thrive streak counters (positive outcomes only, §14 / rule #7).
struct ThriveStreaks: Sendable, Equatable {
    var weekly30Streak: Int = 0      // consecutive weeks hitting 30 plants
    var dailyThreePStreak: Int = 0   // consecutive days with all 3 P's
}

/// C provides PURE functions; the coordinator owns `user_plant_collection`,
/// `weekly_summaries`, and streak writes.
protocol ThriveIngesting: Sendable {
    func plantNames(for context: MealContext) -> [String]
    func threePs(for context: MealContext) -> ThreePs
    func updatedStreaks(_ current: ThriveStreaks, weekHit30: Bool, threePsToday: ThreePs) -> ThriveStreaks
}

// MARK: - Per-photo insight injection (Module B hands off → C/E render)

/// What B persists + passes to the mode-specific insight view.
struct ConfirmedMeal: Sendable, Identifiable {
    let id: UUID
    let response: RecognitionResponse
    let capturedAt: Date
}

/// C and E each supply a presenter; the AppShell injects the one matching the
/// current mode, so B never imports C/E.
@MainActor
protocol MealInsightPresenting {
    func insightView(for meal: ConfirmedMeal) -> AnyView
}

private struct MealInsightPresenterKey: EnvironmentKey {
    static let defaultValue: (any MealInsightPresenting)? = nil
}
extension EnvironmentValues {
    var mealInsightPresenter: (any MealInsightPresenting)? {
        get { self[MealInsightPresenterKey.self] }
        set { self[MealInsightPresenterKey.self] = newValue }
    }
}

// MARK: - Celebration channel (anyone emits; AppShell presents — Thrive only)

enum CelebrationEvent: Sendable, Identifiable {
    case rareFind(plant: String, rarity: RarityTier)
    case guildBloom(displayName: String)
    case guildUnlock(displayName: String)
    case districtUnlock(name: String)
    case graduation

    var id: String {
        switch self {
        case let .rareFind(p, r): "rare-\(p)-\(r.rawValue)"
        case let .guildBloom(n): "bloom-\(n)"
        case let .guildUnlock(n): "unlock-\(n)"
        case let .districtUnlock(n): "district-\(n)"
        case .graduation: "graduation"
        }
    }
}

// MARK: - Progression read surface (Module D writes via coordinator; C/D read)

struct ProgressionState: Sendable, Equatable {
    var isTier2Unlocked: Bool = false
    var unlockedDistrictOrders: Set<Int> = []
    var cumulativeTier2Days: Int = 0
}
