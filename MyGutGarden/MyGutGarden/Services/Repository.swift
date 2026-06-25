//
//  Repository.swift
//  MyGutGarden — the typed data layer (Phase 1 scaffolding). PostgREST CRUD
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
        let (data, resp) = try await URLSession.shared.data(for: req)
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

    func upsert(_ table: String, _ body: [String: PGValue], onConflict: String) async throws {
        var req = makeRequest(table, method: "POST",
                              query: [URLQueryItem(name: "on_conflict", value: onConflict)],
                              prefer: "resolution=merge-duplicates,return=minimal")
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

    // MARK: Convenience — profile & exclusions

    func fetchProfile() async throws -> UserProfile? {
        let rows: [UserProfile] = try await select("users")
        return rows.first
    }

    func fetchExclusions() async throws -> [ExclusionRow] {
        try await select("exclusions")
    }

    // MARK: Convenience — reference reads (cacheable)

    func fetchPlants() async throws -> [PlantRow] { try await select("plants", order: "name") }
    func fetchGuilds() async throws -> [GuildRow] { try await select("guilds") }
    func fetchDistricts() async throws -> [DistrictRow] { try await select("districts", order: "order") }
}

// MARK: - Shared row types (used across modules + the coordinator)

/// Surfaced user fields. `est_daily_kcal` is deliberately NOT decoded here —
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
    let baselineMood: Int?
    let baselineEnergy: Int?
    let baselineClarity: Int?
    let goals: [String]
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
}

struct GuildStateRow: Decodable, Sendable {
    let guildId: String
    let nourishmentScore: Int
    let bloomState: String
    let lastFedAt: String?
    let daysFedThisWeek: Int
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
    let fodmapGroup: String
    let status: String
    let startedAt: String?
    let endedAt: String?
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
