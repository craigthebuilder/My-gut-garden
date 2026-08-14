//
//  OnbModels.swift
//  MyGutGarden, Module A: the remaining intake value types (SPEC §6).
//
//  Goals (multi-select personalization strings), baseline mood/energy/clarity,
//  curated success stories, red-flag symptoms, and serious-condition flags.
//  All gain-framed and warm; nobody is ever locked out, conditions and
//  red flags drive disclaimers + click-to-confirm, never hard gates.
//
//  Single-mode: no routing, no modes. 10-goal set, PlantConsumptionTier,
//  UnitSystem.
//

import Foundation

// MARK: - Goals (SPEC §6)

/// Intake goals (multi-select), stored as plain personalization strings in
/// `users.goals` (text[]). Single-mode: goals no longer route anywhere; they
/// simply shape what the app highlights first.
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
        case .calmIbs:             "Calmer, more comfortable digestion"
        case .easeBloating:        "Ease bloating"
        case .findTriggers:        "Find my triggers"
        case .relieveConstipation: "Relieve constipation"
        case .ibdAutoimmune:       "Support alongside a diagnosed condition"
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

/// Onboarding baseline on a 1-5 scale; gives the home dashboard a before.
///
/// mood is presented as Regulated(1, best) -> Erratic(5, worst) in the UI, then
/// stored CANONICAL high=better via `6 - uiValue` at write time. The single
/// inversion point is `OnbViewModel.usersWriteBody()`; the field here holds the
/// raw UI value, NOT the stored value.
struct OnbBaseline: Equatable, Sendable {
    /// UI value 1=Regulated(best)..5=Erratic(worst). INVERTED at write: stored as 6 - mood.
    var mood = 3
    var energy = 3
    var clarity = 3
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

// MARK: - Lightweight food search hit (specific-food flags)

/// A `foods` row trimmed for the intake food-flag search (real `id` so a
/// specific-food flag writes a valid `food_id` FK).
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
/// (SPEC §6). Celiac additionally PROPOSES a loud gluten `food_flag`
/// (`flag_tier = allergy`, §9), proposed and removable, never silently added.
/// otherAutoimmune is listed FIRST but proposes no flag and persists no column
/// (single-mode: `other_autoimmune` was retired); it drives disclaimer copy only.
// RD-REVIEW-REQUIRED: disclaimer copy is clinical-adjacent; confirm before launch.
struct OnbSeriousCondition: Identifiable, Sendable, Hashable {
    var id: String { key }
    let key: String
    let label: String

    /// Listed first. Drives disclaimer copy only; proposes no flag, persists no column.
    static let otherAutoimmune = OnbSeriousCondition(key: "other_autoimmune",
                                                     label: "Another autoimmune condition")
    static let celiac = OnbSeriousCondition(key: "celiac", label: "Celiac disease")
    static let ibd    = OnbSeriousCondition(key: "ibd",    label: "IBD (Crohn's or colitis)")

    // otherAutoimmune is intentionally FIRST per Batch B spec.
    static let all: [OnbSeriousCondition] = [otherAutoimmune, celiac, ibd]
}
