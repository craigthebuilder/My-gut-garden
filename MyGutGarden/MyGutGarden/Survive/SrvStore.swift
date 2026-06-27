//
//  SrvStore.swift
//  MyGutGarden, Module E. The Survive surface's observable view-model.
//
//  Reads `appState` (CLAUDE.md / Seams.swift) for the RLS-scoped Repository and
//  the signed-in profile, loads the Survive tables (`symptom_logs`,
//  `reintro_challenges`, `pattern_assessments`, `symptom_free_streak`), and owns
//  the writes the surface makes (logging a symptom, starting/resolving a
//  challenge). When the backend is offline it falls back to clearly-labelled
//  sample data so the surface is fully demonstrable end-to-end.
//
//  The symptom-free streak is recomputed locally with SrvStreakEngine (the
//  confounder-freeze rule, SPEC §12/§13) and mirrored to `symptom_free_streak`.
//

import Foundation
import Observation

@MainActor
@Observable
final class SrvStore {
    /// Exposed (read-only-by-convention) so Module-E satellites built from this
    /// store, the FoodStatusStore, the logger's CheckInWriter, the reset, can
    /// reach the RLS-scoped repository + signed-in profile without re-plumbing.
    let appState: AppState

    // Loaded state
    private(set) var logs: [SrvSymptomLogRow] = []
    private(set) var assessments: [PatternAssessmentRow] = []
    private(set) var streak = SrvStreakEngine.Result(current: 0, longest: 0)
    private(set) var lastQualifyingDate: Date?

    // Batch-D multi-entry check-in (new writes go ONLY to these sub-tables; the
    // legacy `symptom_logs` rows above are kept for history). Both feed the streak.
    private(set) var stoolEntries: [StoolEntryRow] = []
    private(set) var symptomEntries: [SymptomEntryRow] = []
    /// Recent meals offered in the logger's "tie this to a photo" control.
    private(set) var recentMeals: [SrvRecentMeal] = []

    // UI state
    private(set) var isLoading = false
    var errorMessage: String?
    /// True when running against the offline sample (no Supabase configured).
    private(set) var usingSampleData = false

    /// Off-ramp preference (Fence 5). In-memory for v1, see report's "gaps".
    var trackingPreference: SrvTrackingPreference = .full

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Derived

    var patternCards: [SrvPatternPresentation] {
        assessments.compactMap(SrvPatternPresenter.present)
    }

    /// A presenter for the Survive per-photo view (reset-aware via appState).
    func makeInsightPresenter() -> SrvInsightPresenter {
        SrvInsightPresenter(appState: appState)
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let repo = appState.repository else {
            loadSample()
            return
        }
        usingSampleData = false
        do {
            async let logRows: [SrvSymptomLogRow] = repo.select("symptom_logs", order: "logged_at.asc")
            async let assessmentRows: [PatternAssessmentRow] = repo.select("pattern_assessments", order: "computed_at.desc")
            async let stoolRows: [StoolEntryRow] = repo.select("stool_entries", order: "log_date.asc")
            async let symptomRows: [SymptomEntryRow] = repo.select("symptom_entries", order: "log_date.asc")
            async let mealRows: [SrvRecentMeal] = repo.select(
                "meals", columns: "id,captured_at,photo_url", order: "captured_at.desc", limit: 12)

            logs = try await logRows
            assessments = try await assessmentRows
            stoolEntries = try await stoolRows
            symptomEntries = try await symptomRows
            recentMeals = try await mealRows
            recomputeStreak()
            await persistStreak()
        } catch {
            errorMessage = "Couldn't load your Survive data. Pull to retry."
        }
    }

    // MARK: - Daily check-in (Batch D, via the shared CheckInKit writer)

    /// Persist a multi-entry evening check-in through the SPINE `CheckInWriter`
    /// (the single mood-inversion point). New rows land in the sub-entry tables
    /// only, never a fresh `symptom_logs` row. Refreshes the streak after.
    @discardableResult
    func saveCheckIn(_ draft: CheckInDraft) async -> Bool {
        guard let repo = appState.repository, let uid = appState.profile?.id else {
            // Offline/demo: keep the surface live by folding the draft into the
            // in-memory sub-entry arrays so the streak still responds.
            appendLocalCheckIn(draft)
            recomputeStreak()
            return true
        }
        do {
            try await CheckInWriter(repository: repo, userId: uid).save(draft)
            await load()
            return true
        } catch {
            errorMessage = "Couldn't save your check-in. It's still here, try again."
            return false
        }
    }

    // MARK: - Symptom logging

    /// Persist tonight's check-in, then refresh the streak. Returns success.
    @discardableResult
    func saveLog(_ draft: SrvSymptomDraft) async -> Bool {
        guard let repo = appState.repository, let uid = appState.profile?.id else {
            // Offline: keep the surface live by appending a local row.
            appendLocalLog(draft)
            recomputeStreak()
            return true
        }
        do {
            try await repo.insertVoid("symptom_logs", draft.insertBody(userID: uid))
            await load()
            return true
        } catch {
            errorMessage = "Couldn't save your check-in. It's still here, try again."
            return false
        }
    }

    // MARK: - Off-ramp (Fence 5)

    /// Leave Survive for Thrive, blameless, "let's go back to basics" (SPEC §2).
    func leaveSurvive() async {
        await appState.setMode(.thrive)
    }

    // MARK: - Streak math

    func recomputeStreak() {
        let days = mergedDailySymptoms()
        streak = SrvStreakEngine.reduce(days.map { SrvStreakEngine.outcome(for: $0.symptoms) })
        lastQualifyingDate = days.last { SrvStreakEngine.outcome(for: $0.symptoms) == .feltGood }?.date
    }

    /// The streak's view of every day, merging legacy `symptom_logs` history with
    /// the new Batch-D sub-entry tables (`stool_entries` + `symptom_entries`),
    /// worst-of-day. Output shape is unchanged so SrvStreakEngine input is too.
    /// (The static `dailySymptoms(from:)` below is retained for the unit tests.)
    func mergedDailySymptoms() -> [(date: Date, symptoms: SrvDaySymptoms)] {
        var byDay: [Date: SrvDaySymptoms] = [:]
        for (date, symptoms) in Self.dailySymptoms(from: logs) { byDay[date] = symptoms }

        // Sub-entry stool rows → Bristol per day.
        for s in stoolEntries {
            guard let day = Self.dayDate(s.logDate),
                  let bss = s.bss, let bristol = SrvBristolType(rawValue: bss) else { continue }
            let incoming = SrvDaySymptoms(bristol: bristol)
            byDay[day] = byDay[day].map { Self.merge($0, incoming) } ?? incoming
        }
        // Sub-entry symptom rows → per-type severity per day.
        for e in symptomEntries {
            guard let day = Self.dayDate(e.logDate) else { continue }
            let sev = SrvSeverity(clampingDBValue: e.severity)
            var incoming = SrvDaySymptoms()
            switch e.symptomType {
            case "bloating": incoming.bloating = sev
            case "gas": incoming.gas = sev
            case "pain": incoming.pain = sev
            case "urgency": incoming.urgency = sev
            default: continue
            }
            byDay[day] = byDay[day].map { Self.merge($0, incoming) } ?? incoming
        }
        return byDay.keys.sorted().map { (date: $0, symptoms: byDay[$0]!) }
    }

    /// "yyyy-MM-dd" (sub-entry `log_date`) → start-of-day Date.
    private nonisolated static func dayDate(_ logDate: String) -> Date? {
        dayParser.date(from: logDate).map { Calendar.current.startOfDay(for: $0) }
    }
    private nonisolated static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private func persistStreak() async {
        guard let repo = appState.repository, let uid = appState.profile?.id else { return }
        var body: [String: PGValue] = [
            "user_id": .string(uid),
            "current_streak": .int(streak.current),
            "longest_streak": .int(streak.longest)
        ]
        if let date = lastQualifyingDate {
            body["last_qualifying_date"] = .string(Self.isoDay.string(from: date))
        }
        try? await repo.upsert("symptom_free_streak", body, onConflict: "user_id")
    }

    /// Collapse logs into one `SrvDaySymptoms` per local calendar day (worst
    /// severity + union of confounders), oldest → newest.
    nonisolated static func dailySymptoms(from logs: [SrvSymptomLogRow]) -> [(date: Date, symptoms: SrvDaySymptoms)] {
        let calendar = Calendar.current
        var byDay: [Date: SrvDaySymptoms] = [:]
        for log in logs {
            guard let date = log.loggedDate else { continue }
            let day = calendar.startOfDay(for: date)
            let incoming = log.daySymptoms
            if let existing = byDay[day] {
                byDay[day] = merge(existing, incoming)
            } else {
                byDay[day] = incoming
            }
        }
        return byDay.keys.sorted().map { (date: $0, symptoms: byDay[$0]!) }
    }

    /// Worst-of-the-day merge so a single rough log can't be averaged away.
    private nonisolated static func merge(_ a: SrvDaySymptoms, _ b: SrvDaySymptoms) -> SrvDaySymptoms {
        func worse(_ x: SrvSeverity, _ y: SrvSeverity) -> SrvSeverity {
            x.rank >= y.rank ? x : y
        }
        let bristol: SrvBristolType? = {
            let ad = a.bristol?.deviationSeverity.rank ?? -1
            let bd = b.bristol?.deviationSeverity.rank ?? -1
            return bd > ad ? b.bristol : a.bristol
        }()
        return SrvDaySymptoms(
            bristol: bristol,
            bloating: worse(a.bloating, b.bloating),
            gas: worse(a.gas, b.gas),
            pain: worse(a.pain, b.pain),
            urgency: worse(a.urgency, b.urgency),
            confounders: Array(Set(a.confounders).union(b.confounders))
        )
    }

    // MARK: - Helpers

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    // MARK: - Offline sample

    private func loadSample() {
        usingSampleData = true
        logs = SrvSampleData.logs()
        assessments = SrvSampleData.assessments()
        recomputeStreak()
    }

    /// Offline fold of a multi-entry check-in into the in-memory sub-entry arrays
    /// so the streak responds without a backend (demo/preview only).
    private func appendLocalCheckIn(_ draft: CheckInDraft) {
        let day = Self.dayParser.string(from: draft.logDate)
        let uid = appState.profile?.id ?? "local"
        let now = ISO8601DateFormatter().string(from: Date())
        for s in draft.stools {
            stoolEntries.append(StoolEntryRow(
                id: UUID().uuidString, userId: uid, logDate: day, bss: s.bss,
                occurredAt: nil, linkedMealId: s.linkedMealId, loggedAt: now))
        }
        for s in draft.symptoms {
            symptomEntries.append(SymptomEntryRow(
                id: UUID().uuidString, userId: uid, logDate: day,
                symptomType: s.symptomType, severity: s.severity, gasOdor: s.gasOdor,
                occurredAt: nil, linkedMealId: s.linkedMealId))
        }
    }

    private func appendLocalLog(_ draft: SrvSymptomDraft) {
        let iso = ISO8601DateFormatter()
        logs.append(SrvSymptomLogRow(
            id: UUID().uuidString,
            loggedAt: iso.string(from: Date()),
            bss: draft.bristol?.rawValue,
            bloating: draft.bloating.rawValue,
            gas: draft.gas.rawValue,
            pain: draft.pain.rawValue,
            urgency: draft.urgency.rawValue,
            mood: draft.mood,
            brainFog: draft.brainFog,
            gasOdor: draft.gasOdor?.rawValue,
            mealTiming: draft.timing?.rawValue,
            foodCorrelation: draft.foodCorrelation.isEmpty ? nil : draft.foodCorrelation,
            confounders: draft.confounders.map(\.rawValue),
            notes: draft.notes.isEmpty ? nil : draft.notes
        ))
    }
}

// MARK: - Recent meal (tie-to-photo target in the logger)

/// A lightweight recent meal for the logger's "tie this to a photo" control.
/// Decoded from `meals` (id + captured_at + photo presence only).
struct SrvRecentMeal: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let capturedAt: String
    let photoUrl: String?

    var capturedDate: Date? { SrvDateParse.timestamp(capturedAt) }

    /// A short, human label, e.g. "1:30 PM meal". No meal-type in the schema yet,
    /// so we anchor on time of day (DESIGN copy stays calm + concrete).
    var label: String {
        guard let d = capturedDate else { return "a recent meal" }
        return "\(d.formatted(date: .omitted, time: .shortened)) meal"
    }
}

// MARK: - Off-ramp preference (Fence 5)

enum SrvTrackingPreference: String, CaseIterable, Sendable, Identifiable {
    case full       // the full evening check-in
    case lite       // a softer, fewer-questions check-in
    case paused     // taking a break; progress is kept

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: "Full check-in"
        case .lite: "Light check-in"
        case .paused: "Paused"
        }
    }
}
