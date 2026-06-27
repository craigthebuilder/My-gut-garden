//
//  OnbExclusions.swift
//  MyGutGarden, Module A: the two-faced exclusion model at intake.
//
//  ⚠️ LOAD-BEARING (SPEC §9 / CLAUDE.md hard rule #1). Every exclusion is tagged
//  with an `ExclusionType` that drives OPPOSITE downstream behavior:
//    • medicalAllergy        → LOUD across both modes, elevated hidden-ingredient
//                              sensitivity. Cost of a miss = harm.
//    • preferenceIntolerance → quiet, silently omitted, no nagging. Cost = discomfort.
//  This file NEVER collapses the two into one flat "excluded foods" list. The
//  scope (specific food OR category) and the type are kept as distinct fields all
//  the way to the write body.
//
//  The branching + write-body logic here is PURE and unit-tested
//  (MyGutGardenTests/Onboarding).
//

import Foundation

/// What an exclusion is scoped to: a specific food (a real `foods.id`) OR a
/// category like "gluten" / "allium" (SPEC §9 examples). Exactly one is stored;
/// the DB CHECK requires `food_id is not null OR category is not null`.
enum OnbExclusionScope: Sendable, Hashable {
    case food(id: String, name: String)
    case category(key: String, label: String)

    var displayName: String {
        switch self {
        case let .food(_, name): name
        case let .category(_, label): label
        }
    }
}

/// A drafted exclusion before it is written. Carries the load-bearing
/// `exclusionType` alongside (never merged into) the scope.
struct OnbDraftExclusion: Identifiable, Sendable, Hashable {
    let id = UUID()
    var scope: OnbExclusionScope
    var exclusionType: ExclusionType

    var displayName: String { scope.displayName }
}

/// The §9 behavior that `exclusion_type` drives, surfaced as a pure value so the
/// "two-faced" branching lives in ONE tested place instead of scattered `==`
/// checks across modules. (Module A only needs it for intake copy/affordances;
/// the food surfaces re-derive their own, but the truth table is identical.)
struct OnbExclusionBehavior: Equatable, Sendable {
    /// Fires across BOTH modes, even mid-celebration (medical allergy, §9).
    let isLoud: Bool
    /// Flag hidden-ingredient dishes aggressively (elevated sensitivity, §9).
    let elevatedHiddenIngredientSensitivity: Bool
    /// Silently omitted in the Thrive photo view, no nagging (§9).
    let silentlyOmitted: Bool

    static func of(_ type: ExclusionType) -> OnbExclusionBehavior {
        switch type {
        case .medicalAllergy:
            OnbExclusionBehavior(isLoud: true,
                                 elevatedHiddenIngredientSensitivity: true,
                                 silentlyOmitted: false)
        case .preferenceIntolerance:
            OnbExclusionBehavior(isLoud: false,
                                 elevatedHiddenIngredientSensitivity: false,
                                 silentlyOmitted: true)
        }
    }

    /// One-line, gain-/clarity-framed explainer shown beside the type toggle so
    /// the user makes the §9 distinction deliberately (a celiac's gluten is not
    /// an onion preference).
    static func explainer(_ type: ExclusionType) -> String {
        switch type {
        case .medicalAllergy:
            "We'll flag this loudly, even when it's a hidden ingredient."
        case .preferenceIntolerance:
            "We'll just leave this off your suggestions. No alerts."
        }
    }
}

/// Builds the PostgREST write body for one exclusion. PURE + unit-tested.
enum OnbExclusionWriter {
    /// Includes `user_id` and the load-bearing `exclusion_type`, and sets
    /// `food_id` XOR `category` to match the scope (the DB CHECK requires at
    /// least one). NEVER flattens scope + type into a single blob.
    static func insertBody(userId: String, draft: OnbDraftExclusion) -> [String: PGValue] {
        var body: [String: PGValue] = [
            "user_id": .string(userId),
            "exclusion_type": .string(draft.exclusionType.rawValue),
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

/// Curated common exclusion categories shown as chips at intake (SPEC §9 names
/// categories like "gluten", "allium"). `commonAllergen` only PRE-SELECTS the
/// type toggle as a sensible default that leans toward the safer (loud)
/// direction for the foods most likely to be true allergies, the user ALWAYS
/// chooses and can flip it. We never auto-classify on the user's behalf.
struct OnbExclusionCategory: Identifiable, Sendable, Hashable {
    var id: String { key }
    let key: String
    let label: String
    let commonAllergen: Bool

    /// Pre-selection only, leans loud for likely allergens, quiet otherwise.
    var suggestedType: ExclusionType { commonAllergen ? .medicalAllergy : .preferenceIntolerance }

    // RD-REVIEW-REQUIRED: the category list + allergen flags are an opinionated
    // starter set; a dietitian should confirm coverage/labels before launch.
    static let curated: [OnbExclusionCategory] = [
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
