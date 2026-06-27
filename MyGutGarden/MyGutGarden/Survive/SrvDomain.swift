//
//  SrvDomain.swift
//  MyGutGarden, Module E (Survive surface) domain vocabulary.
//
//  Survive-local value types: the symptom severities, the Bristol scale, the
//  gas-odor descriptor (the single most discriminating cheap signal, SPEC §12),
//  confounders, FODMAP reintro groups, reintro statuses, and the pattern leans.
//  These mirror the Postgres enums in 20260625000001_schema.sql so the surface
//  and the data model speak the same words. Pure, deterministic, Sendable, 
//  no UI, no I/O, so the streak/reintro engines (and their tests) build on them.
//
//  Copy here is calm and non-clinical (DESIGN.md "Writing", SPEC §11b). Nothing
//  here names a condition or a bug; the pattern leans are gas-chemistry
//  descriptions, never diagnoses (CLAUDE.md rule #4).
//

import Foundation

// MARK: - Symptom severity (the quick 0–3 tap)

/// Stored as `int` (0–3) in `symptom_logs.{bloating,gas,pain,urgency}`.
/// Comparison is by `rank` (avoids a manual Comparable witness under the
/// project's MainActor-default isolation).
enum SrvSeverity: Int, CaseIterable, Codable, Sendable, Identifiable {
    case none = 0, mild = 1, moderate = 2, severe = 3

    var id: Int { rawValue }
    nonisolated var rank: Int { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Strong"
        }
    }

    init(clampingDBValue value: Int?) {
        self = SrvSeverity(rawValue: max(0, min(3, value ?? 0))) ?? .none
    }
}

// MARK: - Bristol Stool Scale (tap a picture, 1–7)

/// `symptom_logs.bss` (1–7). Neutral, body-literate copy, never alarming.
enum SrvBristolType: Int, CaseIterable, Codable, Sendable, Identifiable {
    case type1 = 1, type2, type3, type4, type5, type6, type7

    var id: Int { rawValue }

    /// SF Symbol placeholder for the "tap a picture" grid (owner art later).
    var systemImage: String {
        switch self {
        case .type1: "circle.grid.3x3.fill"
        case .type2: "circle.grid.2x2.fill"
        case .type3: "capsule.portrait.fill"
        case .type4: "capsule.fill"
        case .type5: "drop.fill"
        case .type6: "cloud.fill"
        case .type7: "wave.3.forward"
        }
    }

    var title: String {
        switch self {
        case .type1: "Separate lumps"
        case .type2: "Lumpy"
        case .type3: "Cracked"
        case .type4: "Smooth"
        case .type5: "Soft blobs"
        case .type6: "Mushy"
        case .type7: "Liquid"
        }
    }

    /// 3–5 read as the comfortable middle; the ends carry more signal.
    nonisolated var deviationSeverity: SrvSeverity {
        switch self {
        case .type4: .none
        case .type3, .type5: .mild
        case .type2, .type6: .moderate
        case .type1, .type7: .severe
        }
    }
}

// MARK: - Gas-odor descriptor (SPEC §12, the cheap discriminator)

/// `symptom_logs.gas_odor` enum ('sulfur','sour','odorless').
enum SrvGasOdor: String, CaseIterable, Codable, Sendable, Identifiable {
    case sulfur, sour, odorless

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sulfur: "Sulfur (eggy)"
        case .sour: "Sour"
        case .odorless: "Odorless"
        }
    }

    var systemImage: String {
        switch self {
        case .sulfur: "smoke.fill"
        case .sour: "wind"
        case .odorless: "wind.circle"
        }
    }
}

// MARK: - Confounders (SPEC §12, one-tap context; freezes the streak)

/// `symptom_logs.confounders text[]`. A confounder-tagged day freezes (never
/// breaks) the symptom-free streak, and the pattern engine down-weights it.
enum SrvConfounder: String, CaseIterable, Codable, Sendable, Identifiable {
    case sick, stressed
    case poorSleep = "poor_sleep"
    case traveled
    case newMeds = "new_meds"
    case menstruating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sick: "Under the weather"
        case .stressed: "Stressed"
        case .poorSleep: "Poor sleep"
        case .traveled: "Traveled"
        case .newMeds: "New meds"
        case .menstruating: "Menstruating"
        }
    }

    var systemImage: String {
        switch self {
        case .sick: "thermometer.medium"
        case .stressed: "bolt.heart"
        case .poorSleep: "moon.zzz"
        case .traveled: "airplane"
        case .newMeds: "pills"
        case .menstruating: "drop.halffull"
        }
    }
}

// MARK: - When symptoms showed up (SPEC §11b, timing)

enum SrvMealTiming: String, CaseIterable, Codable, Sendable, Identifiable {
    case onWaking = "on_waking"
    case afterEating = "after_eating"
    case betweenMeals = "between_meals"
    case overnight
    case allDay = "all_day"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onWaking: "On waking"
        case .afterEating: "After eating"
        case .betweenMeals: "Between meals"
        case .overnight: "Overnight"
        case .allDay: "All day"
        }
    }
}

// MARK: - FODMAP reintro groups (the things you test back in)

/// The groups a reintro challenge clears. Stored in
/// `reintro_challenges.fodmap_group` as the rawValue. `level(in:)` reads the
/// per-food levels the DB join produced (CLAUDE.md rule #2, never invented).
enum SrvFodmapGroup: String, CaseIterable, Codable, Sendable, Identifiable {
    case fructan, gos, lactose, fructose, polyol

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fructan: "Fructans"
        case .gos: "GOS (galacto-oligosaccharides)"
        case .lactose: "Lactose"
        case .fructose: "Excess fructose"
        case .polyol: "Polyols"
        }
    }

    /// Short, friendly tag for inline chips.
    var shortName: String {
        switch self {
        case .fructan: "fructans"
        case .gos: "GOS"
        case .lactose: "lactose"
        case .fructose: "fructose"
        case .polyol: "polyols"
        }
    }

    /// A familiar example to ground the abstract group name.
    var exampleFood: String {
        switch self {
        case .fructan: "onion, wheat, garlic"
        case .gos: "beans, lentils, chickpeas"
        case .lactose: "milk, soft cheese"
        case .fructose: "apple, honey, mango"
        case .polyol: "stone fruit, mushroom, sugar-free gum"
        }
    }

    nonisolated func level(in fodmap: FodmapAttr) -> String {
        switch self {
        case .fructan: fodmap.fructanLevel
        case .gos: fodmap.gosLevel
        case .lactose: fodmap.lactoseLevel
        case .fructose: fodmap.fructoseLevel
        case .polyol: fodmap.polyolLevel
        }
    }

    /// True when this group is present at any level above "none", i.e. eating
    /// this food contributes to the group you're testing.
    nonisolated func isPresent(in fodmap: FodmapAttr) -> Bool {
        level(in: fodmap).lowercased() != "none"
    }
}

// MARK: - Reintro status (the leveling ladder)

/// `reintro_challenges.status` enum ('pending','testing','passed','failed').
enum SrvReintroStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case pending, testing, passed, failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending: "Not started"
        case .testing: "Testing now"
        case .passed: "Cleared"
        case .failed: "Needs a rest"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: "circle.dotted"
        case .testing: "hourglass"
        case .passed: "checkmark.seal.fill"
        case .failed: "arrow.counterclockwise.circle"
        }
    }
}

// MARK: - Pattern leans (read-only render of `pattern_assessments`)

/// `pattern_assessments.pattern` enum. ⚠️ These are GAS-CHEMISTRY LEANS, not
/// diagnoses (CLAUDE.md rule #4 / SPEC §11b). `hydrogen_sibo` is rendered as a
/// hydrogen-type-gas lean, the word "SIBO" is NEVER surfaced to the user.
enum SrvPattern: String, Codable, Sendable, Identifiable {
    case methane, h2s
    case hydrogenSibo = "hydrogen_sibo"
    case fat, histamine, proteolytic

    var id: String { rawValue }

    /// Non-diagnostic, user-facing lean. // RD-REVIEW-REQUIRED (Fence 1 copy)
    var leanPhrase: String {
        switch self {
        case .methane: "leans methane, gas that tends to slow things down"
        case .h2s: "leans hydrogen-sulfide, the sulfur, eggy gas"
        case .hydrogenSibo: "leans hydrogen-type gas, odorless gas with bloating"
        case .fat: "leans fat-triggered, richer, oilier meals hit harder"
        case .histamine: "leans histamine-sensitive, aged and fermented foods provoke it"
        case .proteolytic: "leans low-fiber, a stretch heavy on protein, light on plants"
        }
    }
}

/// `pattern_assessments.confidence` enum ('tentative','emerging','consistent').
enum SrvPatternConfidence: String, Codable, Sendable, Identifiable {
    case tentative, emerging, consistent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tentative: "An early lean"
        case .emerging: "Coming into focus"
        case .consistent: "A steady pattern"
        }
    }

    /// Only a steady pattern earns the full experiment + GI suggestion (SPEC §13).
    var suggestsExperiment: Bool { self == .consistent }
}
