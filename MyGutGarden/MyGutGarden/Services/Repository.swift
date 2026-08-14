//
//  Repository.swift
//  MyGutGarden — the typed data layer. PostgREST CRUD over the per-user +
//  reference tables, RLS-scoped by the caller's token. Generic primitives +
//  shared row types; modules add their own row structs via the generic
//  `select`/`insert` when a table is theirs alone.
//

import Foundation

// MARK: - JSON value for write bodies

enum PGValue: Sendable {
    case string(String), int(Int), double(Double), bool(Bool)
    case stringArray([String]), date(Date), null

    var json: Any {
        switch self {
        case let .string(s): s
        case let .int(i): i
        case let .double(d): d
        case let .bool(b): b
        case let .stringArray(a): a
        case let .date(d): ISO8601DateFormatter().string(from: d)
        case .null: NSNull()
        }
    }
}

// MARK: - Repository

struct Repository: Sendable {
    let baseURL: URL
    let anonKey: String
    let accessToken: String
    /// Called once on a 401 (expired JWT) to mint a fresh access token via the
    /// refresh-token grant. Returns the new token, or nil if refresh is
    /// unavailable, in which case the original 401 propagates.
    var refreshAccessToken: (@Sendable () async -> String?)? = nil

    private var restURL: URL { baseURL.appendingPathComponent("rest/v1") }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func makeRequest(_ path: String, method: String, query: [URLQueryItem] = [], prefer: String? = nil) -> URLRequest {
        var comps = URLComponents(url: restURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        return req
    }

    private func run(_ req: URLRequest) async throws -> Data {
        var req = req
        var (data, resp) = try await SupabaseHTTP.session.data(for: req)
        // Transparently recover from an expired access token: mint a fresh token
        // via the refresh grant and retry the same request once.
        if (resp as? HTTPURLResponse)?.statusCode == 401,
           let refresh = refreshAccessToken, let fresh = await refresh() {
            req.setValue("Bearer \(fresh)", forHTTPHeaderField: "Authorization")
            (data, resp) = try await SupabaseHTTP.session.data(for: req)
        }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.server(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, message: body)
        }
        return data
    }

    // MARK: Generic primitives

    /// `filters` are PostgREST predicates, e.g. ["user_id": "eq.\(uid)"].
    func select<T: Decodable>(_ table: String, columns: String = "*",
                              filters: [String: String] = [:], order: String? = nil,
                              limit: Int? = nil) async throws -> [T] {
        var q = [URLQueryItem(name: "select", value: columns)]
        q += filters.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let order { q.append(URLQueryItem(name: "order", value: order)) }
        if let limit { q.append(URLQueryItem(name: "limit", value: String(limit))) }
        let data = try await run(makeRequest(table, method: "GET", query: q))
        return try Self.decoder.decode([T].self, from: data)
    }

    @discardableResult
    func insert<T: Decodable>(_ table: String, _ body: [String: PGValue]) async throws -> [T] {
        var req = makeRequest(table, method: "POST", prefer: "return=representation")
        req.httpBody = try JSONSerialization.data(withJSONObject: body.mapValues(\.json))
        return try Self.decoder.decode([T].self, from: try await run(req))
    }

    func insertVoid(_ table: String, _ body: [String: PGValue]) async throws {
        var req = makeRequest(table, method: "POST", prefer: "return=minimal")
        req.httpBody = try JSONSerialization.data(withJSONObject: body.mapValues(\.json))
        _ = try await run(req)
    }

    /// `ignoreDuplicates: true` → leave the existing row untouched; false → merge.
    func upsert(_ table: String, _ body: [String: PGValue], onConflict: String,
                ignoreDuplicates: Bool = false) async throws {
        let resolution = ignoreDuplicates ? "ignore-duplicates" : "merge-duplicates"
        var req = makeRequest(table, method: "POST",
                              query: [URLQueryItem(name: "on_conflict", value: onConflict)],
                              prefer: "resolution=\(resolution),return=minimal")
        req.httpBody = try JSONSerialization.data(withJSONObject: body.mapValues(\.json))
        _ = try await run(req)
    }

    func update(_ table: String, set body: [String: PGValue], filters: [String: String]) async throws {
        var req = makeRequest(table, method: "PATCH",
                              query: filters.map { URLQueryItem(name: $0.key, value: $0.value) },
                              prefer: "return=minimal")
        req.httpBody = try JSONSerialization.data(withJSONObject: body.mapValues(\.json))
        _ = try await run(req)
    }

    func delete(_ table: String, filters: [String: String]) async throws {
        _ = try await run(makeRequest(table, method: "DELETE",
                                      query: filters.map { URLQueryItem(name: $0.key, value: $0.value) },
                                      prefer: "return=minimal"))
    }

    // MARK: Convenience — profile & food flags

    func fetchProfile() async throws -> UserProfile? {
        // Explicit column list: `est_daily_kcal` is SELECT-revoked at the DB
        // (Fence 5 — the internal calorie estimate must not be readable even
        // over raw PostgREST), and a `*` select would fail on the revoked
        // column. Keep in sync with UserProfile's decoded fields.
        let rows: [UserProfile] = try await select(
            "users",
            columns: "id,height_cm,weight_kg,age,sex,activity_level,fiber_goal_g,"
                + "fiber_goal_state,fiber_goal_unlocked_at,baseline_mood,baseline_energy,"
                + "baseline_clarity,goals,plant_consumption_level,fiber_goal_adjusted_week_start,"
                + "onboarded_at,gas_comfort,gardener_name,intro_seen_at")
        return rows.first
    }

    /// The three-tier food-flag list (SPEC §9). Replaces the old exclusions fetch.
    func fetchFoodFlags() async throws -> [FoodFlagRow] {
        try await select("food_flags")
    }

    // MARK: Convenience — reference reads (cacheable)

    func fetchPlants() async throws -> [PlantRow] { try await select("plants", order: "name") }
    func fetchGuilds() async throws -> [GuildRow] { try await select("guilds") }
    func fetchWorlds() async throws -> [WorldRow] { try await select("worlds", order: "order") }
    func fetchDistricts() async throws -> [DistrictRow] { try await select("districts", order: "order") }
}

// MARK: - Shared row types (used across modules + the coordinator)

/// Surfaced user fields. `est_daily_kcal` and `fiber_target_g` are deliberately
/// NOT decoded here — they are internal-only and must never reach a view
/// (SPEC §10 / Fence 5). The only surfaced derived number is `fiberGoalG`, and
/// that stays nil until the week-one baseline quest unlocks it (SPEC §10).
struct UserProfile: Codable, Sendable {
    let id: String
    let heightCm: Double?
    let weightKg: Double?
    let age: Int?
    let sex: String?
    let activityLevel: String?
    let fiberGoalG: Int?                  // surfaced; nil until unlocked
    let fiberGoalState: String            // baseline_pending | unlocked
    let fiberGoalUnlockedAt: String?
    let baselineMood: Int?               // CANONICAL high=better
    let baselineEnergy: Int?
    let baselineClarity: Int?
    let goals: [String]
    let plantConsumptionLevel: String?   // low | moderate | high | most_of_diet → fiber multiplier
    let fiberGoalAdjustedWeekStart: String?  // idempotency marker for guardian titration offers
    let onboardedAt: String?             // clean isOnboarded marker (SPEC §6)
    /// SPEC §17: the gas-for-growth preference (gentle|balanced|bold). Optional-
    /// decoded for pre-migration safety; nil reads as balanced.
    var gasComfort: String? = nil
    /// The user-chosen gut-gardener name (owner, 2026-07-09). Optional-decoded;
    /// nil/empty reads as "Sprout" via `gardenerDisplayName`.
    var gardenerName: String? = nil
    /// When the 3-frame intro story was seen (nil = not yet). Gates the story
    /// between onboarding and the setup tour.
    var introSeenAt: String? = nil

    /// Never-empty gardener name for UI (nudges, map, tour, story).
    var gardenerDisplayName: String { (gardenerName?.isEmpty == false) ? gardenerName! : "Sprout" }
}

/// A food restriction at one of three tiers (SPEC §9). Replaces `exclusions` +
/// `food_suspects`. ⚠️ There is NO severity/score/rank field, by design (rule #7).
struct FoodFlagRow: Decodable, Sendable {
    let id: String
    let foodId: String?
    let category: String?
    let flagTier: String                 // watching | sensitivity | allergy
    let source: String                   // user | engine
    let userConfirmed: Bool
    let note: String?
}

struct MealRow: Decodable, Sendable {
    let id: String
    let photoUrl: String?                // permanent; nil only if the user deletes it (SPEC §4/§15)
    let capturedAt: String
    let confirmed: Bool
    let userAnnotation: String?          // snapchat-style note (feeds the re-prompt)
    // Optional extras (selected only where needed — jsonb stored as string
    // scalars, see CapServices header). Drive the key-question ⚠︎ on Recent Meals.
    var visionRawJson: String? = nil
    var hiddenIngredientAnswers: String? = nil
}

struct GuildStateRow: Decodable, Sendable {
    let guildId: String
    let nourishmentScore: Int
    let bloomState: String
    let lastFedAt: String?
    let daysFedThisWeek: Int
    var hasEverBloomed: Bool = false      // set by the ingestion coordinator on crossedIntoBlooming
}

struct UserPlantCollectionRow: Decodable, Sendable {
    let plantId: String
    let firstLoggedAt: String
}

struct WeeklySummaryRow: Decodable, Sendable {
    let weekStart: String
    let uniquePlantCount: Int
    let hit30: Bool
    let fiberDaysMet: Int
}

struct UserDistrictRow: Decodable, Sendable {
    let districtId: String
    let unlockedAt: String?
}

struct UserWorldRow: Decodable, Sendable {
    let worldId: String
    let unlockedAt: String?
}

struct WeeklyColorAmountRow: Decodable, Sendable {
    let weekStart: String; let colorId: String; let maxTier: String
}

// MARK: - Check-in rows
//
// The typed per-type tables + `thrive_checkins` are still live in the spine; the
// unification into check_ins/check_in_entries is Phase 1E (done before the drop
// migration applies). New unified rows are defined here for that cutover.

struct ThriveCheckinRow: Decodable, Sendable {
    let logDate: String
    let mood: Int?
    let energy: Int?
    let clarity: Int?
    var checkinMode: String = "full"     // light | full
    var bowelConsistency: Int? = nil
}

struct StoolEntryRow: Decodable, Sendable {
    let id: String; let userId: String; let logDate: String
    let bss: Int?; let occurredAt: String?; let linkedMealId: String?; let loggedAt: String
}

struct SymptomEntryRow: Decodable, Sendable {
    let id: String; let userId: String; let logDate: String
    let symptomType: String; let severity: Int; let gasOdor: String?
    let occurredAt: String?; let linkedMealId: String?
}

struct MoodEntryRow: Decodable, Sendable {
    let id: String; let userId: String; let logDate: String
    let moodScore: Int                   // CANONICAL high=better (5=best)
    let context: String; let occurredAt: String?; let linkedMealId: String?
}

struct CheckinNoteRow: Decodable, Sendable {
    let id: String; let userId: String; let logDate: String
    let content: String; let context: String; let linkedMealId: String?; let createdAt: String
}

/// An Energy or Clarity entry. High=better, stored as-is (no inversion).
struct MetricEntryRow: Decodable, Sendable {
    let id: String; let userId: String; let logDate: String
    let metricType: String               // energy | clarity
    let score: Int
    let context: String; let occurredAt: String?; let linkedMealId: String?
}

/// The unified check-in model (SPEC §5, §12) — Phase 1E cuts every check-in
/// surface over to these two rows.
struct CheckInPrefsRow: Decodable, Sendable {
    let enabledSections: [String]
    let dailyPopupEnabled: Bool
}

struct CheckInRow: Decodable, Sendable {
    let id: String; let logDate: String; let source: String; let createdAt: String
}

struct CheckInEntryRow: Decodable, Sendable {
    let id: String; let checkInId: String; let sectionKey: String
    let valueInt: Int?; let valueText: String?; let occurredAt: String?; let linkedMealId: String?
}

// MARK: - Reference rows

struct PlantRow: Decodable, Sendable {
    let id: String
    let name: String
    let rarityTier: RarityTier
    var description: String? = nil        // field-guide blurb (owner content pass)
}

struct GuildRow: Decodable, Sendable {
    let id: String
    let districtId: String
    let internalName: String
    let displayName: String
    let functionCopy: String?
    let confidenceTag: String
    let feedsCopy: String?
    let introCopy: String?
    let claimRisk: Bool
    let substantiation: String?
}

struct DistrictRow: Decodable, Sendable {
    let id: String
    let order: Int
    let name: String
    let unlockRuleKey: String
    let worldId: String?                 // the new parent tier (SPEC §8)
}

struct WorldRow: Decodable, Sendable {
    let id: String
    let order: Int
    let name: String
    let unlockRuleKey: String
    let introCopy: String?
}

/// Curated "try this" recipe (SPEC §14). [seed]
struct RecipeRow: Decodable, Sendable, Identifiable {
    let id: String; let title: String; let description: String?
    let featuredFoodIds: [String]; let featuredPlantIds: [String]; let colorIds: [String]
    let fiberHighlights: String?; let steps: [String]; let prepMinutes: Int?
    let source: String?; let claimRisk: Bool
    /// A base/side that pairs with "add your protein of choice" (owner request).
    /// Optional-decoded so a pre-migration backend can't break the whole select.
    var suggestProtein: Bool? = nil
    /// Ingredient list WITH serving sizes ("1 cup rolled oats"). Optional-decoded
    /// for pre-migration safety (owner content pass, round 2).
    var ingredients: [String]? = nil
}

/// Curated coach-mark step (SPEC §7). [seed]
struct TutorialStepRow: Decodable, Sendable {
    let id: String; let sectionKey: String; let order: Int
    let title: String?; let body: String; let targetHint: String?; let claimRisk: Bool
}
