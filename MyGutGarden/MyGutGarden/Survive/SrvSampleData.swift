//
//  SrvSampleData.swift
//  MyGutGarden, Module E. Clearly-labelled sample data for the offline build
//  and SwiftUI previews ONLY. Never shown when a real backend is configured.
//
//  This is demo scaffolding, not seed content: it lets the whole Survive
//  surface (logger → streak → patterns → reintro → pokédex) render and be
//  reviewed without Supabase. Real data comes from the RLS-scoped Repository.
//

import Foundation

enum SrvSampleData {

    /// A fortnight of evening check-ins: mostly good, a couple of rough days,
    /// one confounder-tagged day, enough to exercise the streak freeze rule.
    static func logs(now: Date = .init()) -> [SrvSymptomLogRow] {
        let calendar = Calendar.current
        let iso = ISO8601DateFormatter()

        func day(_ ago: Int, bss: Int, bloating: Int, gas: Int, pain: Int, urgency: Int,
                 odor: SrvGasOdor?, confounders: [SrvConfounder]) -> SrvSymptomLogRow {
            let date = calendar.date(byAdding: .day, value: -ago, to: calendar.startOfDay(for: now))!
                .addingTimeInterval(20 * 3600) // ~8pm
            return SrvSymptomLogRow(
                id: "sample-\(ago)",
                loggedAt: iso.string(from: date),
                bss: bss, bloating: bloating, gas: gas, pain: pain, urgency: urgency,
                mood: 4, brainFog: 2,
                gasOdor: odor?.rawValue, mealTiming: SrvMealTiming.afterEating.rawValue,
                foodCorrelation: nil, confounders: confounders.map(\.rawValue), notes: nil
            )
        }

        return [
            day(8, bss: 4, bloating: 0, gas: 1, pain: 0, urgency: 0, odor: .odorless, confounders: []),
            day(7, bss: 4, bloating: 1, gas: 1, pain: 0, urgency: 1, odor: .odorless, confounders: []),
            day(6, bss: 6, bloating: 3, gas: 3, pain: 2, urgency: 2, odor: .sulfur, confounders: []),   // rough day → reset
            day(5, bss: 4, bloating: 0, gas: 1, pain: 0, urgency: 0, odor: .odorless, confounders: []),
            day(4, bss: 5, bloating: 2, gas: 2, pain: 1, urgency: 1, odor: .sour, confounders: [.stressed, .poorSleep]), // confounded → freeze
            day(3, bss: 4, bloating: 1, gas: 0, pain: 0, urgency: 0, odor: .odorless, confounders: []),
            day(2, bss: 4, bloating: 0, gas: 1, pain: 0, urgency: 0, odor: .odorless, confounders: []),
            day(1, bss: 4, bloating: 0, gas: 0, pain: 0, urgency: 0, odor: .odorless, confounders: [])
        ]
    }

    /// A single steady assessment so the pattern card renders the full
    /// experiment + GI routing. (Module F writes the real ones.)
    static func assessments(now: Date = .init()) -> [PatternAssessmentRow] {
        let iso = ISO8601DateFormatter()
        return [
            PatternAssessmentRow(
                id: "pa-h2s",
                computedAt: iso.string(from: now),
                pattern: SrvPattern.h2s.rawValue,
                confidence: SrvPatternConfidence.consistent.rawValue,
                // RD-REVIEW-REQUIRED, placeholder evidence note (Fence 1)
                evidenceSummary: "Sulfur-smelling gas on 6 of the last 10 logged days, often after richer meals."
            )
        ]
    }

}
