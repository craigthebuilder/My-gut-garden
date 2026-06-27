//
//  PatPatternEngine.swift
//  MyGutGarden, Module F (Survive pattern engine), SPEC §11b / §13.
//
//  The rule-based, content-FREE plumbing of the invisible Survive pattern
//  engine: windowing logs into days, applying the §13 timing/confidence gates
//  from GameConfig, down-weighting confounder-heavy days, and picking the
//  leading pattern. All clinical decision content lives in `PatRules.swift`
//  behind 🔒 FENCE 1, this file only orchestrates and reads config.
//
//  ⚠️ Output is structurally pattern → experiment → confirm. NEVER a diagnosis,
//  named condition (SIBO/IBS/IMO), named bug, or accumulating bad-guy meter
//  (CLAUDE.md hard rule #4, SPEC §11b/§14).
//
//  ── READ SHAPE (Batch D cutover) ──────────────────────────────────────────
//  New check-in signal is written ONLY to the sub-entry tables, so `refresh`
//  aggregates per `log_date` from:
//    • symptom_entries  → severity by symptom_type (bloating/gas/pain/urgency)
//                         + gas_odor (the H2S / odor lean's discriminating cue)
//    • mood_entries     → mood_score, CANONICAL high=better (NEVER inverted here;
//                         the single 6 - ui inversion lives in CheckInKit)
//    • stool_entries    → bss → coarse Bristol bucket
//  The flat `symptom_logs` table is kept ONLY as a FALLBACK for legacy/history
//  days that have no sub-entry data (so older logs and confounder tags survive).
//  `Self.features(symptomEntries:moodEntries:stoolEntries:legacyLogs:)` builds
//  the per-day `PatSymptomFeatures`; the pure `assess(features:)` core is
//  unchanged. The legacy `assess(logs:)` / `features(from:)` surface remains for
//  the fallback path and the existing fixtures.
//

import Foundation

struct PatPatternEngine: Sendable {

    /// All §13 timing numbers come from here (Fence 1 placeholders). Injected so
    /// tests can override; defaults to the shared config.
    let config: GameConfig

    init(config: GameConfig = .shared) {
        self.config = config
    }

    // MARK: - Public entry points (SymptomLogRow surface, the mandated API)

    /// PURE. Returns a pattern lean, or `nil` when there isn't enough signal yet.
    func assess(logs: [SymptomLogRow], asOf: Date) -> PatAssessment? {
        guard case let .lean(assessment) = evaluate(logs: logs, asOf: asOf) else { return nil }
        return assessment
    }

    /// PURE. Full result including the "still gathering signal" progress state
    /// (so Module E can render "N more days of logs…" without re-deriving gates).
    func evaluate(logs: [SymptomLogRow], asOf: Date) -> PatEvaluation {
        evaluate(features: logs.compactMap(Self.features(from:)), asOf: asOf)
    }

    // MARK: - Public entry points (feature surface, richer / future inputs)

    /// PURE. Same logic, over the normalized feature model.
    func assess(features: [PatSymptomFeatures], asOf: Date) -> PatAssessment? {
        guard case let .lean(assessment) = evaluate(features: features, asOf: asOf) else { return nil }
        return assessment
    }

    /// PURE. The core: bucket → gate → fingerprint → lean.
    func evaluate(features: [PatSymptomFeatures], asOf: Date) -> PatEvaluation {
        let cal = Self.utcCalendar
        let asOfDay = cal.startOfDay(for: asOf)

        // Bucket logs into UTC calendar days, ignoring anything after `asOf`.
        var byDay: [Date: [PatSymptomFeatures]] = [:]
        for f in features {
            let day = cal.startOfDay(for: f.day)
            guard day <= asOfDay else { continue }   // defensive: drop future logs
            byDay[day, default: []].append(f)
        }

        let symptomaticDayLogs = byDay.values.filter { logs in
            logs.contains(where: PatRules.isSymptomatic)
        }
        let loggedDays = byDay.count
        let symptomaticDays = symptomaticDayLogs.count

        // ── §13 timing gate ──────────────────────────────────────────────────
        // < patternMinDays logged, OR < patternMinSymptomDays symptomatic → wait.
        guard loggedDays >= config.patternMinDays,
              symptomaticDays >= config.patternMinSymptomDays else {
            return .gathering(progress(loggedDays: loggedDays, symptomaticDays: symptomaticDays))
        }

        let confidence = confidenceTier(forLoggedDays: loggedDays)

        // ── Fingerprint over symptomatic days, down-weighting confounder days ──
        var weightedSum: [PatPattern: Double] = [:]
        var totalWeight = 0.0
        for logs in symptomaticDayLogs {
            // SPEC §12: a confounder-heavy day is trusted less, so the engine
            // doesn't blame food for an illness/stress flare. It still COUNTS as
            // a logged/symptomatic day for the timing gate above, only its
            // fingerprint contribution is down-weighted.
            let dayWeight = logs.contains(where: { $0.hasConfounder })
                ? config.confounderDownweight
                : 1.0

            // Combine same-day logs by taking the strongest evidence per pattern.
            var dayScore: [PatPattern: Double] = [:]
            for f in logs {
                let scores = PatRules.dayScores(f)
                for p in PatPattern.allCases {
                    dayScore[p] = max(dayScore[p] ?? 0, scores[p] ?? 0)
                }
            }
            for p in PatPattern.allCases {
                weightedSum[p, default: 0] += dayWeight * (dayScore[p] ?? 0)
            }
            totalWeight += dayWeight
        }

        guard totalWeight > 0 else {
            return .gathering(progress(loggedDays: loggedDays, symptomaticDays: symptomaticDays))
        }

        // Weighted-average evidence per pattern, then deterministic arg-max
        // (ties resolve to the earliest in `PatPattern.allCases`).
        var leadingPattern = PatPattern.allCases[0]
        var leadingScore = -1.0
        for p in PatPattern.allCases {
            let score = (weightedSum[p] ?? 0) / totalWeight
            if score > leadingScore {
                leadingScore = score
                leadingPattern = p
            }
        }

        // No pattern clears the minimum, signal is too mixed to claim a lean.
        guard leadingScore >= PatRules.minLeanEvidence else {
            return .gathering(progress(loggedDays: loggedDays, symptomaticDays: symptomaticDays,
                                       mixed: true))
        }

        let summary = PatRules.evidenceSummary(for: leadingPattern,
                                               experimentDays: config.patternExperimentDays)
        return .lean(PatAssessment(pattern: leadingPattern,
                                   confidence: confidence,
                                   evidenceSummary: summary))
    }

    // MARK: - Confidence tier (§13 timing), config-driven

    private func confidenceTier(forLoggedDays loggedDays: Int) -> PatConfidence {
        if loggedDays >= config.patternConsistentDays { return .consistent }
        if loggedDays >= config.patternEmergingDays { return .emerging }
        return .tentative
    }

    // MARK: - "Still gathering signal" progress (calm, non-clinical copy)

    private func progress(loggedDays: Int, symptomaticDays: Int, mixed: Bool = false) -> PatGatheringProgress {
        let message: String
        if loggedDays < config.patternMinDays {
            let remaining = config.patternMinDays - loggedDays
            message = "Still gathering signal, \(remaining) more day\(remaining == 1 ? "" : "s") "
                + "of logs to spot your first pattern."
        } else if symptomaticDays < config.patternMinSymptomDays {
            message = "Still gathering signal, keep logging on the days you don't feel great, "
                + "and a pattern can start to show."
        } else if mixed {
            message = "Still gathering signal, the picture is mixed so far. A bit more logging "
                + "should sharpen it."
        } else {
            message = "Still gathering signal."
        }
        return PatGatheringProgress(
            loggedDays: loggedDays,
            symptomaticDays: symptomaticDays,
            minLoggedDays: config.patternMinDays,
            minSymptomaticDays: config.patternMinSymptomDays,
            message: message
        )
    }

    // MARK: - SymptomLogRow → features adapter

    /// Maps the shared wire/DB row to the engine's feature model. Returns `nil`
    /// for an unparseable timestamp (the row is skipped, never fatal). Grow this
    /// when `SymptomLogRow` starts decoding bloating/gas/pain/food_correlation.
    static func features(from row: SymptomLogRow) -> PatSymptomFeatures? {
        guard let day = parseTimestamp(row.loggedAt) else { return nil }
        return PatSymptomFeatures(
            day: day,
            stool: PatStoolForm(bss: row.bss),
            gasOdor: PatGasOdor(raw: row.gasOdor),
            confounders: row.confounders
        )
    }

    // MARK: - Sub-entry tables → features adapter (Batch D read cutover)

    /// PURE. Aggregates the new per-`log_date` sub-entry rows into the engine's
    /// daily feature model. `legacyLogs` is a FALLBACK only: a flat `symptom_logs`
    /// row contributes a day ONLY when that calendar date has no sub-entry data
    /// (so history + confounder tags survive without double-counting new signal).
    ///
    /// Mood is read CANONICAL high=better and is NEVER inverted; it does not, by
    /// itself, mark a day symptomatic (a good mood must never read as "worse").
    static func features(
        symptomEntries: [SymptomEntryRow],
        moodEntries: [MoodEntryRow],
        stoolEntries: [StoolEntryRow],
        legacyLogs: [SymptomLogRow] = []
    ) -> [PatSymptomFeatures] {
        var symByDate: [String: [SymptomEntryRow]] = [:]
        var moodByDate: [String: [MoodEntryRow]] = [:]
        var stoolByDate: [String: [StoolEntryRow]] = [:]
        var dates = Set<String>()
        for e in symptomEntries { symByDate[e.logDate, default: []].append(e); dates.insert(e.logDate) }
        for m in moodEntries { moodByDate[m.logDate, default: []].append(m); dates.insert(m.logDate) }
        for s in stoolEntries { stoolByDate[s.logDate, default: []].append(s); dates.insert(s.logDate) }

        var out: [PatSymptomFeatures] = []
        for dateStr in dates {
            guard let day = parseLogDate(dateStr) else { continue }
            out.append(aggregateDay(
                day: day,
                symptoms: symByDate[dateStr] ?? [],
                stools: stoolByDate[dateStr] ?? [],
                moods: moodByDate[dateStr] ?? []
            ))
        }

        // Legacy fallback: keep only days the sub-entry tables don't already cover.
        for row in legacyLogs {
            guard let f = features(from: row) else { continue }
            let key = dayString(f.day)
            guard !dates.contains(key) else { continue }
            out.append(f)
        }
        return out
    }

    /// Collapses one calendar day's sub-entries into a single feature row.
    /// The aggregation choices below (most-extreme stool, most-discriminating gas
    /// odor, max severity per symptom type) are PLACEHOLDER and must be
    /// RD-reviewed before launch. // RD-REVIEW-REQUIRED (Fence 1)
    static func aggregateDay(
        day: Date,
        symptoms: [SymptomEntryRow],
        stools: [StoolEntryRow],
        moods: [MoodEntryRow]
    ) -> PatSymptomFeatures {
        // Stool: the most extreme BSS (largest deviation from a "normal" 4), so a
        // looser/constipated day is not masked by an averaged-out normal one.
        // // RD-REVIEW-REQUIRED (Fence 1)
        let aggBss = stools.compactMap(\.bss).max(by: { abs($0 - 4) < abs($1 - 4) })

        // Symptom severity by type: the day's strongest reading per symptom.
        // // RD-REVIEW-REQUIRED (Fence 1)
        func maxSeverity(_ type: String) -> Int? {
            symptoms.filter { $0.symptomType == type }.map(\.severity).max()
        }

        // Gas odor (only carried on gas entries). Prefer the most discriminating
        // cue: sulfur > sour > odorless. // RD-REVIEW-REQUIRED (Fence 1)
        let odorRank: [String: Int] = ["sulfur": 0, "sour": 1, "odorless": 2]
        let odor = symptoms
            .filter { $0.symptomType == "gas" }
            .compactMap(\.gasOdor)
            .min(by: { (odorRank[$0] ?? 99) < (odorRank[$1] ?? 99) })

        // Mood: CANONICAL high=better, NEVER inverted. Keep the day's most-erratic
        // (lowest) reading for completeness; it never marks the day symptomatic.
        let aggMood = moods.map(\.moodScore).min()

        return PatSymptomFeatures(
            day: day,
            stool: PatStoolForm(bss: aggBss),
            gasOdor: PatGasOdor(raw: odor),
            confounders: [],   // sub-entry tables carry no confounder tags
            bloating: maxSeverity("bloating"),
            gas: maxSeverity("gas"),
            pain: maxSeverity("pain"),
            urgency: maxSeverity("urgency"),
            mood: aggMood
        )
    }

    // MARK: - Persistence (I/O, not pure)

    /// Fetches the user's check-in history from the sub-entry tables, runs
    /// `assess` over the aggregated features, records any lean, then runs the
    /// Fence-7 suspect auto-suggestion gate (see `PatSuspectGate.swift`).
    ///
    /// `pattern_assessments` has no unique constraint on `user_id` (id PK +
    /// `computed_at`), so this APPENDS a fresh assessment, the table is an
    /// evolving history (tentative → emerging → consistent); the latest by
    /// `computed_at` is the current lean. When there isn't enough signal yet,
    /// nothing is written (the UI shows the "gathering" state from `evaluate`).
    func refresh(repository: Repository, userId: String, asOf: Date = Date()) async throws {
        // ── Read cutover: new signal comes from the sub-entry tables. ──────────
        let symptomEntries: [SymptomEntryRow] = try await repository.select(
            "symptom_entries", filters: ["user_id": "eq.\(userId)"], order: "log_date.asc")
        let moodEntries: [MoodEntryRow] = try await repository.select(
            "mood_entries", filters: ["user_id": "eq.\(userId)"], order: "log_date.asc")
        let stoolEntries: [StoolEntryRow] = try await repository.select(
            "stool_entries", filters: ["user_id": "eq.\(userId)"], order: "log_date.asc")
        // Flat history is a FALLBACK only (fills days with no sub-entry data).
        let legacy: [SymptomLogRow] = try await repository.select(
            "symptom_logs", filters: ["user_id": "eq.\(userId)"], order: "logged_at.asc")

        let features = Self.features(
            symptomEntries: symptomEntries, moodEntries: moodEntries,
            stoolEntries: stoolEntries, legacyLogs: legacy)

        if let assessment = assess(features: features, asOf: asOf) {
            try await repository.insertVoid("pattern_assessments", [
                "user_id": .string(userId),
                "computed_at": .date(asOf),
                "pattern": .string(assessment.pattern.rawValue),
                "confidence": .string(assessment.confidence.rawValue),
                "evidence_summary": .string(assessment.evidenceSummary),
            ])
        }

        // ── Fence 7: run the suspect auto-suggestion gate alongside the read. ──
        try await suggestSuspects(
            repository: repository, userId: userId,
            symptomEntries: symptomEntries, asOf: asOf)
    }

    // MARK: - Helpers

    /// UTC so day-bucketing is deterministic regardless of device timezone.
    static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// Parse an ISO-8601 timestamp, with or without fractional seconds.
    static func parseTimestamp(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// Parse a SQL `date` (`log_date`, e.g. "2026-06-26") to UTC midnight. Falls
    /// back to the timestamp parser if a full timestamp is handed in.
    static func parseLogDate(_ string: String) -> Date? {
        if let d = logDateFormatter.date(from: string) { return d }
        return parseTimestamp(string)
    }

    /// Render a `Date` as a UTC "yyyy-MM-dd" key, for deduping legacy fallback
    /// rows against the sub-entry `log_date` keys.
    static func dayString(_ date: Date) -> String {
        logDateFormatter.string(from: date)
    }

    static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
