//
//  PatModels.swift
//  MyGutGarden — Module F (Survive pattern engine), SPEC §11b / §13.
//
//  Pure data types for the rule-based Survive pattern engine. NO clinical
//  decisions live here — those are isolated in `PatRules.swift` behind FENCE 1.
//  These types mirror the DB enums (`pattern_kind` / `pattern_confidence` in
//  20260625000001_schema.sql) and carry the engine's input/output.
//
//  ⚠️ The engine NEVER emits a diagnosis, a named condition (SIBO/IBS/IMO), a
//  named bug, or an accumulating bad-guy meter. Output is structurally
//  pattern → experiment → confirm (SPEC §11b, CLAUDE.md hard rule #4).
//

import Foundation

// MARK: - Output enums (mirror Postgres `pattern_kind` / `pattern_confidence`)

/// The leaning patterns the engine can surface. Raw values match the DB
/// `pattern_kind` enum. These name a *signal lean*, never a diagnosis.
enum PatPattern: String, Sendable, CaseIterable, Equatable {
    case methane                              // bloat + constipation lean
    case h2s                                  // sulfur gas + looser stools lean
    case hydrogenSibo = "hydrogen_sibo"       // odorless gas + bloat lean
    case fat                                  // worse-after-fatty lean
    case histamine                            // aged/fermented-food lean
    case proteolytic                          // sour gas + low-fiber lean
}

/// Confidence tier — purely a function of how long we've been logging
/// (SPEC §13 timing), NOT of how "sure" the clinical claim is. Raw values
/// match the DB `pattern_confidence` enum.
enum PatConfidence: String, Sendable, CaseIterable, Equatable {
    case tentative      // ≥ patternMinDays
    case emerging       // ≥ patternEmergingDays
    case consistent     // ≥ patternConsistentDays
}

// MARK: - Coarse symptom descriptors (never precise measurements)

/// Stool form bucketed from the Bristol Stool Scale (1–7). Coarse + directional,
/// in keeping with "never claim precision the camera can't deliver" (rule #3).
enum PatStoolForm: String, Sendable, Equatable {
    case constipated    // BSS 1–2
    case normal         // BSS 3–5
    case loose          // BSS 6–7

    init?(bss: Int?) {
        switch bss {
        case 1, 2: self = .constipated
        case 3, 4, 5: self = .normal
        case 6, 7: self = .loose
        default: return nil
        }
    }
}

/// Gas-odor descriptor — "the single most discriminating cheap signal"
/// (SPEC §11b/§12). Mirrors the DB `gas_odor` enum.
enum PatGasOdor: String, Sendable, Equatable {
    case sulfur
    case sour
    case odorless

    init?(raw: String?) {
        guard let raw else { return nil }
        self.init(rawValue: raw)
    }
}

// MARK: - Engine input (one day's evening check)

/// The normalized feature view of a single symptom log the engine reasons over.
///
/// `SymptomLogRow` (the wire/DB type, owned by the data layer) currently only
/// surfaces `bss`, `gasOdor`, and `confounders`, so the adapter fills the
/// corresponding fields and leaves the rest `nil`. The richer slots
/// (`bloating`, `worseAfterFatty`, `agedOrFermentedTrigger`, …) exist so the
/// fingerprint machinery is built *fully* — when the data layer starts
/// surfacing those columns (they exist in `symptom_logs`: bloating/gas/pain/
/// urgency/mood/brain_fog/food_correlation), the rules already consume them.
/// See the "input gap" note in `PatPatternEngine`.
struct PatSymptomFeatures: Sendable, Equatable {
    /// The calendar day this check belongs to (engine buckets by UTC day).
    var day: Date

    // --- Surfaced today by SymptomLogRow ---
    var stool: PatStoolForm?
    var gasOdor: PatGasOdor?
    /// Confounder tags (sick/stressed/poor_sleep/traveled/new_meds/menstruating).
    /// A non-empty list down-weights this day in the fingerprint (SPEC §12).
    var confounders: [String]

    // --- Modeled but not yet on SymptomLogRow (severity 0…3 placeholder scale) ---
    var bloating: Int?
    var gas: Int?
    var pain: Int?
    var urgency: Int?
    var mood: Int?
    var brainFog: Int?

    /// food-correlation signals (from `symptom_logs.food_correlation`, not yet
    /// decoded by the data layer). Drive the fat / histamine leans.
    var worseAfterFatty: Bool?
    var agedOrFermentedTrigger: Bool?
    var flushingOrHeadache: Bool?
    var lowFiberHighProtein: Bool?

    init(
        day: Date,
        stool: PatStoolForm? = nil,
        gasOdor: PatGasOdor? = nil,
        confounders: [String] = [],
        bloating: Int? = nil,
        gas: Int? = nil,
        pain: Int? = nil,
        urgency: Int? = nil,
        mood: Int? = nil,
        brainFog: Int? = nil,
        worseAfterFatty: Bool? = nil,
        agedOrFermentedTrigger: Bool? = nil,
        flushingOrHeadache: Bool? = nil,
        lowFiberHighProtein: Bool? = nil
    ) {
        self.day = day
        self.stool = stool
        self.gasOdor = gasOdor
        self.confounders = confounders
        self.bloating = bloating
        self.gas = gas
        self.pain = pain
        self.urgency = urgency
        self.mood = mood
        self.brainFog = brainFog
        self.worseAfterFatty = worseAfterFatty
        self.agedOrFermentedTrigger = agedOrFermentedTrigger
        self.flushingOrHeadache = flushingOrHeadache
        self.lowFiberHighProtein = lowFiberHighProtein
    }

    var hasConfounder: Bool { !confounders.isEmpty }
}

// MARK: - Engine output

/// A surfaced pattern lean. `evidenceSummary` describes the *signal* and points
/// to an experiment + a GI conversation — it is NEVER a verdict (FENCE 1).
struct PatAssessment: Sendable, Equatable {
    let pattern: PatPattern
    let confidence: PatConfidence
    let evidenceSummary: String
}

/// The "still gathering signal" state (SPEC §13: "9 more days of logs to spot
/// your first pattern"). Carries the counts so Module E can render progress.
struct PatGatheringProgress: Sendable, Equatable {
    let loggedDays: Int
    let symptomaticDays: Int
    let minLoggedDays: Int
    let minSymptomaticDays: Int
    /// Calm, non-clinical progress copy. Never names a condition.
    let message: String
}

/// Full result of an evaluation: either we're still gathering, or we have a
/// lean. `assess(...)` is the thin wrapper that returns the lean or `nil`.
enum PatEvaluation: Sendable, Equatable {
    case gathering(PatGatheringProgress)
    case lean(PatAssessment)
}
