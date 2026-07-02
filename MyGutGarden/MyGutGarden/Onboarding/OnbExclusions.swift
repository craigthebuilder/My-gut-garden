//
//  OnbExclusions.swift
//  MyGutGarden, Module A: capturing food flags at intake (SPEC §9).
//
//  Single-mode rework: the retired two-faced exclusion model is replaced by the
//  three-tier `food_flags` model. Onboarding captures the two HEALTH tiers only:
//    • allergy     → LOUD. Fires BEFORE the result overview, even for hidden
//                    ingredients. Cost of a miss = harm.
//    • sensitivity → soft. A gentle in-overview heads-up; the food is still
//                    eaten + logged. Cost of a miss = discomfort.
//  The quiet `watching` tier is engine-only (never offered at intake), and the
//  old pure-preference path is dropped: everything captured here is health-framed.
//
//  Writes always carry source='user', user_confirmed=true, and food_id XOR
//  category. The write-body logic is PURE (unit-testable in isolation).
//

import Foundation

/// What a food flag is scoped to: a specific food (a real `foods.id`) OR a
/// category like "gluten" / "allium" (SPEC §9 examples). Exactly one is written;
/// the `food_flags` CHECK requires `food_id is not null OR category is not null`.
enum OnbFlagScope: Sendable, Hashable {
    case food(id: String, name: String)
    case category(key: String, label: String)

    var displayName: String {
        switch self {
        case let .food(_, name): name
        case let .category(_, label): label
        }
    }
}

/// A drafted food flag before it is written. Carries the load-bearing `flagTier`
/// (allergy = LOUD, sensitivity = soft) alongside — never merged into — the scope.
/// Intake only ever sets the two health tiers; `watching` is engine-only.
struct OnbDraftFlag: Identifiable, Sendable, Hashable {
    let id = UUID()
    var scope: OnbFlagScope
    var flagTier: FlagTier

    var displayName: String { scope.displayName }
}

/// Intake copy for the tier picker. The downstream surfacing (allergy fires LOUD
/// before the overview; sensitivity is a soft in-overview flag) is driven by
/// `FlagTier` in the food surfaces; here we only need the one-line explainer.
enum OnbFlagBehavior {
    /// Gain-/clarity-framed explainer shown beside the tier toggle so the user
    /// makes the §9 distinction deliberately (a celiac's gluten is not an onion
    /// sensitivity).
    static func explainer(_ tier: FlagTier) -> String {
        switch tier {
        case .allergy:
            "We'll flag this loudly, even when it's a hidden ingredient."
        case .sensitivity:
            "We'll give you a gentle heads-up, but still log it."
        case .watching:
            "We'll quietly keep an eye on this one."
        }
    }
}

/// Builds the PostgREST insert body for one `food_flags` row. PURE + unit-tested.
enum OnbFlagWriter {
    /// Always source='user', user_confirmed=true, and sets `food_id` XOR
    /// `category` to match the scope (the DB CHECK requires at least one).
    /// NEVER flattens scope + tier into a single blob.
    static func insertBody(userId: String, draft: OnbDraftFlag) -> [String: PGValue] {
        var body: [String: PGValue] = [
            "user_id":        .string(userId),
            "flag_tier":      .string(draft.flagTier.rawValue),
            "source":         .string("user"),
            "user_confirmed": .bool(true),
        ]
        switch draft.scope {
        case let .food(id, _):
            body["food_id"] = .string(id)
        case let .category(key, _):
            body["category"] = .string(key)
        }
        return body
    }
}

/// Curated common flag categories shown as chips at intake (SPEC §9 names
/// categories like "gluten", "allium"). `commonAllergen` only PRE-SELECTS the
/// tier toggle toward the safer (loud) `allergy` default for the foods most
/// likely to be true allergies; the user ALWAYS chooses and can flip it. We
/// never auto-classify on the user's behalf.
struct OnbFlagCategory: Identifiable, Sendable, Hashable {
    var id: String { key }
    let key: String
    let label: String
    let commonAllergen: Bool

    /// Pre-selection only: leans `allergy` for likely allergens, `sensitivity`
    /// otherwise. Onboarding never offers the engine-only `watching` tier.
    var suggestedTier: FlagTier { commonAllergen ? .allergy : .sensitivity }

    // RD-REVIEW-REQUIRED: the category list + allergen flags are an opinionated
    // starter set; a dietitian should confirm coverage/labels before launch.
    static let curated: [OnbFlagCategory] = [
        .init(key: "gluten",    label: "Gluten / wheat",  commonAllergen: true),
        .init(key: "dairy",     label: "Dairy / lactose", commonAllergen: true),
        .init(key: "allium",    label: "Onion & garlic",  commonAllergen: false),
        .init(key: "soy",       label: "Soy",             commonAllergen: true),
        .init(key: "egg",       label: "Egg",             commonAllergen: true),
        .init(key: "peanut",    label: "Peanut",          commonAllergen: true),
        .init(key: "tree_nut",  label: "Tree nuts",       commonAllergen: true),
        .init(key: "shellfish", label: "Shellfish",       commonAllergen: true),
        .init(key: "fish",      label: "Fish",            commonAllergen: true),
        .init(key: "sesame",    label: "Sesame",          commonAllergen: true),
    ]
}
