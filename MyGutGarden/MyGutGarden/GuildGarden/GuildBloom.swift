//
//  GuildBloom.swift
//  MyGutGarden — Module D's bloom state machine (SPEC §13). PURE, deterministic
//  math: feeding adds `portion × relevance`, the score DECAYS ~12%/day applied
//  ON READ from `last_fed_at` (a guild fades when it isn't fed), and the score
//  maps to Dormant/Sprouting/Growing/Blooming via GameConfig thresholds.
//
//  ⚠️ Module D is the SOLE owner of `guild_state` logic. The coordinator persists
//  the writes (decay-then-add) using exactly these functions, so the on-read view
//  and the on-write store never disagree. Everything here is unit-tested — it is
//  the most regression-prone code in the module (CLAUDE.md §5).
//

import Foundation

// MARK: - Bloom state

/// The four bloom states (SPEC §13). Thresholds come from `GameConfig`; the
/// boundaries are read off the score, so a guild only changes state when its
/// (decayed) nourishment actually crosses a threshold.
enum GuildBloomState: String, Sendable, CaseIterable, Comparable {
    case dormant, sprouting, growing, blooming

    private var rank: Int {
        switch self {
        case .dormant: 0
        case .sprouting: 1
        case .growing: 2
        case .blooming: 3
        }
    }
    static func < (lhs: GuildBloomState, rhs: GuildBloomState) -> Bool { lhs.rank < rhs.rank }

    /// Map a 0–100 nourishment score to a bloom state.
    /// Dormant 0–20 · Sprouting 21–45 · Growing 46–70 · Blooming 71–100.
    static func state(for score: Double, config: GameConfig = .shared) -> GuildBloomState {
        if score <= Double(config.bloomDormantMax) { return .dormant }
        if score <= Double(config.bloomSproutingMax) { return .sprouting }
        if score <= Double(config.bloomGrowingMax) { return .growing }
        return .blooming
    }

    /// Gain-framed label for the surface (never loss/shame — DESIGN.md §6).
    var displayLabel: String {
        switch self {
        case .dormant: "Resting"
        case .sprouting: "Sprouting"
        case .growing: "Growing"
        case .blooming: "Blooming"
        }
    }
}

// MARK: - The outcome of a single feeding event

/// Everything the coordinator needs to persist one feeding + drive the UI.
struct GuildFeedingOutcome: Sendable, Equatable {
    /// New `nourishment_score` (0–100, clamped) to store.
    let score: Double
    /// New `bloom_state` to store.
    let state: GuildBloomState
    /// New `days_fed_this_week` to store.
    let daysFedThisWeek: Int
    /// 3+ distinct days fed this week → the "well-fed" state (SPEC §13).
    let isWellFed: Bool
    /// This feeding pushed the guild from < Blooming into Blooming → fire the
    /// marquee bloom animation + `celebrate(.guildBloom)` (signature moment).
    let crossedIntoBlooming: Bool
    /// This feeding is the one that earned the consistent-feeding bonus.
    let earnedConsistencyBonus: Bool
}

// MARK: - The pure math

enum GuildBloom {

    /// Apply ~12%/day exponential decay to a stored score, as of `now`, from the
    /// last time the guild was fed. This is the ON-READ fade: call it whenever a
    /// stored score is surfaced, and again (with the same clock) before adding a
    /// new feeding, so a single clove fades and only sustained intake blooms.
    static func decayedScore(storedScore: Double,
                             lastFedAt: Date?,
                             asOf now: Date,
                             config: GameConfig = .shared) -> Double {
        guard let lastFedAt else { return storedScore } // never fed → nothing to decay
        let days = now.timeIntervalSince(lastFedAt) / 86_400
        guard days > 0 else { return storedScore }       // clock skew / same instant → no change
        let retained = pow(1 - config.guildDecayPerDay, days)
        return clampScore(storedScore * retained)
    }

    /// The bloom state a stored score *currently* presents at, after on-read decay.
    static func currentState(storedScore: Double,
                             lastFedAt: Date?,
                             asOf now: Date,
                             config: GameConfig = .shared) -> GuildBloomState {
        GuildBloomState.state(for: decayedScore(storedScore: storedScore,
                                                lastFedAt: lastFedAt, asOf: now, config: config),
                              config: config)
    }

    /// The full decay-then-add for ONE feeding event. Pure: give it the stored
    /// row + the feeding's points + the meal's timestamp; get back the row to
    /// store and the UI signals. The coordinator owns the actual `guild_state`
    /// write — this function decides what that write contains.
    ///
    /// - `points`: `GameConfig.feedingPoints(portion:relevance:)`, already summed
    ///   per guild for the meal (see `GuildIngestor.guildFeedingPoints`).
    static func applyFeeding(storedScore: Double,
                             lastFedAt: Date?,
                             daysFedThisWeek: Int,
                             points: Int,
                             at feedingDate: Date,
                             calendar: Calendar = .current,
                             config: GameConfig = .shared) -> GuildFeedingOutcome {
        // 1. Decay first (on-read fade applied before crediting new intake).
        let decayed = decayedScore(storedScore: storedScore, lastFedAt: lastFedAt,
                                   asOf: feedingDate, config: config)
        let stateBefore = GuildBloomState.state(for: decayed, config: config)

        // 2. Distinct-day bookkeeping for the consistent-feeding bonus (§13).
        //    Resets at the Monday week boundary; only a NEW calendar day in the
        //    same week increments the count (chronological feeding assumed).
        let incrementedToday: Bool
        let newDays: Int
        if let last = lastFedAt, GuildWeek.sameWeek(feedingDate, last, calendar: calendar) {
            if GuildWeek.sameDay(feedingDate, last, calendar: calendar) {
                incrementedToday = false
                newDays = max(daysFedThisWeek, 1)
            } else {
                incrementedToday = true
                newDays = daysFedThisWeek + 1
            }
        } else {
            incrementedToday = true          // first feed ever, or first of a new week
            newDays = 1
        }

        // 3. Add the feeding, plus the consistency bonus on the day it's crossed.
        let earnedBonus = incrementedToday && newDays == config.consistentFeedingDaysPerWeek
        var score = decayed + Double(points)
        if earnedBonus { score += Double(config.consistentFeedingBonus) }
        score = clampScore(score)

        let stateAfter = GuildBloomState.state(for: score, config: config)
        return GuildFeedingOutcome(
            score: score,
            state: stateAfter,
            daysFedThisWeek: newDays,
            isWellFed: newDays >= config.consistentFeedingDaysPerWeek,
            crossedIntoBlooming: stateBefore != .blooming && stateAfter == .blooming,
            earnedConsistencyBonus: earnedBonus
        )
    }

    /// Clamp to the 0–100 nourishment range.
    static func clampScore(_ value: Double) -> Double { min(100, max(0, value)) }
}

// MARK: - Week math (Monday-start; Sunday 23:59 reset — SPEC §13)

/// Distinct-day + week-boundary helpers for the consistent-feeding bonus and the
/// weekly reset. Monday is the week start (`weekly_summaries.week_start (Mon)`),
/// so the variety/feeding week is Mon–Sun and resets Sunday 23:59 local.
enum GuildWeek {
    /// A Monday-first calendar derived from the given one (default `.current`).
    static func mondayCalendar(_ base: Calendar = .current) -> Calendar {
        var cal = base
        cal.firstWeekday = 2 // Monday
        return cal
    }

    /// Start-of-week (Monday 00:00) for a date.
    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        let cal = mondayCalendar(calendar)
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    static func sameWeek(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        weekStart(for: a, calendar: calendar) == weekStart(for: b, calendar: calendar)
    }

    static func sameDay(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }
}
