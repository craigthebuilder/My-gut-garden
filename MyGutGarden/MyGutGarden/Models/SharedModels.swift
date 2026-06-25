//
//  SharedModels.swift
//  MyGutGarden — Phase 0 shared types (SPEC §5).
//
//  The typed Swift mirror of the data model + the frozen recognition contract
//  (SPEC §4). Every module decodes the `recognize` Edge Function response into
//  these types. JSON is snake_case; decode with `.convertFromSnakeCase`
//  (see RecognitionService) so property names stay camelCase here.
//

import Foundation

// MARK: - Domain enums (mirror the Postgres enums in 20260625000001_schema.sql)

enum AppMode: String, Codable, Sendable, CaseIterable {
    case thrive, survive
}

enum PortionTier: String, Codable, Sendable {
    case trace, serving, lots
}

enum RarityTier: String, Codable, Sendable {
    case common, uncommon, rare, legendary
}

enum FodmapSafety: String, Codable, Sendable {
    case green, yellow, red
}

/// ⚠️ THE load-bearing enum (SPEC §9). Drives OPPOSITE behavior — never flatten.
/// `medicalAllergy` is LOUD across both modes; `preferenceIntolerance` is quiet.
enum ExclusionType: String, Codable, Sendable {
    case medicalAllergy = "medical_allergy"
    case preferenceIntolerance = "preference_intolerance"
}

// MARK: - Frozen vision-LLM contract (SPEC §4)

struct VisionFood: Codable, Sendable, Hashable {
    let name: String
    let portionTier: PortionTier
    let confidence: Double
    let dishType: String?
}

struct VisionResult: Codable, Sendable {
    let foods: [VisionFood]
    let sceneNotes: String?
}

// MARK: - Food attributes (produced by the DB join, NOT the LLM — rule #2)

struct PlantRef: Codable, Sendable, Hashable {
    let name: String
    let rarityTier: RarityTier
}

struct FiberAttr: Codable, Sendable, Hashable {
    let name: String
    let relativeAmount: String          // minor | moderate | primary
    let isFodmapTrigger: Bool
    let estGramsPerServing: Double?     // coarse, RD-review-fenced (Fence 4)
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
    let claimRisk: Bool                  // true => render "[emerging science]" (Fence 2)
}

struct FodmapAttr: Codable, Sendable, Hashable {
    let safety: FodmapSafety
    let fructanLevel: String
    let gosLevel: String
    let lactoseLevel: String
    let fructoseLevel: String
    let polyolLevel: String
    let servingSizeDesc: String?
}

struct FoodAttributes: Codable, Sendable, Hashable {
    let foodId: String
    let canonicalName: String
    let isPlant: Bool
    let plant: PlantRef?
    let isFermented: Bool
    let histamineLevel: String?
    let fibers: [FiberAttr]
    let colors: [String]
    let phytochemicals: [PhytochemicalAttr]
    let guildFeeds: [GuildFeedAttr]
    let fodmap: FodmapAttr?
}

// MARK: - The `recognize` Edge Function response (SPEC §4 end-to-end)

struct ResolvedItem: Codable, Sendable {
    let vision: VisionFood
    let attributes: FoodAttributes?     // nil => unmatched, needs manual confirm
    let silentlyOmitted: Bool?          // preference_intolerance match (§9, quiet)
}

struct AllergyAlert: Codable, Sendable {
    let foodName: String
    let exclusionType: ExclusionType    // always medicalAllergy here (LOUD, §9)
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

struct ThriveSummary: Codable, Sendable {
    let uniquePlants: [String]
    let colorsHit: [String]
    let guildsFed: [GuildFed]
    let fermentedCount: Int
}

struct SafetyEntry: Codable, Sendable {
    let foodName: String
    let safety: FodmapSafety
}

struct SurviveSummary: Codable, Sendable {
    let safetyOverview: [SafetyEntry]
    let fermentedCaution: [String]
}

struct RecognitionResponse: Codable, Sendable {
    let provider: String
    let mode: AppMode
    let vision: VisionResult
    let items: [ResolvedItem]
    let unmatched: [String]
    let hiddenIngredientPrompts: [HiddenIngredientPrompt]
    let allergyAlerts: [AllergyAlert]
    let thrive: ThriveSummary?
    let survive: SurviveSummary?
}
