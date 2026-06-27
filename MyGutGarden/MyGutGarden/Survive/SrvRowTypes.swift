//
//  SrvRowTypes.swift
//  MyGutGarden, Module E. Survive-local row decoding + the logger draft.
//
//  The shared `SymptomLogRow` in Repository.swift decodes only the columns the
//  coordinator needs; the logger needs the full row, so Module E decodes its
//  own richer type via the generic `Repository.select` (snake_case → camelCase
//  via the repo's `.convertFromSnakeCase` decoder).
//

import Foundation

// MARK: - Full symptom-log row (Module-E read model)

nonisolated struct SrvSymptomLogRow: Decodable, Sendable, Identifiable {
    let id: String
    let loggedAt: String
    let bss: Int?
    let bloating: Int?
    let gas: Int?
    let pain: Int?
    let urgency: Int?
    let mood: Int?
    let brainFog: Int?
    let gasOdor: String?
    let mealTiming: String?
    let foodCorrelation: String?
    let confounders: [String]
    let notes: String?

    /// ISO8601 → Date (Postgres `timestamptz`).
    nonisolated var loggedDate: Date? {
        SrvDateParse.timestamp(loggedAt)
    }

    /// Reduce to the streak's view of the day.
    nonisolated var daySymptoms: SrvDaySymptoms {
        SrvDaySymptoms(
            bristol: bss.flatMap(SrvBristolType.init(rawValue:)),
            bloating: SrvSeverity(clampingDBValue: bloating),
            gas: SrvSeverity(clampingDBValue: gas),
            pain: SrvSeverity(clampingDBValue: pain),
            urgency: SrvSeverity(clampingDBValue: urgency),
            confounders: confounders.compactMap(SrvConfounder.init(rawValue:))
        )
    }
}

// MARK: - Date parsing helper

enum SrvDateParse {
    nonisolated static func timestamp(_ s: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}

// MARK: - The evening logger draft (~20 sec; SPEC §11b, §12)

/// Editable state the symptom logger binds to, plus its write mapping. Default
/// is a calm "nothing to report" so the fast path is a couple of taps.
struct SrvSymptomDraft: Sendable, Equatable {
    var bristol: SrvBristolType?
    var bloating: SrvSeverity = .none
    var gas: SrvSeverity = .none
    var pain: SrvSeverity = .none
    var urgency: SrvSeverity = .none
    var mood: Int?            // 1–5
    var brainFog: Int?        // 1–5
    var gasOdor: SrvGasOdor?
    var timing: SrvMealTiming?
    var foodCorrelation: String = ""
    var confounders: Set<SrvConfounder> = []
    var notes: String = ""

    /// What the streak engine sees (live preview while logging).
    nonisolated var daySymptoms: SrvDaySymptoms {
        SrvDaySymptoms(
            bristol: bristol,
            bloating: bloating,
            gas: gas,
            pain: pain,
            urgency: urgency,
            confounders: Array(confounders)
        )
    }

    /// PostgREST insert body for `symptom_logs`. Severities persist as 0–3 ints
    /// (matches the schema's `int` columns); the server stamps `logged_at`.
    nonisolated func insertBody(userID: String) -> [String: PGValue] {
        var body: [String: PGValue] = [
            "user_id": .string(userID),
            "bloating": .int(bloating.rawValue),
            "gas": .int(gas.rawValue),
            "pain": .int(pain.rawValue),
            "urgency": .int(urgency.rawValue),
            "confounders": .stringArray(confounders.map(\.rawValue))
        ]
        body["bss"] = bristol.map { .int($0.rawValue) } ?? .null
        body["mood"] = mood.map { .int($0) } ?? .null
        body["brain_fog"] = brainFog.map { .int($0) } ?? .null
        body["gas_odor"] = gasOdor.map { .string($0.rawValue) } ?? .null
        body["meal_timing"] = timing.map { .string($0.rawValue) } ?? .null
        let trimmedCorrelation = foodCorrelation.trimmingCharacters(in: .whitespacesAndNewlines)
        body["food_correlation"] = trimmedCorrelation.isEmpty ? .null : .string(trimmedCorrelation)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        body["notes"] = trimmedNotes.isEmpty ? .null : .string(trimmedNotes)
        return body
    }
}

// MARK: - Food pokédex model (Safe / Triggers / timeline)

/// A food the user is tracking through Survive. Safe vs trigger is derived from
/// its dominant FODMAP group and whether that group has been cleared (passed).
struct SrvTrackedFood: Identifiable, Sendable, Equatable {
    let name: String
    let safety: FodmapSafety
    /// The group most responsible for this food's caution (nil = inherently safe).
    let dominantGroup: SrvFodmapGroup?
    /// Observed reaction severity when last eaten (nil = not yet linked).
    var observedSeverity: SrvSeverity?

    var id: String { name }

    /// Cleared once its dominant group has passed a challenge, then it's safe
    /// to fold back into the collection (the visible win, SPEC §11b).
    nonisolated func isCleared(clearedGroups: Set<SrvFodmapGroup>) -> Bool {
        guard let group = dominantGroup else { return true }
        return clearedGroups.contains(group)
    }

    nonisolated func isSafe(clearedGroups: Set<SrvFodmapGroup>) -> Bool {
        safety == .green || isCleared(clearedGroups: clearedGroups)
    }
}
