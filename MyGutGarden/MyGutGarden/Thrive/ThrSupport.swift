//
//  ThrSupport.swift
//  MyGutGarden, Module C (Thrive surface) shared support.
//
//  Small, dependency-free helpers used across the Thrive surfaces: week/day
//  date math (Sunday-reset weekly variety, §13), rarity ordering (celebration
//  intensity, §13), and the PostgREST row types this module decodes from tables
//  it reads (curiosity_facts, colors, phytochemicals, meal_items). Row types
//  that already live in Services/Repository.swift are reused, never redefined.
//

import Foundation

// MARK: - Rarity ordering (celebration intensity scales with rarity, §13)

extension RarityTier {
    /// 0…3, common → legendary. Used to pick the *rarest* new find to celebrate.
    var rank: Int {
        switch self {
        case .common: 0
        case .uncommon: 1
        case .rare: 2
        case .legendary: 3
        }
    }
    /// A find worth a rare-find celebration moment (SPEC §11a, §13).
    var triggersCelebration: Bool { self == .rare || self == .legendary }
}

// MARK: - Week / day math (weekly variety resets Sunday 23:59 local, §8/§13)

enum ThrDates {
    /// The Monday that opens the current weekly-variety window, local time.
    /// (`weekly_summaries.week_start` is a Monday, SPEC §5.)
    static func currentMonday(_ now: Date = Date(), calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return cal.date(from: comps) ?? cal.startOfDay(for: now)
    }

    /// `yyyy-MM-dd` for a `date`/`week_start` column (POSIX, stable across locales).
    static func dateString(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Start of today, local time, the floor for "today's" meals.
    static func startOfToday(_ now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: now)
    }

    /// ISO-8601 string for a PostgREST `gte.` timestamp filter.
    static func timestampString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Parse a `timestamptz` string (with or without fractional seconds).
    static func parseTimestamp(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFrac.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

// MARK: - Module-owned decode rows (tables C reads but Repository.swift doesn't model)

/// One fiber estimate from `meal_items` (coarse/directional, never precise, §3/§4).
struct ThrMealItemFiberRow: Decodable, Sendable {
    let estFiberG: Double?
}

/// A rainbow group's education copy (`colors`; the group name IS the id, SPEC §5).
/// `exampleFoods` is curated seed data (Batch D, rule #9), surfaced when a color
/// ring is tapped. Optional-decoded so a partial column select never fails.
struct ThrColorRow: Decodable, Sendable {
    let id: String
    let meaningCopy: String?
    let whatItDoesCopy: String?
    let exampleFoods: [String]?
}

// MARK: - Meal-item / food rows (Recent Meals, rainbow + 3 P's day reads, Your Foods)

/// One `meal_items` row for the Recent-Meals detail sheet: editable coarse tier
/// (no grams, rule #3) + the user's confirm/deny verdict on the AI hypothesis.
struct ThrMealItemRow: Decodable, Sendable, Identifiable {
    let id: String
    let foodId: String
    let portionTier: String
    let source: String
    let estFiberG: Double?
    let userConfirmed: Bool?
    let userDenied: Bool?
}

/// Cheap `meal_items` read for today's fiber sum + per-color rainbow amount.
struct ThrMealItemTierRow: Decodable, Sendable {
    let foodId: String
    let portionTier: String
    let estFiberG: Double?
}

/// One `food_colors` junction row (food → rainbow color group).
struct ThrFoodColorRow: Decodable, Sendable {
    let foodId: String
    let colorId: String
}

/// A `foods` name lookup (detail-sheet labels + the Suspects food search).
struct ThrFoodNameRow: Decodable, Sendable, Identifiable {
    let id: String
    let canonicalName: String
}

/// One curated curiosity fact (`curiosity_facts`), variable reward (§11a).
/// Curated content only; never generated at request time (CLAUDE.md rule #9).
struct ThrCuriosityFactRow: Decodable, Sendable {
    let id: String
    let factText: String
    let confidenceTag: String
}

/// A phytochemical reference row (`phytochemicals`). `class` is a SQL/Swift
/// keyword, so it is decoded explicitly rather than via snake-case conversion.
struct ThrPhytochemicalRow: Decodable, Sendable {
    let id: String
    let name: String
    let phytoClass: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case phytoClass = "class"
    }
}
