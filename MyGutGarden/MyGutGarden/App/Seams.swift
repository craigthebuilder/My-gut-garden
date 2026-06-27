//
//  Seams.swift
//  MyGutGarden, the inter-module contracts, fixed BEFORE fan-out so the
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

/// What B persists + passes to the mode-specific insight view. The food-status
/// fields are filled by the injected SuspectCheckService BEFORE auto-log (Module B
/// reads them; Module E supplies the real impl). Defaulted so B's construction
/// sites and previews stay source-compatible.
struct ConfirmedMeal: Sendable, Identifiable {
    let id: UUID
    let response: RecognitionResponse
    let capturedAt: Date
    var suspectFoodIds: [String] = []   // status='suspect', avoid=false, not reintroducing
    var avoidFoodIds: [String] = []     // avoid=true
    var reintroFoodId: String? = nil    // a food in the user's active food_suspect challenge present here
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

// MARK: - Celebration channel (anyone emits; AppShell presents, Thrive only)

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

// MARK: - Survive care-prompt channel (Batch E)
//
// Deliberately SEPARATE from CelebrationEvent: restriction is never juice (rule #7).
// Unlike `AppState.celebrate(_:)` this fires in EITHER mode, it is a care prompt,
// not a reward, and is presented as a calm, dismissible question, never confetti.

enum SurvivePromptEvent: Sendable, Identifiable {
    case switchToSurvivePrompt(avoidCount: Int)   // offered when ≥ N foods are set aside
    case graduateToThrive                          // offered when the reset is complete
    case offerSurvive                              // offered right after onboarding (R5 #4)

    var id: String {
        switch self {
        case let .switchToSurvivePrompt(n): "switch-survive-\(n)"
        case .graduateToThrive: "graduate-thrive"
        case .offerSurvive: "offer-survive"
        }
    }
}

// MARK: - Food-status read seam (Module E owns the store; B/C read through this)
//
// Keeps Capture (Module B) and Thrive Today (Module C) ignorant of Module E types.
// The default is a no-op so the spine + any module compiles without E wired in.

protocol SuspectCheckService: Sendable {
    func suspectFoodIds(for userId: String) async -> Set<String>   // suspect, NOT reintroducing
    func avoidFoodIds(for userId: String) async -> Set<String>     // avoid = true
    func reintroFoodIds(for userId: String) async -> Set<String>   // active food_suspect challenge
}

struct NoopSuspectCheckService: SuspectCheckService {
    func suspectFoodIds(for userId: String) async -> Set<String> { [] }
    func avoidFoodIds(for userId: String) async -> Set<String> { [] }
    func reintroFoodIds(for userId: String) async -> Set<String> { [] }
}

private struct SuspectCheckServiceKey: EnvironmentKey {
    static let defaultValue: any SuspectCheckService = NoopSuspectCheckService()
}
extension EnvironmentValues {
    var suspectCheckService: any SuspectCheckService {
        get { self[SuspectCheckServiceKey.self] }
        set { self[SuspectCheckServiceKey.self] = newValue }
    }
}

/// Module E injects the real write; default is a no-op. Called by Module B after a
/// meal containing the active reintro food is auto-logged, to attach the
/// "How did the [food] feel?" card whose answer writes back via CheckInWriter.
typealias ReintroFeelingAttacher = @Sendable (_ reintroFoodId: String, _ mealId: String) async -> Void

private struct ReintroFeelingAttacherKey: EnvironmentKey {
    static let defaultValue: ReintroFeelingAttacher = { _, _ in }
}
extension EnvironmentValues {
    var reintroFeelingAttacher: ReintroFeelingAttacher {
        get { self[ReintroFeelingAttacherKey.self] }
        set { self[ReintroFeelingAttacherKey.self] = newValue }
    }
}
