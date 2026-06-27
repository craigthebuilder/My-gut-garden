//
//  PatFixtures.swift
//  MyGutGardenTests, Module F (Survive pattern engine) test data builders.
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

    /// UTC "yyyy-MM-dd" key for the day `offset` days after the anchor, matching
    /// `PatPatternEngine.parseLogDate` so the aggregator buckets them correctly.
    static let logDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func logDate(_ offset: Int) -> String { logDateFmt.string(from: day(offset)) }

    // MARK: - Sub-entry row builders (Batch D read cutover)

    static func symptomEntry(
        dayOffset: Int,
        type: String,
        severity: Int,
        gasOdor: String? = nil,
        occurredAt: Date? = nil,
        linkedMealId: String? = nil
    ) -> SymptomEntryRow {
        SymptomEntryRow(
            id: "sym-\(dayOffset)-\(type)-\(severity)-\(gasOdor ?? "x")",
            userId: "user-1",
            logDate: logDate(dayOffset),
            symptomType: type,
            severity: severity,
            gasOdor: gasOdor,
            occurredAt: occurredAt.map(iso),
            linkedMealId: linkedMealId
        )
    }

    static func moodEntry(
        dayOffset: Int,
        moodScore: Int,                       // CANONICAL high=better (5=regulated)
        context: String = "survive_logger",
        occurredAt: Date? = nil,
        linkedMealId: String? = nil
    ) -> MoodEntryRow {
        MoodEntryRow(
            id: "mood-\(dayOffset)-\(moodScore)",
            userId: "user-1",
            logDate: logDate(dayOffset),
            moodScore: moodScore,
            context: context,
            occurredAt: occurredAt.map(iso),
            linkedMealId: linkedMealId
        )
    }

    static func stoolEntry(
        dayOffset: Int,
        bss: Int?,
        occurredAt: Date? = nil,
        linkedMealId: String? = nil
    ) -> StoolEntryRow {
        StoolEntryRow(
            id: "stool-\(dayOffset)-\(bss.map(String.init) ?? "x")",
            userId: "user-1",
            logDate: logDate(dayOffset),
            bss: bss,
            occurredAt: occurredAt.map(iso),
            linkedMealId: linkedMealId,
            loggedAt: iso(day(dayOffset).addingTimeInterval(20 * 3600))
        )
    }

    /// A 14-day sulfur+loose window expressed entirely through the NEW sub-entry
    /// tables (so the cutover is exercised end-to-end). Maps to the h2s lean.
    static func h2sSubEntries(days: Int = 14)
        -> (symptoms: [SymptomEntryRow], moods: [MoodEntryRow], stools: [StoolEntryRow]) {
        var symptoms: [SymptomEntryRow] = []
        var stools: [StoolEntryRow] = []
        for d in 0..<days {
            symptoms.append(symptomEntry(dayOffset: d, type: "gas", severity: 2, gasOdor: "sulfur"))
            stools.append(stoolEntry(dayOffset: d, bss: 6))
        }
        return (symptoms, [], stools)
    }

    // MARK: - Meal + meal_items builders (Fence 7 suspect gate)

    static func meal(id: String, capturedAt: Date) -> MealRow {
        MealRow(id: id, mode: .survive, photoUrl: nil, capturedAt: iso(capturedAt),
                confirmed: true, userAnnotation: nil, photoExpiresAt: nil)
    }

    static func mealItem(mealId: String, foodId: String) -> PatMealItemRow {
        PatMealItemRow(mealId: mealId, foodId: foodId)
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
