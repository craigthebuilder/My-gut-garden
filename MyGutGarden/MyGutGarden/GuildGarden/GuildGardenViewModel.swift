//
//  GuildGardenViewModel.swift
//  MyGutGarden, Module D's read model for the guild garden surface.
//
//  Loads the four districts + their guilds + per-user `guild_state`, applies the
//  ~12%/day decay ON READ (GuildBloom) so a faded guild shows faded, and exposes
//  the fog-of-war unlock state the map renders. Read-only: all `guild_state` and
//  `user_districts` WRITES belong to the coordinator (Module D owns the logic,
//  the coordinator owns the persistence, Seams.swift).
//

import Foundation
import Observation

// MARK: - Display types

/// On-read bloom snapshot for one guild (decay already applied).
struct GuildBloomDisplay: Sendable, Equatable {
    let score: Double            // 0–100, decayed as of "now"
    let state: GuildBloomState
    let daysFedThisWeek: Int

    var isWellFed: Bool { daysFedThisWeek >= GameConfig.shared.consistentFeedingDaysPerWeek }
    var fraction: Double { min(1, max(0, score / 100)) }

    static let empty = GuildBloomDisplay(score: 0, state: .dormant, daysFedThisWeek: 0)
}

/// One collectible guild card's data (a `GuildRow` joined to its bloom state).
struct GuildDisplay: Identifiable, Sendable {
    let number: Int              // collectible "Pokédex" number (see assembler)
    let internalName: String
    let displayName: String
    let districtOrder: Int
    let functionCopy: String?
    let feedsCopy: String?
    let confidenceTag: String
    let claimRisk: Bool          // RD-review ledger only (FENCES.md); no visible tag (owner, 2026-07-02)
    let substantiation: String?
    let bloom: GuildBloomDisplay

    var id: String { internalName }
    /// Eyebrow on the field-guide card — the district it belongs to (the world is
    /// shown in the garden section header now, SPEC §8).
    func eyebrow(districtName: String) -> String { districtName }
}

/// One district region on the map.
struct GuildDistrictDisplay: Identifiable, Sendable {
    let order: Int
    let name: String
    let isUnlocked: Bool
    let guilds: [GuildDisplay]

    var id: Int { order }
    var bloomingCount: Int { guilds.filter { $0.bloom.state == .blooming }.count }
    var wellFedCount: Int { guilds.filter { $0.bloom.isWellFed }.count }
}

// MARK: - Pure assembler (testable; no I/O)

enum GuildGardenAssembler {

    /// Alphabetical sort key ignoring a leading "The ", this is what makes the
    /// collectible numbering match the reference cards (Anti-inflammatory
    /// Arsenal = 1, Base Layer = 3, Estrogen Regulators = 9).
    static func sortKey(_ displayName: String) -> String {
        var s = displayName
        if s.lowercased().hasPrefix("the ") { s = String(s.dropFirst(4)) }
        return s.lowercased()
    }

    /// Number the whole roster by (district order, then alphabetical-without-"The"),
    /// 1…N, a stable collectible index across all districts.
    static func numbering(districts: [DistrictRow], guilds: [GuildRow]) -> [String: Int] {
        let orderByDistrict = Dictionary(districts.map { ($0.id, $0.order) }) { a, _ in a }
        let sorted = guilds.sorted { a, b in
            let oa = orderByDistrict[a.districtId] ?? .max
            let ob = orderByDistrict[b.districtId] ?? .max
            if oa != ob { return oa < ob }
            return sortKey(a.displayName) < sortKey(b.displayName)
        }
        var map: [String: Int] = [:]
        for (i, g) in sorted.enumerated() { map[g.id] = i + 1 }
        return map
    }

    static func build(districts: [DistrictRow],
                      guilds: [GuildRow],
                      states: [GuildStateRow],
                      unlockedOrders: Set<Int>,
                      now: Date,
                      calendar: Calendar = .current) -> [GuildDistrictDisplay] {
        let orderByDistrict = Dictionary(districts.map { ($0.id, $0.order) }) { a, _ in a }
        let numberByGuild = numbering(districts: districts, guilds: guilds)
        let stateByGuild = Dictionary(states.map { ($0.guildId, $0) }) { a, _ in a }

        return districts.sorted { $0.order < $1.order }.map { district in
            let rows = guilds
                .filter { $0.districtId == district.id }
                .sorted { sortKey($0.displayName) < sortKey($1.displayName) }
            let displays = rows.map { row in
                GuildDisplay(
                    number: numberByGuild[row.id] ?? 0,
                    internalName: row.internalName,
                    displayName: row.displayName,
                    districtOrder: orderByDistrict[row.districtId] ?? district.order,
                    functionCopy: row.functionCopy,
                    feedsCopy: row.feedsCopy,
                    confidenceTag: row.confidenceTag,
                    claimRisk: row.claimRisk,
                    substantiation: row.substantiation,
                    bloom: bloomDisplay(for: stateByGuild[row.id], now: now, calendar: calendar)
                )
            }
            return GuildDistrictDisplay(order: district.order, name: district.name,
                                        isUnlocked: unlockedOrders.contains(district.order),
                                        guilds: displays)
        }
    }


    /// Apply on-read decay to a stored guild_state row (or `.empty` if unfed).
    static func bloomDisplay(for state: GuildStateRow?, now: Date,
                             calendar: Calendar = .current) -> GuildBloomDisplay {
        guard let state else { return .empty }
        let lastFed = state.lastFedAt.flatMap(parseTimestamp)
        let decayed = GuildBloom.decayedScore(storedScore: Double(state.nourishmentScore),
                                              lastFedAt: lastFed, asOf: now)
        return GuildBloomDisplay(score: decayed,
                                 state: GuildBloomState.state(for: decayed),
                                 daysFedThisWeek: state.daysFedThisWeek)
    }

    /// Tolerant ISO-8601 parse for Postgres `timestamptz` (with/without fractions).
    static func parseTimestamp(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    /// Snapshots for the §13 unlock gates. NOTE: `guild_state` stores only the
    /// *current* bloom state, so `hasEverBloomed` is approximated by "blooming
    /// right now". The authoritative unlock set lives in `user_districts` /
    /// `ProgressionState` (the coordinator tracks ever-bloomed properly), this
    /// fallback is only used when that read surface is empty.
    static func snapshots(from districts: [GuildDistrictDisplay]) -> [GuildBloomSnapshot] {
        districts.flatMap { district in
            district.guilds.map {
                GuildBloomSnapshot(districtOrder: district.order,
                                   isBlooming: $0.bloom.state == .blooming,
                                   hasEverBloomed: $0.bloom.state == .blooming)
            }
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class GuildGardenViewModel {
    private(set) var districts: [GuildDistrictDisplay] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let repository: Repository?
    private let ingestor = GuildIngestor()
    private let clock: () -> Date

    /// Progression read surface (coordinator writes; D reads, Seams.swift).
    var progression: ProgressionState

    init(repository: Repository?,
         progression: ProgressionState,
         clock: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.progression = progression
        self.clock = clock
    }

    var isTier2Unlocked: Bool { progression.isTier2Unlocked }
    var unlockedDistrictCount: Int { districts.filter(\.isUnlocked).count }
    var totalDistrictCount: Int { max(districts.count, 4) }

    func load() async {
        guard let repository else { return } // offline/preview → seeded via `preview`
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let districtsRows = repository.fetchDistricts()
            async let guildRows = repository.fetchGuilds()
            async let stateRows: [GuildStateRow] = repository.select("guild_state")
            async let userDistrictRows: [UserDistrictRow] = repository.select("user_districts")
            let (ds, gs, ss, uds) = try await (districtsRows, guildRows, stateRows, userDistrictRows)
            rebuild(districts: ds, guilds: gs, states: ss, userDistricts: uds)
        } catch {
            errorMessage = "Couldn't load your garden. Pull to try again."
        }
    }

    /// Pure rebuild from fetched rows (split out so it's exercisable in tests).
    func rebuild(districts ds: [DistrictRow], guilds gs: [GuildRow],
                 states ss: [GuildStateRow], userDistricts uds: [UserDistrictRow]) {
        let unlocked = resolveUnlockedOrders(districts: ds, guilds: gs, states: ss, userDistricts: uds)
        districts = GuildGardenAssembler.build(districts: ds, guilds: gs, states: ss,
                                               unlockedOrders: unlocked, now: clock())
    }

    /// Authoritative unlock set comes from `ProgressionState` / `user_districts`.
    /// When neither is populated yet (fresh Tier-2 user), fall back to computing
    /// the gates from current snapshots. Nothing is unlocked until Tier 2 itself.
    private func resolveUnlockedOrders(districts ds: [DistrictRow], guilds gs: [GuildRow],
                                       states ss: [GuildStateRow],
                                       userDistricts uds: [UserDistrictRow]) -> Set<Int> {
        guard progression.isTier2Unlocked else { return [] }

        if !progression.unlockedDistrictOrders.isEmpty {
            return progression.unlockedDistrictOrders
        }

        // user_districts (only the unlocked ones) → orders
        let orderByDistrict = Dictionary(ds.map { ($0.id, $0.order) }) { a, _ in a }
        let fromUserDistricts = Set(uds.compactMap { row -> Int? in
            row.unlockedAt == nil ? nil : orderByDistrict[row.districtId]
        })
        if !fromUserDistricts.isEmpty { return fromUserDistricts }

        // Last resort: compute from snapshots (D1 always opens with Tier 2).
        let preview = GuildGardenAssembler.build(districts: ds, guilds: gs, states: ss,
                                                 unlockedOrders: [], now: clock())
        let snaps = GuildGardenAssembler.snapshots(from: preview)
        return ingestor.unlockedDistrictOrders(snapshots: snaps,
                                               cumulativeTier2Days: progression.cumulativeTier2Days)
    }

    /// Fixture-backed model for previews + the showcase without a live backend.
    static func preview(progression: ProgressionState = GuildSampleData.previewProgression,
                        now: Date = GuildSampleData.previewNow) -> GuildGardenViewModel {
        let vm = GuildGardenViewModel(repository: nil, progression: progression, clock: { now })
        vm.districts = GuildGardenAssembler.build(
            districts: GuildSampleData.districts,
            guilds: GuildSampleData.guilds,
            states: GuildSampleData.states,
            unlockedOrders: progression.isTier2Unlocked ? progression.unlockedDistrictOrders : [],
            now: now)
        return vm
    }
}
