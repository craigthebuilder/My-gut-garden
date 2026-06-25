//
//  PatRules.swift
//  MyGutGarden — Module F (Survive pattern engine).
//
//  ╔══════════════════════════════════════════════════════════════════════╗
//  ║  🔒 FENCE 1 — RD-REVIEW-REQUIRED                                       ║
//  ║                                                                        ║
//  ║  EVERY decision rule in this file is PLACEHOLDER clinical content:     ║
//  ║  which symptom fingerprint maps to which pattern, and the weights /    ║
//  ║  thresholds used to decide. None of it is validated. A registered      ║
//  ║  dietitian + the owner must review and replace these rules before      ║
//  ║  launch (SPEC §14 Fence 1, CLAUDE.md §3 / hard rule #10).              ║
//  ║                                                                        ║
//  ║  This file is the SINGLE review surface — all fenced logic lives here  ║
//  ║  so the engine plumbing in `PatPatternEngine.swift` stays content-free.║
//  ║                                                                        ║
//  ║  The output copy stays structurally pattern → experiment → confirm and ║
//  ║  NEVER names a condition, a bug, or a diagnosis.                       ║
//  ╚══════════════════════════════════════════════════════════════════════╝
//

import Foundation

enum PatRules {

    // MARK: - Tunable rule thresholds (RD-REVIEW-REQUIRED placeholders)

    /// Severity scale is an undocumented 0…3 placeholder (none/mild/mod/severe);
    /// "above mild" means strictly greater than this. // RD-REVIEW-REQUIRED
    static let mildSeverityCutoff = 1

    /// Minimum weighted-average evidence for the top pattern before we'll claim
    /// any lean at all. Below this the signal is "too mixed" → keep gathering.
    /// // RD-REVIEW-REQUIRED
    static let minLeanEvidence = 0.15

    // MARK: - "Is this a symptomatic day?" (RD-REVIEW-REQUIRED)

    /// A day counts as symptomatic if any tracked symptom reads above mild.
    /// Drives the §13 gate ("14 days, ≥10 with symptoms"). // RD-REVIEW-REQUIRED
    static func isSymptomatic(_ f: PatSymptomFeatures) -> Bool {
        if let s = f.stool, s == .constipated || s == .loose { return true }
        if let o = f.gasOdor, o == .sulfur || o == .sour { return true }
        if aboveMild(f.bloating) || aboveMild(f.gas) || aboveMild(f.pain) || aboveMild(f.urgency) {
            return true
        }
        if f.flushingOrHeadache == true { return true }
        return false
    }

    private static func aboveMild(_ severity: Int?) -> Bool {
        guard let severity else { return false }
        return severity > mildSeverityCutoff
    }

    // MARK: - Fingerprint → per-pattern day evidence (RD-REVIEW-REQUIRED)

    /// Placeholder scoring: for one day, how strongly does the fingerprint lean
    /// toward each pattern? Each score is clamped to 0…1. These weights are
    /// illustrative ONLY and must be replaced by RD-reviewed logic.
    ///
    /// Framework heuristics encoded as placeholders (SPEC §11b / framework §7):
    ///   • methane      — bloat + constipation, low-odor gas
    ///   • h2s          — sulfur gas + looser stools (+ worse after fatty)
    ///   • hydrogenSibo — odorless gas + bloat, not constipated
    ///   • fat          — worse after fatty meals + looser stools
    ///   • histamine    — aged/fermented-food triggers (± flushing/headache)
    ///   • proteolytic  — sour gas on a lower-fiber stretch
    static func dayScores(_ f: PatSymptomFeatures) -> [PatPattern: Double] {
        let bloat = aboveMild(f.bloating)

        // --- methane-leaning: constipation + bloat, gas not sulfurous ---  // RD-REVIEW-REQUIRED
        var methane = 0.0
        if f.stool == .constipated { methane += 0.60 }
        if bloat { methane += 0.20 }
        if f.gasOdor == .odorless { methane += 0.15 }
        if f.gasOdor == .sulfur { methane -= 0.30 }

        // --- h2s-leaning: sulfur gas + looser stools (+ worse after fatty) --- // RD-REVIEW-REQUIRED
        var h2s = 0.0
        if f.gasOdor == .sulfur { h2s += 0.60 }
        if f.stool == .loose { h2s += 0.30 }
        if f.worseAfterFatty == true { h2s += 0.20 }
        if f.stool == .constipated { h2s -= 0.20 }

        // --- hydrogen/SIBO-leaning: odorless gas + bloat, not constipated --- // RD-REVIEW-REQUIRED
        var hydrogenSibo = 0.0
        if f.gasOdor == .odorless { hydrogenSibo += 0.50 }
        if bloat { hydrogenSibo += 0.25 }
        if f.stool == .loose { hydrogenSibo += 0.15 }
        if f.stool == .normal { hydrogenSibo += 0.10 }
        if f.gasOdor == .sulfur { hydrogenSibo -= 0.20 }
        if f.stool == .constipated { hydrogenSibo -= 0.20 }

        // --- fat-triggered: worse after fatty meals + looser stools --- // RD-REVIEW-REQUIRED
        var fat = 0.0
        if f.worseAfterFatty == true { fat += 0.60 }
        if f.stool == .loose { fat += 0.30 }
        if f.gasOdor == .sulfur { fat += 0.10 }

        // --- histamine: aged/fermented-food triggers (± flushing/headache) --- // RD-REVIEW-REQUIRED
        var histamine = 0.0
        if f.agedOrFermentedTrigger == true { histamine += 0.50 }
        if f.flushingOrHeadache == true { histamine += 0.40 }

        // --- proteolytic shift: sour gas on a lower-fiber stretch --- // RD-REVIEW-REQUIRED
        var proteolytic = 0.0
        if f.gasOdor == .sour { proteolytic += 0.50 }
        if f.lowFiberHighProtein == true { proteolytic += 0.20 }
        if f.stool == .constipated { proteolytic += 0.20 }
        if f.stool == .normal { proteolytic += 0.15 }
        if f.gasOdor == .sulfur { proteolytic += 0.15 }

        return [
            .methane: clamp01(methane),
            .h2s: clamp01(h2s),
            .hydrogenSibo: clamp01(hydrogenSibo),
            .fat: clamp01(fat),
            .histamine: clamp01(histamine),
            .proteolytic: clamp01(proteolytic),
        ]
    }

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    // MARK: - Evidence copy: signal → experiment → confirm (RD-REVIEW-REQUIRED)

    /// Placeholder user-facing summary. Structurally pattern → experiment →
    /// "this is also what a breath test checks — worth raising with a GI."
    /// Describes the SIGNAL only. NEVER a diagnosis, named condition, or bug.
    /// `experimentDays` comes from `GameConfig.patternExperimentDays` (no magic
    /// numbers). // RD-REVIEW-REQUIRED
    static func evidenceSummary(for pattern: PatPattern, experimentDays: Int) -> String {
        let lead: String
        let experiment: String
        switch pattern {
        case .methane:
            lead = "Your recent logs lean toward a slower-transit signal — more constipated days than loose ones, with low-odor gas."
            experiment = "ease back on your usual fermentable load"
        case .h2s:
            lead = "Your recent logs lean toward a sulfur-gas signal — sulfur-smelling gas showing up alongside looser stools."
            experiment = "cut back on high-sulfur foods"
        case .hydrogenSibo:
            lead = "Your recent logs lean toward a fermentation signal — mostly odorless gas with bloating, and few constipated days."
            experiment = "lower the quickly-fermenting carbs"
        case .fat:
            lead = "Your recent logs lean toward a fat-handling signal — looser stools that tend to track with richer, fattier meals."
            experiment = "spread fat across smaller portions"
        case .histamine:
            lead = "Your recent logs lean toward a histamine-sensitivity signal — symptoms that cluster around aged or fermented foods."
            experiment = "pause aged and fermented foods"
        case .proteolytic:
            lead = "Your recent logs lean toward a protein-fermentation signal — sour-smelling gas during a lower-fiber stretch."
            experiment = "add gentle fiber and balance the protein"
        }
        return "\(lead) A gentle experiment: \(experiment) for \(experimentDays) days, and we'll watch the signal. "
            + "This is also the kind of thing a breath test looks at — worth raising with a GI."
    }
}
