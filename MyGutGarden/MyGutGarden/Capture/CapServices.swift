//
//  CapServices.swift
//  MyGutGarden — Module B I/O: photo upload (Supabase Storage), food search,
//  and meal persistence (SPEC §4, §5). Table CRUD goes through the shared
//  `Repository`; the Storage upload is Module B's own small call (Repository
//  covers PostgREST, not the Storage API).
//
//  ⚠️ jsonb caveat: `Repository.insert` bodies are `[String: PGValue]`, and
//  `PGValue` has no nested-JSON case, so `vision_raw_json` and
//  `hidden_ingredient_answers` are persisted as JSON *strings*. This is lossless
//  and valid jsonb, but stores a string scalar rather than a parsed object.
//  GAP for the orchestrator: add a `PGValue.json(Any)` case (one line in
//  Repository.swift) and switch the two fields below to it for structured jsonb.
//

import Foundation

// MARK: - JSON helpers

enum CapJSON {
    /// Encode a Codable value (e.g. the frozen vision contract) to a snake_case
    /// JSON string for a jsonb column.
    static func string(from value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Serialize a loose JSON object (the hidden-answers payload) to a string.
    static func string(fromObject object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Photo upload (Supabase Storage bucket `meal-photos`)

/// Uploads a meal photo to `meal-photos/<userId>/<uuid>.jpg` using the user's
/// access token (the bucket + RLS already exist). Returns the stored object URL
/// for `meals.photo_url`. Best-effort: the caller logs the meal even if this
/// fails, so a flaky upload never blocks the user.
struct CapStorageUploader: Sendable {
    let baseURL: URL
    let anonKey: String
    static let bucket = "meal-photos"

    init(baseURL: URL = SupabaseConfig.baseURL, anonKey: String = SupabaseConfig.anonKey) {
        self.baseURL = baseURL
        self.anonKey = anonKey
    }

    /// - Returns: the stored object URL (authenticated endpoint). Downstream
    ///   display may need a signed URL; out of Module B's scope.
    func upload(imageData: Data, userId: String, accessToken: String) async throws -> String {
        let path = "\(userId)/\(UUID().uuidString).jpg"
        let objectPath = "storage/v1/object/\(Self.bucket)/\(path)"
        let url = baseURL.appendingPathComponent(objectPath)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = imageData

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CapError.uploadFailed(body.isEmpty ? "status \((resp as? HTTPURLResponse)?.statusCode ?? -1)" : body)
        }
        return url.absoluteString
    }
}

// MARK: - Food search (manual-confirm + hidden-ingredient resolution)

/// Searches `foods` by canonical name for the manual-confirm picker and to
/// resolve confirmed hidden ingredients to a `food_id` (SPEC §4).
struct CapFoodSearchService: Sendable {
    let repository: Repository

    /// Case-insensitive substring match (`ilike.*term*`). Trimmed; empty → [].
    func search(_ term: String, limit: Int = 20) async throws -> [CapFoodSearchResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await repository.select(
            "foods",
            columns: "id,canonical_name",
            filters: ["canonical_name": "ilike.*\(trimmed)*"],
            order: "canonical_name",
            limit: limit
        )
    }

    /// Best single match for a name (used to resolve a confirmed hidden
    /// ingredient like "onion" → its food_id). Prefers an exact (case-folded)
    /// canonical-name hit, else the first substring match.
    func bestMatch(for name: String) async throws -> CapFoodSearchResult? {
        let results = try await search(name)
        let folded = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return results.first { $0.canonicalName.lowercased() == folded } ?? results.first
    }
}

// MARK: - Meal persistence (SPEC §5 — `meals` + `meal_items`)

/// Writes one confirmed meal and its items, RLS-scoped by the caller's token.
struct CapMealPersistence: Sendable {
    let repository: Repository
    let userId: String

    /// Persists the `meals` row (confirmed=true) and every `meal_items` row.
    /// - Returns: the new `meals.id`.
    @discardableResult
    func persist(_ draft: CapMealDraft) async throws -> String {
        var mealBody: [String: PGValue] = [
            "user_id": .string(userId),
            "mode": .string(draft.mode.rawValue),
            "captured_at": .date(draft.capturedAt),
            "confirmed": .bool(true)
        ]
        if let photoURL = draft.photoURL { mealBody["photo_url"] = .string(photoURL) }
        // jsonb-as-string (see file header caveat).
        if let visionJSON = CapJSON.string(from: draft.response.vision) {
            mealBody["vision_raw_json"] = .string(visionJSON)
        }
        let payload = CapHiddenIngredients.answersPayload(draft.hiddenAnswers)
        if let hiddenJSON = CapJSON.string(fromObject: payload) {
            mealBody["hidden_ingredient_answers"] = .string(hiddenJSON)
        }

        let rows: [MealRow] = try await repository.insert("meals", mealBody)
        guard let mealId = rows.first?.id else {
            throw SupabaseError.server(status: -1, message: "meals insert returned no row")
        }

        for item in draft.items {
            try await repository.insertVoid("meal_items", [
                "meal_id": .string(mealId),
                "food_id": .string(item.foodId),
                "portion_tier": .string(item.portion.rawValue),
                "source": .string(item.source.rawValue)
            ])
        }
        return mealId
    }
}
