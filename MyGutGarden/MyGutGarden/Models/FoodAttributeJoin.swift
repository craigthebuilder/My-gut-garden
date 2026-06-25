//
//  FoodAttributeJoin.swift
//  MyGutGarden — Phase 0 food-attribute derivation (SPEC §5, §10, §11).
//
//  The Edge Function performs the DB join (identified foods → fiber/FODMAP/
//  phytochemical/guild/color attributes). This client layer turns that joined
//  response into the per-photo insights each surface shows — the "3 P's",
//  plant variety, rainbow contribution (Thrive); FODMAP safety + cautions
//  (Survive). It never invents nutrition numbers (CLAUDE.md rule #2).
//

import Foundation

/// The three P's hit by a meal (SPEC §11a). Prebiotic = fiber that feeds a
/// guild; Probiotic = a fermented food; Polyphenol = a polyphenol/anthocyanin.
struct ThreePs: Sendable, Equatable {
    var prebiotic: Bool
    var probiotic: Bool
    var polyphenol: Bool

    var count: Int { (prebiotic ? 1 : 0) + (probiotic ? 1 : 0) + (polyphenol ? 1 : 0) }
    var allThree: Bool { prebiotic && probiotic && polyphenol }
}

/// What the Thrive per-photo view renders (SPEC §11a).
struct ThrivePhotoInsights: Sendable {
    let plantNames: [String]
    let colorsHit: [String]
    let guildsFed: [GuildFed]
    let threePs: ThreePs
    let curiosityWorthyFermentedCount: Int
}

/// What the Survive per-photo view renders (SPEC §11b): FODMAP safety overlay
/// + ferment caution. No bacteria, no diagnosis.
struct SurvivePhotoInsights: Sendable {
    let safety: [SafetyEntry]
    let fermentedCaution: [String]
    let hiddenIngredientPrompts: [HiddenIngredientPrompt]
}

enum FoodAttributeJoin {

    /// Matched, non-omitted attributes (preference_intolerance items are quietly
    /// dropped per the two-faced model, §9).
    static func surfacedAttributes(_ response: RecognitionResponse) -> [FoodAttributes] {
        response.items
            .filter { $0.silentlyOmitted != true }
            .compactMap(\.attributes)
    }

    static func threePs(for attributes: [FoodAttributes]) -> ThreePs {
        let prebiotic = attributes.contains { !$0.fibers.isEmpty || !$0.guildFeeds.isEmpty }
        let probiotic = attributes.contains(where: \.isFermented)
        let polyphenol = attributes.contains { food in
            food.phytochemicals.contains { $0.category == "polyphenol" }
                || food.colors.contains("blue_purple")
        }
        return ThreePs(prebiotic: prebiotic, probiotic: probiotic, polyphenol: polyphenol)
    }

    static func thriveInsights(_ response: RecognitionResponse) -> ThrivePhotoInsights {
        let attrs = surfacedAttributes(response)
        let summary = response.thrive
        return ThrivePhotoInsights(
            plantNames: summary?.uniquePlants
                ?? Array(Set(attrs.compactMap { $0.plant?.name })).sorted(),
            colorsHit: summary?.colorsHit
                ?? Array(Set(attrs.flatMap(\.colors))).sorted(),
            guildsFed: summary?.guildsFed ?? [],
            threePs: threePs(for: attrs),
            curiosityWorthyFermentedCount: summary?.fermentedCount
                ?? attrs.filter(\.isFermented).count
        )
    }

    static func surviveInsights(_ response: RecognitionResponse) -> SurvivePhotoInsights {
        let attrs = surfacedAttributes(response)
        return SurvivePhotoInsights(
            safety: response.survive?.safetyOverview
                ?? attrs.compactMap { a in
                    a.fodmap.map { SafetyEntry(foodName: a.canonicalName, safety: $0.safety) }
                },
            fermentedCaution: response.survive?.fermentedCaution
                ?? attrs.filter(\.isFermented).map(\.canonicalName),
            hiddenIngredientPrompts: response.hiddenIngredientPrompts
        )
    }
}
