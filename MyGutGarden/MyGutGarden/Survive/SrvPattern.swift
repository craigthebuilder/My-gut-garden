//
//  SrvPattern.swift
//  MyGutGarden — Module E. READ-ONLY rendering of `pattern_assessments`
//  (SPEC §11b, §13; Fence 1).
//
//  Module F (the pattern engine) WRITES `pattern_assessments`; Module E only
//  reads and renders. The output is strictly insight → experiment → "worth
//  raising with a GI." (CLAUDE.md rule #4 / SPEC §14 Fence 1):
//      • NEVER a diagnosis, a named condition, or a named bug.
//      • NEVER an accumulating "bad-guy" meter.
//      • The experiment is structurally a FODMAP-style elimination, fenced.
//
//  🔒 FENCE 1: every copy line below is RD-REVIEW-REQUIRED placeholder content.
//

import Foundation

/// A render-ready, non-diagnostic presentation of one assessment row.
struct SrvPatternPresentation: Sendable, Identifiable {
    let id: String
    let pattern: SrvPattern
    let confidence: SrvPatternConfidence
    /// "Your pattern leans …" — the lean, never a label. // RD-REVIEW-REQUIRED
    let insight: String
    /// The structured experiment, only offered once the pattern is steady. nil
    /// while still tentative/emerging (we keep gathering signal). // RD-REVIEW-REQUIRED
    let experiment: String?
    /// The routing line — always points back to a clinician, never replaces one.
    let routing: String
    /// Module F's evidence note, shown verbatim and clearly fenced.
    let evidenceSummary: String?

    var confidenceLabel: String { confidence.label }
}

enum SrvPatternPresenter {

    private static let experimentDays = GameConfig.shared.patternExperimentDays

    /// Map a stored row → a calm, confidence-tiered, non-diagnostic card.
    /// Returns nil if the stored enum value is unrecognized (fail safe, never
    /// guess a clinical claim — CLAUDE.md rule #8).
    nonisolated static func present(_ row: PatternAssessmentRow) -> SrvPatternPresentation? {
        guard
            let pattern = SrvPattern(rawValue: row.pattern),
            let confidence = SrvPatternConfidence(rawValue: row.confidence)
        else { return nil }

        let insight = "Your pattern \(pattern.leanPhrase)."

        // Only a STEADY pattern earns the structured experiment (SPEC §13).
        let experiment: String? = confidence.suggestsExperiment
            ? experimentCopy(for: pattern)
            : nil

        return SrvPatternPresentation(
            id: row.id,
            pattern: pattern,
            confidence: confidence,
            insight: insight,
            experiment: experiment,
            routing: routingCopy(for: pattern),
            evidenceSummary: row.evidenceSummary
        )
    }

    /// The experiment is always "drop X for N days, we'll watch the signal" —
    /// structurally identical to a FODMAP reintro. // RD-REVIEW-REQUIRED (Fence 1)
    private nonisolated static func experimentCopy(for pattern: SrvPattern) -> String {
        let n = experimentDays
        switch pattern {
        case .methane:
            return "Try easing back on the heaviest fermentable fibers for \(n) days — we'll watch whether things move more easily."
        case .h2s:
            return "Try dialing down the high-sulfur foods for \(n) days — we'll watch whether the eggy gas settles."
        case .hydrogenSibo:
            return "Try lightening the most fermentable carbs for \(n) days — we'll watch whether the bloating eases."
        case .fat:
            return "Try a run of \(n) days with lighter, lower-fat meals — we'll watch whether the after-meal symptoms calm down."
        case .histamine:
            return "Try setting aside aged and fermented foods for \(n) days — we'll watch whether the flushing and headaches ease."
        case .proteolytic:
            return "Try adding a little more plant fiber over \(n) days — we'll watch whether things feel steadier."
        }
    }

    /// Routing always lands on "worth raising with a GI" — a recommendation,
    /// never a diagnosis or a block. // RD-REVIEW-REQUIRED (Fence 1)
    private nonisolated static func routingCopy(for pattern: SrvPattern) -> String {
        switch pattern {
        case .h2s, .hydrogenSibo, .methane:
            return "A breath test looks at exactly this — it's worth raising with a GI."
        case .fat:
            return "If lighter meals help, that's useful to share — worth raising with a GI."
        case .histamine:
            return "Histamine sensitivity is something a clinician can help confirm — worth raising with a GI."
        case .proteolytic:
            return "A dietitian or GI can help you build the fiber back up comfortably — worth raising with them."
        }
    }
}

// MARK: - Red-flag escalation (SPEC §11b — "these warrant a doctor")

/// Static, curated care-prompt content (CLAUDE.md rule #9 — never generated).
/// A recommendation to also see a doctor, never a block (SPEC §6).
enum SrvRedFlags {
    /// // RD-REVIEW-REQUIRED — confirm the red-flag list with a clinician.
    static let symptoms: [String] = [
        "Blood in your stool, or black, tarry stools",
        "Unexplained weight loss",
        "Pain or symptoms that wake you from sleep",
        "Trouble or pain swallowing",
        "A persistent fever alongside gut symptoms",
        "Symptoms that are severe or steadily getting worse"
    ]

    static let title = "Worth a doctor's eyes"
    static let body = "If any of these show up, it's worth booking a visit — they're outside what tracking can help with. This isn't a diagnosis, just a nudge to get checked."
}
