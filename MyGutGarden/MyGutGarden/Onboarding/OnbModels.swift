//
//  OnbModels.swift
//  MyGutGarden — Module A: the remaining intake value types (SPEC §6).
//
//  Goals (multi-select + soft-routing lean), baseline mood/energy/clarity,
//  curated success stories, red-flag symptoms, and serious-condition flags.
//  All gain-framed and warm; nobody is ever locked out — conditions and
//  red flags drive disclaimers + click-to-confirm, never hard gates.
//

import Foundation

// MARK: - Goals + soft routing (SPEC §6)

/// Intake goals (multi-select). Each carries a routing lean used ONLY for the
/// soft suggestion (SPEC §6): relief goals lean Survive, optimization goals lean
/// Thrive. Never a gate.
enum OnbGoal: String, CaseIterable, Identifiable, Sendable {
    case reduceBloating   = "reduce_bloating"
    case findTriggers     = "find_triggers"
    case calmIbs          = "calm_ibs"
    case eatMoreDiversity = "eat_more_diversity"
    case moreEnergy       = "more_energy"
    case feedGoodBacteria = "feed_good_bacteria"
    case eatTheRainbow    = "eat_the_rainbow"
    case generalCuriosity = "general_curiosity"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .reduceBloating:   "Ease bloating"
        case .findTriggers:     "Find my triggers"
        case .calmIbs:          "Calm IBS flare-ups"
        case .eatMoreDiversity: "Eat more variety"
        case .moreEnergy:       "Steadier energy"
        case .feedGoodBacteria: "Feed my good bacteria"
        case .eatTheRainbow:    "Eat the rainbow"
        case .generalCuriosity: "Just curious"
        }
    }

    var systemImage: String {
        switch self {
        case .reduceBloating:   "wind"
        case .findTriggers:     "magnifyingglass"
        case .calmIbs:          "heart.text.square"
        case .eatMoreDiversity: "leaf"
        case .moreEnergy:       "bolt"
        case .feedGoodBacteria: "ant"
        case .eatTheRainbow:    "rainbow"
        case .generalCuriosity: "sparkles"
        }
    }

    /// +1 leans Survive (relief), −1 leans Thrive (optimization).
    var routingLean: Int {
        switch self {
        case .reduceBloating, .findTriggers, .calmIbs: 1
        case .eatMoreDiversity, .moreEnergy, .feedGoodBacteria, .eatTheRainbow, .generalCuriosity: -1
        }
    }
}

/// Soft routing (SPEC §6): a SUGGESTION from goals (+ any relief/red-flag
/// signal), never a gate. Either mode is one tap away. PURE + testable.
enum OnbRouting {
    static func suggestedMode(goals: Set<OnbGoal>, hasReliefSignal: Bool) -> AppMode {
        if hasReliefSignal { return .survive }   // active distress → start with relief
        let lean = goals.reduce(0) { $0 + $1.routingLean }
        return lean > 0 ? .survive : .thrive
    }

    /// Calm, honest rationale shown beside the suggestion (no diagnosis).
    static func rationale(for mode: AppMode) -> String {
        switch mode {
        case .survive:
            "You mentioned relief. Survive helps you spot triggers and feel steady first — you can switch to Thrive any time."
        case .thrive:
            "You're here to optimize. Thrive turns variety into a garden you grow — and Survive is one tap away if a flare hits."
        }
    }
}

// MARK: - Baseline (the "Is it working?" before — SPEC §6, §11a)

/// Onboarding baseline on a 1–5 scale; gives the Thrive dashboard a *before*.
struct OnbBaseline: Equatable, Sendable {
    var mood = 3
    var energy = 3
    var clarity = 3
}

// MARK: - Social proof (SPEC §5 `success_stories`, §6)

/// Decoded `success_stories` row. Truthful + representative only — the data
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

// MARK: - Disclaimers (SPEC §6 — never a block)

/// Red-flag symptoms (SPEC §6 / §11b). Selecting any triggers a "please also see
/// a doctor" CARE PROMPT — a recommendation, NEVER a block.
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

/// Serious conditions that warrant a disclaimer + acknowledgment at Survive
/// intake (SPEC §6). Celiac additionally PROPOSES a loud gluten exclusion
/// (medical_allergy, §9) — proposed and removable, never silently added.
// RD-REVIEW-REQUIRED: disclaimer copy is clinical-adjacent; confirm before launch.
struct OnbSeriousCondition: Identifiable, Sendable, Hashable {
    var id: String { key }
    let key: String
    let label: String

    static let celiac = OnbSeriousCondition(key: "celiac", label: "Celiac disease")
    static let ibd    = OnbSeriousCondition(key: "ibd",    label: "IBD (Crohn's or colitis)")
    static let all: [OnbSeriousCondition] = [celiac, ibd]
}
