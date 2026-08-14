//
//  CheckInKit.swift
//  MyGutGarden, the reusable multi-entry daily check-in (SPINE-owned).
//
//  The SINGLE place the mood-polarity inversion happens: the UI presents
//  regulated→erratic (1=regulated), and we store the CANONICAL high=better score
//  (5=regulated) via `6 - uiValue`, so downstream never sees mixed polarities.
//

import Foundation
import Observation

/// Written into every sub-entry row's `context` column.
enum CheckInContext: String, Sendable {
    case thriveCheckin = "thrive_checkin"
}

// MARK: - Drafts (one row each; the user can add several of any kind)

/// Transient label for a meal-linked time tie ("30 min after meal"). NOT persisted
/// directly: on save we write `occurredAt = mealCapturedAt + offset` and
/// `linkedMealId`, and the UI re-derives this label from `mealOffsetMinutes`.
/// The DB records WHICH meal; the UI doesn't name it (Batch C).
let mealTieOffsets: [Int] = [0, 30, 60, 90, 120, 180]
func mealTieLabel(_ minutes: Int) -> String {
    switch minutes {
    case 0:   return "Right after a meal"
    case 180: return "3+ hours after a meal"
    default:  return "\(minutes) min after a meal"
    }
}

struct StoolEntryDraft: Identifiable, Sendable {
    let id = UUID()
    var bss: Int?
    var occurredAt: Date?
    var linkedMealId: String?
    var mealOffsetMinutes: Int?    // transient label only (see mealTieLabel)
}

struct SymptomEntryDraft: Identifiable, Sendable {
    let id = UUID()
    var symptomType: String        // bloating | gas | pain | urgency
    var severity: Int              // 0..3
    var gasOdor: String?           // only when symptomType == "gas"
    var occurredAt: Date?
    var linkedMealId: String?
    var mealOffsetMinutes: Int?
}

struct MoodEntryDraft: Identifiable, Sendable {
    let id = UUID()
    var uiValue: Int               // 1 = regulated (best) .. 5 = erratic (worst), as shown
    var occurredAt: Date?
    var linkedMealId: String?
    var mealOffsetMinutes: Int?
    /// CANONICAL high=better, the ONLY inversion point in the whole app.
    var storedScore: Int { 6 - uiValue }
}

/// Energy / Clarity: high=better scalars stored DIRECTLY (no inversion, unlike mood).
struct MetricEntryDraft: Identifiable, Sendable {
    let id = UUID()
    var metricType: String         // "energy" | "clarity"
    var score: Int                 // 1 = low .. 5 = high (high is better, stored as-is)
    var occurredAt: Date?
    var linkedMealId: String?
    var mealOffsetMinutes: Int?
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
    var energy: [MetricEntryDraft] = []      // Batch C: high=better
    var clarity: [MetricEntryDraft] = []     // Batch C: high=better
    var notes: [CheckInNoteDraft] = []
    /// Thrive "light check-in" (Batch C): when non-nil, only this one category is
    /// shown/saved. Persisted on users.light_checkin_category, so it stays until the
    /// user de-selects it. nil = full check-in.
    var lightCategory: CheckInCategory?
    var lightMode: Bool { lightCategory != nil }
    /// Customized check-in (SPEC §12): which categories to show. nil = all (default).
    var enabledCategories: Set<CheckInCategory>?
    var notesEnabled = true

    init(context: CheckInContext) { self.context = context }

    /// Seeds ONE empty entry per active category (R3/R4: every category starts with
    /// one, including EACH symptom subtype and "Anything else?", so nothing needs a
    /// "+" to begin). Empty = an UNSET sentinel (bss nil / severity 0 / uiValue 0 /
    /// score 0 / empty note); the writer skips unset entries, so an untouched seed is
    /// never saved. In light mode only the chosen category is seeded/shown.
    func seedEmptyEntries() {
        func active(_ c: CheckInCategory) -> Bool {
            (lightCategory == nil || lightCategory == c) && (enabledCategories?.contains(c) ?? true)
        }
        stools = active(.stool) ? [StoolEntryDraft()] : []
        symptoms = active(.symptom)
            ? ["bloating", "gas", "pain", "urgency"].map { SymptomEntryDraft(symptomType: $0, severity: 0) }
            : []
        moods = active(.mood)      ? [MoodEntryDraft(uiValue: 0)] : []
        energy = active(.energy)   ? [MetricEntryDraft(metricType: "energy", score: 0)] : []
        clarity = active(.clarity) ? [MetricEntryDraft(metricType: "clarity", score: 0)] : []
        notes = (lightCategory == nil && notesEnabled) ? [CheckInNoteDraft(content: "")] : []
    }
}

/// The Bristol stool types as an ICON grid (shared by both modes' check-in so they
/// look identical). Stored value is just the Int (1...7); this only drives display.
enum CheckInBristol: Int, CaseIterable, Identifiable, Sendable {
    case type1 = 1, type2, type3, type4, type5, type6, type7
    var id: Int { rawValue }
    var systemImage: String {
        switch self {
        case .type1: return "circle.grid.3x3.fill"
        case .type2: return "circle.grid.2x2.fill"
        case .type3: return "capsule.portrait.fill"
        case .type4: return "capsule.fill"
        case .type5: return "drop.fill"
        case .type6: return "cloud.fill"
        case .type7: return "wave.3.forward"
        }
    }
    var title: String {
        switch self {
        case .type1: return "Separate lumps"
        case .type2: return "Lumpy"
        case .type3: return "Cracked"
        case .type4: return "Smooth"
        case .type5: return "Soft blobs"
        case .type6: return "Mushy"
        case .type7: return "Liquid"
        }
    }
}

/// The five check-in categories. Drives the light-check-in single-category pick and
/// the persisted users.light_checkin_category value.
enum CheckInCategory: String, CaseIterable, Sendable, Identifiable {
    case stool, symptom, mood, energy, clarity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stool:   return "Stool"
        case .symptom: return "Symptoms"
        case .mood:    return "Mood"
        case .energy:  return "Energy"
        case .clarity: return "Clarity"
        }
    }
}

// MARK: - Writer (one check_in + a check_in_entry per set field, SPEC §5/§12)

@MainActor
struct CheckInWriter {
    let repository: Repository
    let userId: String

    private struct CheckInIdRow: Decodable { let id: String }

    /// The full form: create one `check_ins` row (source='full'), then fan out one
    /// `check_in_entries` row per set field. `section_key` is the field's key; mood is
    /// written from `storedScore` (the single 6 - uiValue inversion, canonical high=better).
    func save(_ draft: CheckInDraft) async throws {
        let day = Self.dateString(draft.logDate)
        let checkInId = try await createCheckIn(day: day, source: "full")
        let repo = repository, uid = userId

        try await withThrowingTaskGroup(of: Void.self) { group in
            for s in draft.stools where s.bss != nil {          // skip untouched seed
                let b = Self.entry(checkInId, uid, "bss", int: s.bss, text: nil, at: s.occurredAt, meal: s.linkedMealId)
                group.addTask { try await repo.insertVoid("check_in_entries", b) }
            }
            for s in draft.symptoms where s.severity > 0 {      // 0 = "none"
                let b = Self.entry(checkInId, uid, s.symptomType, int: s.severity, text: s.gasOdor, at: s.occurredAt, meal: s.linkedMealId)
                group.addTask { try await repo.insertVoid("check_in_entries", b) }
            }
            for m in draft.moods where m.uiValue >= 1 {         // 0 = unset seed
                let b = Self.entry(checkInId, uid, "mood", int: m.storedScore, text: nil, at: m.occurredAt, meal: m.linkedMealId)
                group.addTask { try await repo.insertVoid("check_in_entries", b) }
            }
            for e in (draft.energy + draft.clarity) where e.score >= 1 {
                let b = Self.entry(checkInId, uid, e.metricType, int: e.score, text: nil, at: e.occurredAt, meal: e.linkedMealId)
                group.addTask { try await repo.insertVoid("check_in_entries", b) }
            }
            for n in draft.notes where !n.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let b = Self.entry(checkInId, uid, "notes", int: nil, text: n.content, at: nil, meal: n.linkedMealId)
                group.addTask { try await repo.insertVoid("check_in_entries", b) }
            }
            try await group.waitForAll()
        }
    }

    /// Meal-followup mood (no UI opened, e.g. a "how did that sit?" answer): a small
    /// check_in (source='meal_followup') + one mood entry.
    func appendMood(uiValue: Int, context: CheckInContext, linkedMealId: String?, on date: Date) async throws {
        let checkInId = try await createCheckIn(day: Self.dateString(date), source: "meal_followup")
        let b = Self.entry(checkInId, userId, "mood", int: 6 - uiValue, text: nil, at: nil, meal: linkedMealId)
        try await repository.insertVoid("check_in_entries", b)
    }

    /// The daily pop-up "did you feel okay?" → a check_in (source='daily_popup') + a
    /// `felt_okay` entry. `discomfort` is 0 (great) .. 3 (rough) — the guardian reads it (SPEC §11).
    func saveDailyFeltOkay(discomfort: Int, on date: Date) async throws {
        let day = Self.dateString(date)
        // Idempotent: a retried answer (relaunch after a slow/failed-looking
        // write that actually committed) must not double-count discomfort in
        // the guardian's input (Fence 3).
        let existing: [CheckInIdRow] = try await repository.select(
            "check_ins", columns: "id",
            filters: ["log_date": "eq.\(day)", "source": "eq.daily_popup"], limit: 1)
        guard existing.isEmpty else { return }
        let checkInId = try await createCheckIn(day: day, source: "daily_popup")
        let b = Self.entry(checkInId, userId, "felt_okay", int: discomfort, text: nil, at: nil, meal: nil)
        try await repository.insertVoid("check_in_entries", b)
    }

    private func createCheckIn(day: String, source: String) async throws -> String {
        let rows: [CheckInIdRow] = try await repository.insert("check_ins",
            ["user_id": .string(userId), "log_date": .string(day), "source": .string(source)])
        guard let id = rows.first?.id else {
            throw SupabaseError.server(status: -1, message: "check_in insert returned no id")
        }
        return id
    }

    // MARK: One entry body (pure, Sendable). Typed maps keep it fast to type-check.

    private static func entry(_ checkInId: String, _ userId: String, _ section: String,
                              int: Int?, text: String?, at: Date?, meal: String?) -> [String: PGValue] {
        ["check_in_id": .string(checkInId), "user_id": .string(userId), "section_key": .string(section),
         "value_int": int.map { PGValue.int($0) } ?? .null,
         "value_text": text.map { PGValue.string($0) } ?? .null,
         "occurred_at": at.map { PGValue.date($0) } ?? .null,
         "linked_meal_id": meal.map { PGValue.string($0) } ?? .null]
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static func dateString(_ date: Date) -> String { dayFormatter.string(from: date) }
}
