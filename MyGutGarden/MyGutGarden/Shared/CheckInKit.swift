//
//  CheckInKit.swift
//  MyGutGarden, the reusable multi-entry daily check-in (SPINE-owned, Batch D/E).
//
//  Used by BOTH the Survive logger and the new Thrive "test" tab, so neither
//  reimplements multi-entry persistence. It is the SINGLE place the mood-polarity
//  inversion happens: the UI presents regulated→erratic (1=regulated), and we store
//  the CANONICAL high=better score (5=regulated) via `6 - uiValue`, so the pattern
//  engine never sees mixed polarities.
//

import Foundation
import Observation

/// Written into every sub-entry row's `context` column.
enum CheckInContext: String, Sendable {
    case surviveLogger = "survive_logger"
    case thriveCheckin = "thrive_checkin"
    case thriveTestTab = "thrive_test_tab"
}

// MARK: - Drafts (one row each; the user can add several of any kind)

struct StoolEntryDraft: Identifiable, Sendable {
    let id = UUID()
    var bss: Int?
    var occurredAt: Date?
    var linkedMealId: String?
}

struct SymptomEntryDraft: Identifiable, Sendable {
    let id = UUID()
    var symptomType: String        // bloating | gas | pain | urgency
    var severity: Int              // 0..3 (SrvSeverity)
    var gasOdor: String?           // only when symptomType == "gas"
    var occurredAt: Date?
    var linkedMealId: String?
}

struct MoodEntryDraft: Identifiable, Sendable {
    let id = UUID()
    var uiValue: Int               // 1 = regulated (best) .. 5 = erratic (worst), as shown
    var occurredAt: Date?
    var linkedMealId: String?
    /// CANONICAL high=better, the ONLY inversion point in the whole app.
    var storedScore: Int { 6 - uiValue }
}

struct CheckInNoteDraft: Identifiable, Sendable {
    let id = UUID()
    var content: String
    var linkedMealId: String?
}

// MARK: - Draft container

@Observable @MainActor
final class CheckInDraft {
    var logDate: Date = Date()
    var context: CheckInContext
    var stools: [StoolEntryDraft] = []
    var symptoms: [SymptomEntryDraft] = []   // multiple per type (bloating/gas/pain/urgency)
    var moods: [MoodEntryDraft] = []
    var notes: [CheckInNoteDraft] = []
    /// Thrive test-tab "light check-in": collapses the form to mood-only.
    var lightMode = false

    init(context: CheckInContext) { self.context = context }
}

// MARK: - Writer (fans the drafts out to the sub-entry tables)

@MainActor
struct CheckInWriter {
    let repository: Repository
    let userId: String

    /// Inserts every draft entry across stool_entries / symptom_entries /
    /// mood_entries / checkin_notes concurrently. mood_score is written from
    /// `MoodEntryDraft.storedScore` (the single 6 - uiValue inversion).
    func save(_ draft: CheckInDraft) async throws {
        let repo = repository
        let uid = userId
        let day = Self.dateString(draft.logDate)
        let ctx = draft.context.rawValue

        try await withThrowingTaskGroup(of: Void.self) { group in
            for s in draft.stools {
                let body = Self.stoolBody(s, userId: uid, day: day)
                group.addTask { try await repo.insertVoid("stool_entries", body) }
            }
            for s in draft.symptoms {
                let body = Self.symptomBody(s, userId: uid, day: day)
                group.addTask { try await repo.insertVoid("symptom_entries", body) }
            }
            for m in draft.moods {
                let body = Self.moodBody(m, userId: uid, day: day, context: ctx)
                group.addTask { try await repo.insertVoid("mood_entries", body) }
            }
            for n in draft.notes {
                let body = Self.noteBody(n, userId: uid, day: day, context: ctx)
                group.addTask { try await repo.insertVoid("checkin_notes", body) }
            }
            try await group.waitForAll()
        }
    }

    /// The camera / test-tab auto-write path: append one mood entry without any UI
    /// being opened (e.g. the "How did the [food] feel?" answer).
    func appendMood(uiValue: Int, context: CheckInContext, linkedMealId: String?, on date: Date) async throws {
        let body = Self.moodBody(
            MoodEntryDraft(uiValue: uiValue, occurredAt: nil, linkedMealId: linkedMealId),
            userId: userId, day: Self.dateString(date), context: context.rawValue)
        try await repository.insertVoid("mood_entries", body)
    }

    // MARK: Body builders (pure, Sendable)
    // Typed `opt` overloads keep these dict literals fast to type-check.

    private static func opt(_ v: Int?)    -> PGValue { v.map { PGValue.int($0) }    ?? .null }
    private static func opt(_ v: String?) -> PGValue { v.map { PGValue.string($0) } ?? .null }
    private static func opt(_ v: Date?)   -> PGValue { v.map { PGValue.date($0) }   ?? .null }

    private static func stoolBody(_ s: StoolEntryDraft, userId: String, day: String) -> [String: PGValue] {
        ["user_id": .string(userId), "log_date": .string(day),
         "bss": opt(s.bss), "occurred_at": opt(s.occurredAt), "linked_meal_id": opt(s.linkedMealId)]
    }

    private static func symptomBody(_ s: SymptomEntryDraft, userId: String, day: String) -> [String: PGValue] {
        ["user_id": .string(userId), "log_date": .string(day),
         "symptom_type": .string(s.symptomType), "severity": .int(s.severity),
         "gas_odor": opt(s.gasOdor), "occurred_at": opt(s.occurredAt), "linked_meal_id": opt(s.linkedMealId)]
    }

    private static func moodBody(_ m: MoodEntryDraft, userId: String, day: String, context: String) -> [String: PGValue] {
        ["user_id": .string(userId), "log_date": .string(day),
         "mood_score": .int(m.storedScore),           // 6 - uiValue (canonical high=better)
         "context": .string(context),
         "occurred_at": opt(m.occurredAt), "linked_meal_id": opt(m.linkedMealId)]
    }

    private static func noteBody(_ n: CheckInNoteDraft, userId: String, day: String, context: String) -> [String: PGValue] {
        ["user_id": .string(userId), "log_date": .string(day),
         "content": .string(n.content), "context": .string(context),
         "linked_meal_id": opt(n.linkedMealId)]
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static func dateString(_ date: Date) -> String { dayFormatter.string(from: date) }
}
