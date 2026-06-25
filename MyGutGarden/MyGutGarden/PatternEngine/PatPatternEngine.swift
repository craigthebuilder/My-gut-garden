//
//  PatPatternEngine.swift
//  MyGutGarden — Module F (Survive pattern engine), SPEC §11b / §13.
//
//  The rule-based, content-FREE plumbing of the invisible Survive pattern
//  engine: windowing logs into days, applying the §13 timing/confidence gates
//  from GameConfig, down-weighting confounder-heavy days, and picking the
//  leading pattern. All clinical decision content lives in `PatRules.swift`
//  behind 🔒 FENCE 1 — this file only orchestrates and reads config.
//
//  ⚠️ Output is structurally pattern → experiment → confirm. NEVER a diagnosis,
//  named condition (SIBO/IBS/IMO), named bug, or accumulating bad-guy meter
//  (CLAUDE.md hard rule #4, SPEC §11b/§14).
//
//  ── INPUT GAP (documented, intentional) ───────────────────────────────────
//  `assess(logs:asOf:)` takes the shared `SymptomLogRow`, which today only
//  carries bss / gasOdor / confounders. Stool-form + gas-odor cleanly reach the
//  methane / h2s / hydrogen_sibo / proteolytic leans. The fat and histamine
//  leans depend on food-correlation signals (worse-after-fatty, aged/fermented
//  triggers) that live in `symptom_logs` (food_correlation, bloating, …) but
//  aren't decoded by `SymptomLogRow` yet. The feature-based `assess(features:)`
//  surface exercises those rules; when the data layer surfaces the extra
//  columns, only the `features(from:)` adapter below needs to grow.
//

import Foundation

struct PatPatternEngine: Sendable {

    /// All §13 timing numbers come from here (Fence 1 placeholders). Injected so
    /// tests can override; defaults to the shared config.
    let config: GameConfig

    init(config: GameConfig = .shared) {
        self.config = config
    }

    // MARK: - Public entry points (SymptomLogRow surface — the mandated API)

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

    // MARK: - Public entry points (feature surface — richer / future inputs)

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
            // a logged/symptomatic day for the timing gate above — only its
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

        // No pattern clears the minimum — signal is too mixed to claim a lean.
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

    // MARK: - Confidence tier (§13 timing) — config-driven

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
            message = "Still gathering signal — \(remaining) more day\(remaining == 1 ? "" : "s") "
                + "of logs to spot your first pattern."
        } else if symptomaticDays < config.patternMinSymptomDays {
            message = "Still gathering signal — keep logging on the days you don't feel great, "
                + "and a pattern can start to show."
        } else if mixed {
            message = "Still gathering signal — the picture is mixed so far. A bit more logging "
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

    // MARK: - Persistence (I/O — not pure)

    /// Fetches the user's symptom history, runs `assess`, and records the lean.
    ///
    /// `pattern_assessments` has no unique constraint on `user_id` (id PK +
    /// `computed_at`), so this APPENDS a fresh assessment — the table is an
    /// evolving history (tentative → emerging → consistent); the latest by
    /// `computed_at` is the current lean. When there isn't enough signal yet,
    /// nothing is written (the UI shows the "gathering" state from `evaluate`).
    func refresh(repository: Repository, userId: String, asOf: Date = Date()) async throws {
        let logs: [SymptomLogRow] = try await repository.select(
            "symptom_logs",
            filters: ["user_id": "eq.\(userId)"],
            order: "logged_at.asc"
        )
        guard let assessment = assess(logs: logs, asOf: asOf) else { return }

        try await repository.insertVoid("pattern_assessments", [
            "user_id": .string(userId),
            "computed_at": .date(asOf),
            "pattern": .string(assessment.pattern.rawValue),
            "confidence": .string(assessment.confidence.rawValue),
            "evidence_summary": .string(assessment.evidenceSummary),
        ])
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
}
