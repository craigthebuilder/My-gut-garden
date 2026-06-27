//
//  OnbModels.swift
//  MyGutGarden, Module A: the remaining intake value types (SPEC §6).
//
//  Goals (multi-select + soft-routing lean), baseline mood/energy/clarity/bowel,
//  curated success stories, red-flag symptoms, and serious-condition flags.
//  All gain-framed and warm; nobody is ever locked out, conditions and
//  red flags drive disclaimers + click-to-confirm, never hard gates.
//
//  Phase-2 (Batch B): 10-goal set, PlantConsumptionTier, UnitSystem,
//  bowel-consistency baseline, otherAutoimmune serious-condition.
//

import Foundation

// MARK: - Goals + soft routing (SPEC §6)

/// Intake goals (multi-select). Each carries a routing lean used ONLY for the
/// soft suggestion (SPEC §6): relief goals lean Survive, optimization goals lean
/// Thrive. Never a gate.
///
/// Phase-2 (Batch B): expanded to 10 product strings stored in users.goals text[].
/// First five are relief goals (+1 Survive); last five are optimization goals (-1 Thrive).
enum OnbGoal: String, CaseIterable, Identifiable, Sendable {
    case calmIbs             = "calm_ibs"
    case easeBloating        = "ease_bloating"
    case findTriggers        = "find_triggers"
    case relieveConstipation = "relieve_constipation"
    case ibdAutoimmune       = "ibd_autoimmune"
    case increaseEnergy      = "increase_energy"
    case decreaseBrainFog    = "decrease_brain_fog"
    case regulateMood        = "regulate_mood"
    case clearSkin           = "clear_skin"
    case justCurious         = "just_curious"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calmIbs:             "Calm IBS flare-ups"
        case .easeBloating:        "Ease bloating"
        case .findTriggers:        "Find my triggers"
        case .relieveConstipation: "Relieve constipation"
        case .ibdAutoimmune:       "Help with IBD or Autoimmune issues"
        case .increaseEnergy:      "Increase energy"
        case .decreaseBrainFog:    "Decrease brain fog"
        case .regulateMood:        "Regulate mood swings"
        case .clearSkin:           "Clear my skin"
        case .justCurious:         "Just curious"
        }
    }

    var systemImage: String {
        switch self {
        case .calmIbs:             "heart.text.square"
        case .easeBloating:        "wind"
        case .findTriggers:        "magnifyingglass"
        case .relieveConstipation: "arrow.down.circle"
        case .ibdAutoimmune:       "cross.case"
        case .increaseEnergy:      "bolt"
        case .decreaseBrainFog:    "brain.head.profile"
        case .regulateMood:        "waveform.path.ecg"
        case .clearSkin:           "sparkles"
        case .justCurious:         "questionmark.circle"
        }
    }

    /// +1 leans Survive (relief), -1 leans Thrive (optimization).
    /// First five are relief goals; last five are optimization goals.
    var routingLean: Int {
        switch self {
        case .calmIbs, .easeBloating, .findTriggers, .relieveConstipation, .ibdAutoimmune:
            1
        case .increaseEnergy, .decreaseBrainFog, .regulateMood, .clearSkin, .justCurious:
            -1
        }
    }
}

/// Soft routing (SPEC §6): a SUGGESTION from goals (+ any relief/red-flag
/// signal), never a gate. Either mode is one tap away. PURE + testable.
enum OnbRouting {
    static func suggestedMode(goals: Set<OnbGoal>, hasReliefSignal: Bool) -> AppMode {
        if hasReliefSignal { return .survive }   // active distress -> start with relief
        let lean = goals.reduce(0) { $0 + $1.routingLean }
        return lean > 0 ? .survive : .thrive
    }

    /// Calm, honest rationale shown beside the suggestion (no diagnosis).
    static func rationale(for mode: AppMode) -> String {
        switch mode {
        case .survive:
            "You mentioned relief. Survive helps you spot triggers and feel steady first. You can switch to Thrive any time."
        case .thrive:
            "You are here to optimize. Thrive turns variety into a garden you grow, and Survive is one tap away if a flare hits."
        }
    }
}

// MARK: - Unit system (display only; canonical storage is always cm/kg)

/// Controls how height and weight are displayed in Q2. All math and storage
/// use metric (cm/kg) regardless of this setting.
enum UnitSystem: String, CaseIterable, Sendable, Hashable {
    case metric, us

    var displayName: String {
        switch self {
        case .metric: "Metric"
        case .us: "US / Imperial"
        }
    }
}

// MARK: - Plant-food consumption tier (SPEC §6, Batch B)

/// Four-level self-reported estimate of overall plant-food intake.
/// Written to users.plant_consumption_level; drives the fiber-goal multiplier.
/// // RD-REVIEW-REQUIRED: tier labels and multiplier values are clinical; confirm before launch.
enum PlantConsumptionTier: String, CaseIterable, Sendable, Hashable {
    case low        = "low"
    case moderate   = "moderate"
    case high       = "high"
    case mostOfDiet = "most_of_diet"

    var displayName: String {
        switch self {
        case .low:        "Mostly packaged or processed"
        case .moderate:   "A mix, some fruits and veg"
        case .high:       "Lots of plants and whole foods"
        case .mostOfDiet: "Plants make up most of my diet"
        }
    }
}

// MARK: - Baseline (the "Is it working?" before, SPEC §6, §11a)

/// Onboarding baseline on a 1-5 scale; gives the Thrive dashboard a before.
///
/// Phase-2 (Batch B):
///   mood is NOW presented as Regulated(1, best) -> Erratic(5, worst) in the UI.
///   It is stored CANONICAL high=better via 6 - uiValue at write time; only the
///   INVERSION in usersWriteBody() is the canonical storage point. The field here
///   holds the raw UI value, NOT the stored value.
///   bowelConsistency added: 1=Inconsistent..5=Consistent (high=better, canonical,
///   no inversion needed).
struct OnbBaseline: Equatable, Sendable {
    /// UI value 1=Regulated(best)..5=Erratic(worst). INVERTED at write: stored as 6 - mood.
    var mood = 3
    var energy = 3
    var clarity = 3
    /// 1=Inconsistent..5=Consistent (high=better, canonical, no inversion).
    var bowelConsistency = 3
}

// MARK: - Social proof (SPEC §5 `success_stories`, §6)

/// Decoded `success_stories` row. Truthful + representative only, the data
/// layer never fabricates; if none load (e.g. offline) the section is hidden
/// rather than filled with a made-up claim (SPEC §2).
struct OnbSuccessStory: Decodable, Identifiable, Sendable {
    let id: String
    let text: String
    let attribution: String?
    let verified: Bool
}

// MARK: - Lightweight food search hit (specific-food exclusions)

/// A `foods` row trimmed for the intake exclusion search (real `id` so a
/// specific-food exclusion writes a valid FK).
struct OnbFoodHit: Decodable, Identifiable, Sendable, Hashable {
    let id: String
    let canonicalName: String
}

// MARK: - Disclaimers (SPEC §6, never a block)

/// Red-flag symptoms (SPEC §6 / §11b). Selecting any triggers a "please also see
/// a doctor" CARE PROMPT, a recommendation, NEVER a block.
// RD-REVIEW-REQUIRED: red-flag list + wording is clinical-adjacent; a clinician
// should confirm the set and copy before launch.
struct OnbRedFlag: Identifiable, Sendable, Hashable {
    var id: String { key }
    let key: String
    let label: String

    static let all: [OnbRedFlag] = [
        .init(key: "blood",               label: "Blood in your stool"),
        .init(key: "weight_loss",         label: "Unexplained weight loss"),
        .init(key: "persistent_vomiting", label: "Persistent vomiting"),
        .init(key: "trouble_swallowing",  label: "Trouble swallowing"),
        .init(key: "fever_with_diarrhea", label: "Fever with diarrhea"),
        .init(key: "night_symptoms",      label: "Symptoms that wake you at night"),
    ]
}

/// Serious conditions that warrant a disclaimer + acknowledgment at intake
/// (SPEC §6). Celiac additionally PROPOSES a loud gluten exclusion
/// (medical_allergy, §9), proposed and removable, never silently added.
/// Phase-2 (Batch B): otherAutoimmune added FIRST; writes users.other_autoimmune=true
/// but proposes NO universal exclusion (unlike celiac).
// RD-REVIEW-REQUIRED: disclaimer copy is clinical-adjacent; confirm before launch.
struct OnbSeriousCondition: Identifiable, Sendable, Hashable {
    var id: String { key }
    let key: String
    let label: String

    /// Phase-2: added first. Writes users.other_autoimmune; proposes no exclusion.
    static let otherAutoimmune = OnbSeriousCondition(key: "other_autoimmune",
                                                     label: "Another autoimmune condition")
    static let celiac = OnbSeriousCondition(key: "celiac", label: "Celiac disease")
    static let ibd    = OnbSeriousCondition(key: "ibd",    label: "IBD (Crohn's or colitis)")

    // otherAutoimmune is intentionally FIRST per Batch B spec.
    static let all: [OnbSeriousCondition] = [otherAutoimmune, celiac, ibd]
}
