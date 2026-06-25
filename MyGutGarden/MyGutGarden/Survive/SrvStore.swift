//
//  SrvStore.swift
//  MyGutGarden — Module E. The Survive surface's observable view-model.
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
    private let appState: AppState

    // Loaded state
    private(set) var logs: [SrvSymptomLogRow] = []
    private(set) var challenges: [SrvChallenge] = []
    private(set) var assessments: [PatternAssessmentRow] = []
    private(set) var trackedFoods: [SrvTrackedFood] = []
    private(set) var streak = SrvStreakEngine.Result(current: 0, longest: 0)
    private(set) var lastQualifyingDate: Date?

    // UI state
    private(set) var isLoading = false
    var errorMessage: String?
    /// True when running against the offline sample (no Supabase configured).
    private(set) var usingSampleData = false

    /// Off-ramp preference (Fence 5). In-memory for v1 — see report's "gaps".
    var trackingPreference: SrvTrackingPreference = .full

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Derived

    var clearedGroups: Set<SrvFodmapGroup> { SrvReintroEngine.clearedGroups(challenges) }
    var activeTestingGroups: [SrvFodmapGroup] {
        challenges.filter { $0.status == .testing }.map(\.group)
    }
    var patternCards: [SrvPatternPresentation] {
        assessments.compactMap(SrvPatternPresenter.present)
    }
    var safeFoods: [SrvTrackedFood] {
        trackedFoods.filter { $0.isSafe(clearedGroups: clearedGroups) }
    }
    var triggerFoods: [SrvTrackedFood] {
        trackedFoods.filter { !$0.isSafe(clearedGroups: clearedGroups) }
    }

    /// A presenter for the Survive per-photo view, aware of what's being tested.
    func makeInsightPresenter() -> SrvInsightPresenter {
        SrvInsightPresenter(activeReintroGroups: activeTestingGroups)
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
            async let challengeRows: [ReintroChallengeRow] = repo.select("reintro_challenges")
            async let assessmentRows: [PatternAssessmentRow] = repo.select("pattern_assessments", order: "computed_at.desc")

            logs = try await logRows
            challenges = try await challengeRows.compactMap(Self.challenge(from:))
            assessments = try await assessmentRows
            if trackedFoods.isEmpty { trackedFoods = SrvSampleData.trackedFoods }
            recomputeStreak()
            await persistStreak()
        } catch {
            errorMessage = "Couldn't load your Survive data. Pull to retry."
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
            errorMessage = "Couldn't save your check-in. It's still here — try again."
            return false
        }
    }

    // MARK: - Reintro challenges

    func startChallenge(_ group: SrvFodmapGroup, now: Date = .init()) async {
        if let existing = challenges.first(where: { $0.group == group }) {
            await write(SrvReintroEngine.started(existing, at: now))
        } else {
            let new = SrvChallenge(id: UUID().uuidString, group: group, status: .testing, startedAt: now, endedAt: nil)
            await write(new, isNew: true)
        }
    }

    func resolveChallenge(_ challenge: SrvChallenge, tolerated: Bool, now: Date = .init()) async {
        let resolved = SrvReintroEngine.resolved(challenge, tolerated: tolerated, at: now)
        await write(resolved)
        // Clearing a group is a relief win — surface it via the Thrive channel
        // only if the user is in Thrive; in Survive nothing rewards restriction.
        if tolerated { appState.celebrate(.guildUnlock(displayName: challenge.group.displayName)) }
    }

    private func write(_ challenge: SrvChallenge, isNew: Bool = false) async {
        // Optimistic local update so the surface responds instantly.
        if let idx = challenges.firstIndex(where: { $0.id == challenge.id }) {
            challenges[idx] = challenge
        } else {
            challenges.append(challenge)
        }

        guard let repo = appState.repository, let uid = appState.profile?.id else { return }
        var body: [String: PGValue] = [
            "user_id": .string(uid),
            "fodmap_group": .string(challenge.group.rawValue),
            "status": .string(challenge.status.rawValue)
        ]
        body["started_at"] = challenge.startedAt.map { .date($0) } ?? .null
        body["ended_at"] = challenge.endedAt.map { .date($0) } ?? .null
        do {
            if isNew {
                try await repo.insertVoid("reintro_challenges", body)
            } else {
                try await repo.update("reintro_challenges", set: body, filters: ["id": "eq.\(challenge.id)"])
            }
        } catch {
            errorMessage = "Couldn't update your challenge. Try again."
        }
    }

    // MARK: - Off-ramp (Fence 5)

    /// Leave Survive for Thrive — blameless, "let's go back to basics" (SPEC §2).
    func leaveSurvive() async {
        await appState.setMode(.thrive)
    }

    // MARK: - Streak math

    func recomputeStreak() {
        let days = Self.dailySymptoms(from: logs)
        streak = SrvStreakEngine.reduce(days.map { SrvStreakEngine.outcome(for: $0.symptoms) })
        lastQualifyingDate = days.last { SrvStreakEngine.outcome(for: $0.symptoms) == .feltGood }?.date
    }

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

    private nonisolated static func challenge(from row: ReintroChallengeRow) -> SrvChallenge? {
        guard
            let group = SrvFodmapGroup(rawValue: row.fodmapGroup),
            let status = SrvReintroStatus(rawValue: row.status)
        else { return nil }
        return SrvChallenge(
            id: row.id,
            group: group,
            status: status,
            startedAt: row.startedAt.flatMap(SrvDateParse.timestamp),
            endedAt: row.endedAt.flatMap(SrvDateParse.timestamp)
        )
    }

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
        challenges = SrvSampleData.challenges()
        assessments = SrvSampleData.assessments()
        trackedFoods = SrvSampleData.trackedFoods
        recomputeStreak()
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
