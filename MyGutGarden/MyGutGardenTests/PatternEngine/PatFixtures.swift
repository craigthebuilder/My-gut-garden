//
//  PatFixtures.swift
//  MyGutGardenTests — Module F (Survive pattern engine) test data builders.
//
//  Deterministic, wall-clock-free fabrication of `SymptomLogRow` and
//  `PatSymptomFeatures` arrays. Days are anchored to a fixed UTC date and
//  spaced one calendar day apart so timing gates are exact.
//

import Foundation
@testable import MyGutGarden

enum PatFixtures {
    /// Fixed UTC anchor (matches Fixtures.fixedDate epoch: 2023-11-14T22:13:20Z).
    static let anchor = Date(timeIntervalSince1970: 1_700_000_000)

    static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// Start of the day `offset` days after the anchor.
    static func day(_ offset: Int) -> Date {
        utc.date(byAdding: .day, value: offset, to: utc.startOfDay(for: anchor))!
    }

    /// A safe `asOf` that sits after any fixture window we build.
    static let asOf = day(400)

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - SymptomLogRow builders

    static func row(
        dayOffset: Int,
        bss: Int? = nil,
        odor: String? = nil,
        confounders: [String] = []
    ) -> SymptomLogRow {
        // Log at ~20:00 UTC (an "evening check") so it lands inside the day.
        let loggedAt = day(dayOffset).addingTimeInterval(20 * 3600)
        return SymptomLogRow(
            id: "log-\(dayOffset)-\(bss.map(String.init) ?? "x")-\(odor ?? "x")",
            loggedAt: iso(loggedAt),
            bss: bss,
            gasOdor: odor,
            confounders: confounders
        )
    }

    /// `count` consecutive distinct days, each with the same signal.
    static func rows(
        count: Int,
        startOffset: Int = 0,
        bss: Int? = nil,
        odor: String? = nil,
        confounders: [String] = []
    ) -> [SymptomLogRow] {
        (0..<count).map {
            row(dayOffset: startOffset + $0, bss: bss, odor: odor, confounders: confounders)
        }
    }

    // MARK: - Feature builders (for fat / histamine / bloat-driven leans)

    static func feature(
        dayOffset: Int,
        stool: PatStoolForm? = nil,
        gasOdor: PatGasOdor? = nil,
        confounders: [String] = [],
        bloating: Int? = nil,
        worseAfterFatty: Bool? = nil,
        agedOrFermentedTrigger: Bool? = nil,
        flushingOrHeadache: Bool? = nil,
        lowFiberHighProtein: Bool? = nil
    ) -> PatSymptomFeatures {
        PatSymptomFeatures(
            day: day(dayOffset),
            stool: stool,
            gasOdor: gasOdor,
            confounders: confounders,
            bloating: bloating,
            worseAfterFatty: worseAfterFatty,
            agedOrFermentedTrigger: agedOrFermentedTrigger,
            flushingOrHeadache: flushingOrHeadache,
            lowFiberHighProtein: lowFiberHighProtein
        )
    }

    static func features(
        count: Int,
        startOffset: Int = 0,
        _ build: (Int) -> PatSymptomFeatures
    ) -> [PatSymptomFeatures] {
        (0..<count).map { build(startOffset + $0) }
    }

    // MARK: - Diagnosis-language guard

    /// Tokens that would betray the "never diagnose / never name a bug" rule.
    /// Any appearance in surfaced copy is a hard defect (CLAUDE.md rule #4).
    static let bannedDiagnosisTokens = [
        "sibo", "ibs", "imo", "diagnos", "overgrowth", "condition", "disease",
        "disorder", "infection", "you have", "bad bug", "bad-bug", "bacteria",
        "syndrome", "intestinal methanogen",
    ]

    static func containsDiagnosisLanguage(_ text: String) -> Bool {
        let lower = text.lowercased()
        return bannedDiagnosisTokens.contains { lower.contains($0) }
    }
}
