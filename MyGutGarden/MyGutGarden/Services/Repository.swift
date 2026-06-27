//
//  Repository.swift
//  MyGutGarden, the typed data layer (Phase 1 scaffolding). PostgREST CRUD
//  over the per-user + reference tables, RLS-scoped by the caller's token.
//  This is the internal data contract every module calls; nobody hand-rolls
//  REST. Generic primitives + shared row types; modules add their own row
//  structs via the generic `select`/`insert` when a table is theirs alone.
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
    /// unavailable, in which case the original 401 propagates. Defaulted so
    /// existing call sites that build a Repository without it still compile.
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
        var (data, resp) = try await URLSession.shared.data(for: req)
        // Transparently recover from an expired access token (JWT expired): mint a
        // fresh token via the refresh grant and retry the same request once.
        if (resp as? HTTPURLResponse)?.statusCode == 401,
           let refresh = refreshAccessToken, let fresh = await refresh() {
            req.setValue("Bearer \(fresh)", forHTTPHeaderField: "Authorization")
            (data, resp) = try await URLSession.shared.data(for: req)
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

    /// `ignoreDuplicates: true` → leave the existing row untouched (e.g. the
    /// lifetime plant collection's first_logged_at); false → merge/update it.
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

    // MARK: Convenience, profile & exclusions

    func fetchProfile() async throws -> UserProfile? {
        let rows: [UserProfile] = try await select("users")
        return rows.first
    }

    func fetchExclusions() async throws -> [ExclusionRow] {
        try await select("exclusions")
    }

    // MARK: Convenience, reference reads (cacheable)

    func fetchPlants() async throws -> [PlantRow] { try await select("plants", order: "name") }
    func fetchGuilds() async throws -> [GuildRow] { try await select("guilds") }
    func fetchDistricts() async throws -> [DistrictRow] { try await select("districts", order: "order") }

    // MARK: Convenience, Phase 2
    func fetchResetInstructions() async throws -> [ResetInstructionRow] {
        try await select("reset_instructions", order: "sort_order")
    }
    func fetchSurviveReset() async throws -> SurviveResetRow? {
        let rows: [SurviveResetRow] = try await select("survive_reset")
        return rows.first
    }
    func fetchSurviveMealPlan(phase: String) async throws -> [SurviveMealPlanRow] {
        try await select("survive_meal_plan", filters: ["phase": "eq.\(phase)"], order: "day_index")
    }
}

// MARK: - Shared row types (used across modules + the coordinator)

/// Surfaced user fields. `est_daily_kcal` is deliberately NOT decoded here, 
/// it is internal-only and must never reach a view (SPEC §10 / Fence 5).
struct UserProfile: Decodable, Sendable {
    let id: String
    let currentMode: AppMode
    let heightCm: Double?
    let weightKg: Double?
    let age: Int?
    let sex: String?
    let activityLevel: String?
    let fiberGoalG: Int?
    let baselineMood: Int?            // CANONICAL high=better (UI flips regulated→erratic via 6 - ui)
    let baselineEnergy: Int?
    let baselineClarity: Int?
    let goals: [String]
    // Phase 2 (Batch B). `residue_ceiling_g` is INTENTIONALLY NOT decoded, it is
    // internal-only, exactly like est_daily_kcal (SPEC §10 / Fence 5).
    let plantConsumptionLevel: String?   // low | moderate | high | most_of_diet → fiber multiplier
    let baselineBowelConsistency: Int?   // 1=inconsistent .. 5=consistent (high=better)
    let otherAutoimmune: Bool
    let fiberGoalAdjustedWeekStart: String?  // last week the Thrive auto-increase fired (idempotency)
    let lightCheckinCategory: String?    // R3 Batch C: persisted single-category light check-in (nil = full)
}

struct ExclusionRow: Decodable, Sendable {
    let id: String
    let foodId: String?
    let category: String?
    let exclusionType: ExclusionType
}

struct MealRow: Decodable, Sendable {
    let id: String
    let mode: AppMode
    let photoUrl: String?
    let capturedAt: String
    let confirmed: Bool
    let userAnnotation: String?      // Batch C snapchat-style note (feeds the re-prompt)
    let photoExpiresAt: String?      // captured_at + 5d; photo_url nulled by the retention sweep after
}

struct GuildStateRow: Decodable, Sendable {
    let guildId: String
    let nourishmentScore: Int
    let bloomState: String
    let lastFedAt: String?
    let daysFedThisWeek: Int
    var hasEverBloomed: Bool = false   // set by the ingestion coordinator on crossedIntoBlooming
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

struct ThriveCheckinRow: Decodable, Sendable {
    let logDate: String
    let mood: Int?
    let energy: Int?
    let clarity: Int?
    // Phase 2 (Batch D/E). `var … = default` so the in-code constructor stays
    // source-compatible; PostgREST always returns the columns so decoding fills them.
    var checkinMode: String = "full"     // light | full
    var bowelConsistency: Int? = nil     // 1=inconsistent .. 5=consistent (high=better)
    var reintroFoodId: String? = nil     // a reintro food present in this day's test
    var reintroFeltFine: Bool? = nil
}

struct SymptomLogRow: Decodable, Sendable {
    let id: String
    let loggedAt: String
    let bss: Int?
    let gasOdor: String?
    let confounders: [String]
}

struct ReintroChallengeRow: Decodable, Sendable {
    let id: String
    let fodmapGroup: String?         // nil for food_suspect challenges (branch on challengeKind)
    let status: String
    let startedAt: String?
    let endedAt: String?
    // Phase 2 (Batch E). food_suspect challenges are EVENT-DRIVEN: the bar advances
    // on felt-fine meals, never on elapsed time (rule #7). FODMAP challenges keep the
    // legacy time-based path (GameConfig.reintroChallengeDays).
    let challengeKind: String        // fodmap | food_suspect
    let foodId: String?
    let suspectId: String?
    let mealsFeelingFineCount: Int
    let consecutiveUnwellCount: Int  // UNSURFACED gate for the Avoid offer only
    let progressPct: Int
}

struct PatternAssessmentRow: Decodable, Sendable {
    let id: String
    let computedAt: String
    let pattern: String
    let confidence: String
    let evidenceSummary: String?
}

struct SymptomFreeStreakRow: Decodable, Sendable {
    let currentStreak: Int
    let longestStreak: Int
    let lastQualifyingDate: String?
}

// Reference rows
struct PlantRow: Decodable, Sendable {
    let id: String
    let name: String
    let rarityTier: RarityTier
}

struct GuildRow: Decodable, Sendable {
    let id: String
    let districtId: String
    let internalName: String
    let displayName: String
    let functionCopy: String?
    let confidenceTag: String
    let feedsCopy: String?
    let claimRisk: Bool
    let substantiation: String?
}

struct DistrictRow: Decodable, Sendable {
    let id: String
    let order: Int
    let name: String
    let unlockRuleKey: String
}

// MARK: - Phase 2 row types (multi-entry check-in, food-status, reset)

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
    let moodScore: Int                 // CANONICAL high=better (5=regulated)
    let context: String; let occurredAt: String?; let linkedMealId: String?
}

struct CheckinNoteRow: Decodable, Sendable {
    let id: String; let userId: String; let logDate: String
    let content: String; let context: String; let linkedMealId: String?; let createdAt: String
}

/// A food the user is keeping an eye on. NO severity/score/confidence field, by
/// design, there is never an accumulating "bad-guy" meter (rule #4). `avoid` is
/// NOT an exclusion_type and is never merged into `exclusions` (rule #1).
struct FoodSuspectRow: Decodable, Sendable {
    let id: String; let userId: String; let foodId: String
    let addedBy: String                // user | system (system = a dismissible suggestion)
    let status: String                 // suspect | reintroducing | avoided | cleared
    let userVerdict: String?           // nil = pending; the user authors every negative transition
    let avoid: Bool
    let createdAt: String; let updatedAt: String
}

struct ReintroMealCheckRow: Decodable, Sendable {
    let id: String; let userId: String; let challengeId: String; let mealId: String
    let feltFine: Bool?                 // nil = auto-attached, awaiting the user
    let portionTier: String; let loggedAt: String
}

struct WeeklyColorAmountRow: Decodable, Sendable {
    let weekStart: String; let colorId: String; let maxTier: String
}

/// The low-residue reset. Progress is RELIEF only (`symptomFreeDays`); there is no
/// days-restricted column by design (rule #7).
struct SurviveResetRow: Decodable, Sendable {
    let id: String; let userId: String; let startedAt: String
    let pausedAt: String?; let endedAt: String?
    let phase: String                  // reset | reintroduction_phase | graduated
    let symptomFreeDays: Int; let noImprovementAlerts: Int
    let clinicianPromptedAt: String?; let graduatedAt: String?
}

/// Curated reset guidance (Fence 6, RD-REVIEW-REQUIRED). Not runtime-generated.
struct ResetInstructionRow: Decodable, Sendable {
    let id: String; let phase: String; let sortOrder: Int
    let instructionCopy: String; let foodSuggestions: [String]; let claimRisk: Bool
}

/// R3 Batch C: an Energy or Clarity entry. High=better, stored as-is (no inversion).
struct MetricEntryRow: Decodable, Sendable {
    let id: String; let userId: String; let logDate: String
    let metricType: String             // energy | clarity
    let score: Int                     // 1=low .. 5=high
    let context: String; let occurredAt: String?; let linkedMealId: String?
}

/// R3 Batch E: a curated Survive meal-plan slot (Fence 6, RD-REVIEW-REQUIRED).
struct SurviveMealPlanRow: Decodable, Sendable {
    let id: String; let phase: String; let dayIndex: Int
    let mealSlot: String               // breakfast | lunch | dinner
    let optionIndex: Int
    let title: String; let description: String
    let exampleFoods: [String]; let fiberLevel: String
}
