//
//  SrvStreakEngine.swift
//  MyGutGarden — Module E. The symptom-free streak math (SPEC §11b, §13, §12).
//
//  POSITIVE-OUTCOME STREAK ONLY (CLAUDE.md rule #7 / Fence 5): this counts
//  "days feeling good," never "days restricted." Restriction is never gamified.
//
//  The rule (SPEC §13): a symptom-free streak is consecutive days with no
//  symptom rated above "mild." Confounder-tagged days FREEZE the streak — they
//  neither advance nor break it — so an illness- or stress-driven flare never
//  blames food (SPEC §12). This file is pure and deterministic so it is unit-
//  tested directly (CLAUDE.md §5 testing).
//

import Foundation

// MARK: - A single day's symptoms, reduced to what the streak cares about

/// The streak only needs: was any symptom above mild, and was the day
/// confounded. Built from a `symptom_logs` row or the live logger draft.
struct SrvDaySymptoms: Sendable, Equatable {
    var bristol: SrvBristolType?
    var bloating: SrvSeverity
    var gas: SrvSeverity
    var pain: SrvSeverity
    var urgency: SrvSeverity
    var confounders: [SrvConfounder]

    init(
        bristol: SrvBristolType? = nil,
        bloating: SrvSeverity = .none,
        gas: SrvSeverity = .none,
        pain: SrvSeverity = .none,
        urgency: SrvSeverity = .none,
        confounders: [SrvConfounder] = []
    ) {
        self.bristol = bristol
        self.bloating = bloating
        self.gas = gas
        self.pain = pain
        self.urgency = urgency
        self.confounders = confounders
    }

    /// The single worst signal of the day (Bristol deviation counts too — a
    /// hard-lumps or watery day is a real symptom).
    nonisolated var worstSeverity: SrvSeverity {
        let ranks = [bloating, gas, pain, urgency, bristol?.deviationSeverity ?? .none].map(\.rank)
        let worst = ranks.max() ?? 0
        return SrvSeverity(rawValue: worst) ?? .none
    }

    nonisolated var isConfounded: Bool { !confounders.isEmpty }
}

// MARK: - A day's outcome for the streak

enum SrvDayOutcome: Sendable, Equatable {
    case feltGood       // advances the streak
    case hadSymptoms    // resets the streak to zero
    case confounded     // freezes: neither advances nor breaks (SPEC §12)
}

// MARK: - The engine

enum SrvStreakEngine {

    /// Threshold above which a symptom counts (SPEC §13: "no symptom above mild").
    static let symptomThreshold: SrvSeverity = .mild

    /// Classify one day. A confounder-tagged day always FREEZES — the confounder
    /// explains the day, so it is set aside from the streak entirely (SPEC §12).
    nonisolated static func outcome(for day: SrvDaySymptoms) -> SrvDayOutcome {
        if day.isConfounded { return .confounded }
        return day.worstSeverity.rank > symptomThreshold.rank ? .hadSymptoms : .feltGood
    }

    /// Result of folding a chronological run of day outcomes.
    struct Result: Sendable, Equatable {
        var current: Int
        var longest: Int
    }

    /// Fold day outcomes in chronological (oldest → newest) order.
    /// - feltGood  → +1 and update the best-ever
    /// - hadSymptoms → reset to 0
    /// - confounded → unchanged (the streak carries across the frozen day)
    nonisolated static func reduce(_ outcomes: [SrvDayOutcome]) -> Result {
        var current = 0
        var longest = 0
        for outcome in outcomes {
            switch outcome {
            case .feltGood:
                current += 1
                longest = max(longest, current)
            case .hadSymptoms:
                current = 0
            case .confounded:
                break // freeze — no change in either direction
            }
        }
        return Result(current: current, longest: longest)
    }

    /// Convenience: classify then fold a run of days.
    nonisolated static func streak(for days: [SrvDaySymptoms]) -> Result {
        reduce(days.map(outcome(for:)))
    }
}
