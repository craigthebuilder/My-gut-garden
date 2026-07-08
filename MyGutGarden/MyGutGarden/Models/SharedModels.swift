//
//  SharedModels.swift
//  MyGutGarden — shared types (SPEC §5).
//
//  The typed Swift mirror of the data model + the frozen recognition contract
//  (SPEC §4). Every module decodes the `recognize` Edge Function response into
//  these types. JSON is snake_case; decode with `.convertFromSnakeCase`
//  (see RecognitionService) so property names stay camelCase here.
//
//  Single-mode: there are no modes. FODMAP + the two-faced exclusion model are
//  retired; food restrictions live in the three-tier `FlagTier` model (SPEC §9).
//

import Foundation

// MARK: - Domain enums (mirror the Postgres enums)

enum PortionTier: String, Codable, Sendable {
    case trace, serving, lots
}

enum RarityTier: String, Codable, Sendable {
    case common, uncommon, rare, legendary
}

/// The three-tier food-flag model (SPEC §9). Drives OPPOSITE surfacing:
/// `allergy` is LOUD and fires BEFORE the result overview; `sensitivity` is a
/// soft in-overview warning (the food is still eaten + logged); `watching` is
/// quiet. Never flatten allergy into a softer tier.
enum FlagTier: String, Codable, Sendable {
    case watching, sensitivity, allergy
}

/// The gas-for-growth trade the user chooses (SPEC §17). A PREFERENCE, never a
/// symptom score: it tunes the fiber ramp, the guardian's thresholds, and how
/// prominent fermentation notes are. Default `balanced` preserves the pre-§17
/// fenced values exactly.
enum GasComfort: String, Codable, CaseIterable, Sendable {
    case gentle, balanced, bold

    var label: String {
        switch self {
        case .gentle: "Keep it quiet"
        case .balanced: "Some is fine"
        case .bold: "Bring it on"
        }
    }

    var explainer: String {
        switch self {
        case .gentle: "Slower ramp, gentler nudges — comfort first."
        case .balanced: "A steady climb with the occasional lively day."
        case .bold: "Fast garden growth; a talkative gut doesn't bother you."
        }
    }

    /// One step toward gentle (the guardian's "ramp slower?" accept action).
    var gentler: GasComfort {
        switch self {
        case .bold: .balanced
        case .balanced, .gentle: .gentle
        }
    }
}

// MARK: - Food-name matching (plural-tolerant, mirrors the Edge Function)

/// Plural/singular-tolerant food-name helpers, mirroring the recognize Edge
/// Function's matcher (attributes.ts `singularizeLastWord`) so in-app search
/// behaves exactly like the pipeline: "scrambled eggs" finds the
/// "scrambled egg" alias without anyone maintaining plural aliases.
enum FoodName {
    /// Singularize the LAST word only ("cherry tomatoes" → "cherry tomato",
    /// "anchovies" → "anchovy"). Conservative: ss/us/is endings (watercress,
    /// asparagus) are left alone, and plural canonicals ("Oats") normalize the
    /// same from both sides of a comparison.
    static func singularizedLastWord(_ name: String) -> String {
        var words = name.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard var word = words.last else { return name }
        if word.count > 4, word.hasSuffix("ies") {
            word = String(word.dropLast(3)) + "y"
        } else if word.count > 4, word.hasSuffix("oes") {
            word = String(word.dropLast(2))
        } else if word.count > 4, ["ches", "shes", "sses", "xes", "zes"].contains(where: word.hasSuffix) {
            word = String(word.dropLast(2))
        } else if word.count > 3, word.hasSuffix("s"),
                  !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is") {
            word = String(word.dropLast())
        }
        words[words.count - 1] = word
        return words.joined(separator: " ")
    }

    /// Case-insensitive substring match that tolerates a plural/singular
    /// mismatch on either side's last word.
    static func matches(haystack: String, query: String) -> Bool {
        let h = haystack.lowercased()
        let q = query.lowercased()
        if h.contains(q) { return true }
        let hs = singularizedLastWord(h)
        let qs = singularizedLastWord(q)
        return h.contains(qs) || hs.contains(qs) || hs.contains(q)
    }
}

// MARK: - Portion math (mirrors the est_fiber_g DB trigger)

/// Client-side mirror of the meal_items fiber trigger (20260708000001) so live
/// UI estimates agree with what the server persists: grams ratio against the
/// food's typical serving when both are known, else the coarse tier multiplier.
/// RD-REVIEW-REQUIRED: the clamp band and tier multipliers are fenced (Fence 2/4).
enum PortionMath {
    static func ratio(estGrams: Double?, typicalServingG: Double?, tier: String) -> Double {
        if let grams = estGrams, let serving = typicalServingG, serving > 0 {
            return min(4.0, max(0.1, grams / serving))
        }
        switch tier {
        case "trace": return 0.5
        case "lots": return 1.5
        default: return 1.0
        }
    }

    static func ratio(estGrams: Double?, typicalServingG: Double?, tier: PortionTier) -> Double {
        ratio(estGrams: estGrams, typicalServingG: typicalServingG, tier: tier.rawValue)
    }

    /// The coarse tier a grams ratio lands in — kept in sync with the slider
    /// bands so `portion_tier` stays meaningful for v1 readers of the column.
    static func tier(forRatio ratio: Double) -> PortionTier {
        if ratio <= 0.5 { return .trace }
        if ratio >= 1.5 { return .lots }
        return .serving
    }
}

// MARK: - Meal time labels (check-in linking)

/// Time-derived meal names ("11am breakfast") for anywhere a logged meal is
/// referenced outside its own detail view — above all the check-in's
/// "link to a meal" picker. Owner decision (2026-07-08): a meal is named by
/// WHEN it happened, never by the note text and never "Meal 2" — people
/// remember "the 11am breakfast", so that's the name they link symptoms to.
enum MealTimeLabel {
    /// "11am breakfast", "1pm lunch", "7pm dinner", "11pm late bite".
    static func label(for date: Date, calendar: Calendar = .current,
                      withMinutes: Bool = false) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let hour = comps.hour ?? 12
        return clockText(hour: hour, minute: comps.minute ?? 0, withMinutes: withMinutes)
            + " " + daypart(hour: hour)
    }

    /// Labels for one day's meals, in the same order. Two meals landing on the
    /// same coarse label get minutes appended so a grazing day still reads
    /// unambiguously ("8:05am breakfast" / "8:40am breakfast").
    static func labels(for dates: [Date], calendar: Calendar = .current) -> [String] {
        let coarse = dates.map { label(for: $0, calendar: calendar) }
        return coarse.enumerated().map { i, text in
            let duplicated = coarse.enumerated().contains { $0.offset != i && $0.element == text }
            return duplicated ? label(for: dates[i], calendar: calendar, withMinutes: true) : text
        }
    }

    /// breakfast 4–11:59, lunch 12–15:59, dinner 16–21:59, late bite otherwise.
    static func daypart(hour: Int) -> String {
        switch hour {
        case 4...11: "breakfast"
        case 12...15: "lunch"
        case 16...21: "dinner"
        default: "late bite"
        }
    }

    private static func clockText(hour: Int, minute: Int, withMinutes: Bool) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        return withMinutes ? String(format: "%d:%02d%@", h12, minute, suffix) : "\(h12)\(suffix)"
    }
}

// MARK: - Vision-LLM contract (SPEC §4) — CONTRACT v2

/// v2 (owner decision, 2026-07-08): the model estimates what it can SEE —
/// identity + quantity (`householdMeasure` + `estGrams`) and decomposes mixed
/// dishes into components. Composition stays DB-owned (rule #2): same food,
/// same numbers, every day. v2 fields are optional so v1 payloads still decode.
struct VisionFood: Codable, Sendable, Hashable {
    let name: String
    let portionTier: PortionTier        // coarse fallback (annotation/no-photo paths)
    let confidence: Double
    let dishType: String?
    let householdMeasure: String?       // "a fist", "a cupped handful" — the human anchor
    let estGrams: Double?               // grams VISIBLE (quantity, never composition)
}

struct VisionResult: Codable, Sendable {
    let foods: [VisionFood]
    let sceneNotes: String?
}

// MARK: - Food attributes (produced by the DB join, NOT the LLM, rule #2)

struct PlantRef: Codable, Sendable, Hashable {
    let name: String
    let rarityTier: RarityTier
}

struct FiberAttr: Codable, Sendable, Hashable {
    let name: String
    let relativeAmount: String          // minor | moderate | primary
    let fermentability: String?         // low | moderate | high — coarse tolerance hint (Fence 2)
    let estGramsPerServing: Double?     // coarse, RD-review-fenced
}

struct PhytochemicalAttr: Codable, Sendable, Hashable {
    let name: String
    let category: String                // carotenoid | polyphenol | ...

    enum CodingKeys: String, CodingKey {
        case name
        case category = "class"
    }
}

struct GuildFeedAttr: Codable, Sendable, Hashable {
    let internalName: String
    let displayName: String
    let relevance: String               // minor | moderate | primary
    let claimRisk: Bool                  // RD-review ledger only (Fence 1); no visible tag (owner, 2026-07-02)
}

struct FoodAttributes: Codable, Sendable, Hashable {
    let foodId: String
    let canonicalName: String
    let isPlant: Bool
    let plant: PlantRef?
    let isFermented: Bool
    /// Grams of one typical serving (RD-fenced placeholder) — the anchor that
    /// turns `estGrams` into a portion ratio for the live ~fiber math.
    let typicalServingG: Double?
    let fibers: [FiberAttr]
    let colors: [String]
    let phytochemicals: [PhytochemicalAttr]
    let guildFeeds: [GuildFeedAttr]

    /// Directional fiber for ONE typical serving (Σ fiber-fraction grams, Fence 4).
    var fiberPerServingG: Double { fibers.reduce(0) { $0 + ($1.estGramsPerServing ?? 0) } }
}

// MARK: - The `recognize` Edge Function response (SPEC §4 end-to-end)

struct ResolvedItem: Codable, Sendable {
    let vision: VisionFood
    let attributes: FoodAttributes?     // nil => unmatched, needs manual confirm
}

/// LOUD, fires BEFORE the result overview (SPEC §9). Server-computed from the
/// user's `food_flags` where `flag_tier = 'allergy'`.
struct AllergyAlert: Codable, Sendable {
    let foodName: String
    let flagTier: FlagTier              // always .allergy here
}

/// Soft, in-overview heads-up (SPEC §9). The food is still eaten + logged.
/// Server-computed from `food_flags` where `flag_tier = 'sensitivity'`.
struct SensitivityFlag: Codable, Sendable, Identifiable {
    let foodName: String
    let foodId: String
    var id: String { foodId }
}

struct HiddenIngredientPrompt: Codable, Sendable, Identifiable {
    let foodName: String
    let dishType: String
    let prompt: String
    var id: String { "\(foodName)-\(dishType)" }
}

struct GuildFed: Codable, Sendable, Hashable {
    let displayName: String
    let claimRisk: Bool
}

/// The single per-photo garden summary (SPEC §11a). "Thrive" persists only as an
/// internal code label — there are no user-facing modes.
struct ThriveSummary: Codable, Sendable {
    let uniquePlants: [String]
    let colorsHit: [String]
    let guildsFed: [GuildFed]
    let fermentedCount: Int
}

struct RecognitionResponse: Codable, Sendable {
    let provider: String
    let vision: VisionResult
    let items: [ResolvedItem]
    let unmatched: [String]
    let hiddenIngredientPrompts: [HiddenIngredientPrompt]
    let allergyAlerts: [AllergyAlert]
    let sensitivityFlags: [SensitivityFlag]
    let thrive: ThriveSummary?
}
