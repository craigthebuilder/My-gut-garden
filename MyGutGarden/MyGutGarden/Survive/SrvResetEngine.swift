//
//  SrvResetEngine.swift
//  MyGutGarden, Module E. Pure logic for the low-residue reset (Batch E).
//
//  🔒 FENCE 6 (CLAUDE.md §3 / SPEC §14), the sharpest disordered-eating risk in
//  the app. EVERY threshold here is a placeholder read from GameConfig and is
//  // RD-REVIEW-REQUIRED. Build the machinery, fence the clinical content.
//
//  STRUCTURAL rule-#7 pin: progress is RELIEF (symptom-free days), never elapsed
//  time. `canAdvance` and `graduationReady` read symptom-free days ONLY, so the
//  reset bar can never advance on the calendar. (Unit-tested.) The 14-day
//  no-improvement clinician escalation is a SAFETY check that legitimately uses
//  time, it gates a doctor prompt, never progress.
//

import Foundation

/// `survive_reset.phase`. NEVER named "carnivore"; no condition, no microbe.
enum SrvResetPhase: String, Sendable, CaseIterable {
    case reset
    case reintroductionPhase = "reintroduction_phase"
    case graduated

    /// Calm, relief-framed titles (RD-REVIEW-REQUIRED, Fence 6).
    var title: String {
        switch self {
        case .reset: "Giving your gut a break"
        case .reintroductionPhase: "Adding foods back, gently"
        case .graduated: "Ready for Thrive"
        }
    }
}

enum SrvResetEngine {

    private static let config = GameConfig.shared

    // MARK: Advancement (RELIEF-driven, never time-driven)

    /// Whether the reset is ready to move to the reintroduction phase. Reads
    /// symptom-free days ONLY, never elapsed days. // RD-REVIEW-REQUIRED (Fence 6)
    nonisolated static func canAdvance(from phase: SrvResetPhase, symptomFreeDays: Int) -> Bool {
        // Defensive structural guard: the metric MUST be relief, never elapsed.
        guard config.resetProgressMetric == .symptomFreeDays else { return false }
        switch phase {
        case .reset: return symptomFreeDays >= config.resetSymptomFreeDaysToAdvance
        case .reintroductionPhase, .graduated: return false
        }
    }

    /// Whether the user is ready to graduate to Thrive. Relief-gated, not timed.
    /// // RD-REVIEW-REQUIRED (Fence 6)
    nonisolated static func graduationReady(state: SurviveResetRow) -> Bool {
        guard config.resetProgressMetric == .symptomFreeDays else { return false }
        return state.phase == SrvResetPhase.reintroductionPhase.rawValue
            && state.symptomFreeDays >= config.resetSymptomFreeDaysToAdvance
    }

    // MARK: Safety escalation (a doctor prompt, NOT a progress bar)

    /// Re-firing, non-blocking clinician checkpoint: if things haven't settled
    /// after the no-improvement window, suggest seeing a doctor or dietitian.
    /// This is duty-of-care machinery (Fence 5), legitimately time-based.
    /// // RD-REVIEW-REQUIRED (Fence 6, threshold placeholder)
    nonisolated static func clinicianPromptNeeded(state: SurviveResetRow, now: Date,
                                                  calendar: Calendar = .current) -> Bool {
        guard state.phase == SrvResetPhase.reset.rawValue, state.pausedAt == nil else { return false }
        guard let started = SrvDateParse.timestamp(state.startedAt) else { return false }
        let daysIn = calendar.dateComponents([.day], from: started, to: now).day ?? 0
        guard daysIn >= config.resetNoImprovementThresholdDays else { return false }
        guard state.symptomFreeDays < config.resetSymptomFreeDaysToAdvance else { return false }
        // Re-fire only after another full window since the last prompt.
        if let prompted = state.clinicianPromptedAt.flatMap({ SrvDateParse.timestamp($0) }) {
            let sincePrompt = calendar.dateComponents([.day], from: prompted, to: now).day ?? 0
            return sincePrompt >= config.resetNoImprovementThresholdDays
        }
        return true
    }

    // MARK: Informational context (copy only, NEVER a bar denominator)

    /// "Typically 1 to 3 weeks", informational only. // RD-REVIEW-REQUIRED (Fence 6)
    nonisolated static var typicalDurationCopy: String {
        "Most people do this for \(config.resetTypicalDurationWeeksLow) to \(config.resetTypicalDurationWeeksHigh) weeks. There's no clock, you go by how you feel."
    }
}
