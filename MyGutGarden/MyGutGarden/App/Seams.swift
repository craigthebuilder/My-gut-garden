//
//  Seams.swift
//  MyGutGarden — the inter-module contracts. Modules conform to these; the
//  MealIngestion coordinator + AppShell consume them, so modules never import
//  each other. Single-mode: one insight presenter, food restrictions surface
//  server-side via the three-tier flag model (no client suspect seams).
//

import SwiftUI

// MARK: - Meal context (input to the ingestion seam)

/// One confirmed, surfaced meal item. Portion drives feeding weight; attributes
/// drive everything. (Sensitivity foods are still ingested + counted, SPEC §9.)
struct IngestedItem: Sendable {
    let attributes: FoodAttributes
    let portion: PortionTier
}

/// The confirmed meal as the ingestors see it.
struct MealContext: Sendable {
    let loggedAt: Date
    let items: [IngestedItem]

    /// Build from a recognize response — every resolved item is surfaced.
    static func from(_ response: RecognitionResponse, loggedAt: Date) -> MealContext {
        let items = response.items.compactMap { item -> IngestedItem? in
            guard let attrs = item.attributes else { return nil }
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
/// (decay from `last_fed_at`, then add) and the `user_districts` / `user_worlds` writes.
protocol GuildIngesting: Sendable {
    /// internal_name → feeding points for this meal (GameConfig.feedingPoints).
    func guildFeedingPoints(for context: MealContext) -> [String: Int]
    /// Which district `order`s should be unlocked given current bloom snapshots
    /// + cumulative days in Tier 2.
    func unlockedDistrictOrders(snapshots: [GuildBloomSnapshot], cumulativeTier2Days: Int) -> Set<Int>
}

// MARK: - Collection/streak ingestion (Module C owns; coordinator writes)

/// Streak counters (positive outcomes only, rule #7).
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

// MARK: - Per-photo insight injection (Module B hands off → C renders)

/// What B persists + passes to the insight view. The three food-flag tiers are
/// carried by `response` (allergyAlerts + sensitivityFlags, server-computed);
/// Module B no longer computes them client-side.
struct ConfirmedMeal: Sendable, Identifiable {
    let id: UUID
    let response: RecognitionResponse
    let capturedAt: Date
}

/// C supplies the presenter; AppShell injects it so B never imports C.
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

// MARK: - Celebration channel (anyone emits; AppShell presents)

enum CelebrationEvent: Sendable, Identifiable {
    case rareFind(plant: String, rarity: RarityTier)
    case guildBloom(displayName: String)
    case guildUnlock(displayName: String)
    case districtUnlock(name: String)
    case worldUnlock(name: String)

    var id: String {
        switch self {
        case let .rareFind(p, r): "rare-\(p)-\(r.rawValue)"
        case let .guildBloom(n): "bloom-\(n)"
        case let .guildUnlock(n): "unlock-\(n)"
        case let .districtUnlock(n): "district-\(n)"
        case let .worldUnlock(n): "world-\(n)"
        }
    }
}

// MARK: - Guardian prompt channel (SPEC §11)
//
// A SEPARATE channel from CelebrationEvent. The guardian is quiet: it SUGGESTS,
// the user CONFIRMS every move into a stricter tier (rule #8). None of these are
// "juice for restriction" — they are calm, dismissible questions/offers.

enum GuardianPrompt: Sendable, Identifiable, Equatable {
    case fiberGoalIncrease(currentG: Int, proposedG: Int)         // Accept/Decline (+ water reminder)
    case suggestWatching(foodName: String, foodId: String)       // "keep an eye on [food]?"
    case couldBeAllergy(foodName: String, foodId: String)        // care prompt, NEVER a diagnosis
    case overcameSensitivity(foodName: String, foodId: String)   // celebrated demote back into the diet

    var id: String {
        switch self {
        case let .fiberGoalIncrease(c, p): "fiber-\(c)-\(p)"
        case let .suggestWatching(_, f): "watch-\(f)"
        case let .couldBeAllergy(_, f): "allergy-\(f)"
        case let .overcameSensitivity(_, f): "overcame-\(f)"
        }
    }
}

// MARK: - Progression read surface (Module D writes via coordinator; C/D read)

struct ProgressionState: Sendable, Equatable {
    var isTier2Unlocked: Bool = false
    var unlockedWorldOrders: Set<Int> = []
    var unlockedDistrictOrders: Set<Int> = []
    var cumulativeTier2Days: Int = 0
}
