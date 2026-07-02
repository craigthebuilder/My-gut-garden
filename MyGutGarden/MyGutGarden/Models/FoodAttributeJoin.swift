//
//  FoodAttributeJoin.swift
//  MyGutGarden — food-attribute derivation (SPEC §5, §10, §11).
//
//  The Edge Function performs the DB join (identified foods → fiber/phytochemical/
//  guild/color attributes). This client layer turns that joined response into the
//  per-photo insights: the "3 P's", plant variety, rainbow contribution. It never
//  invents nutrition numbers (CLAUDE.md rule #2).
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

/// What the per-photo view renders (SPEC §11a).
struct ThrivePhotoInsights: Sendable {
    let plantNames: [String]
    let colorsHit: [String]
    let guildsFed: [GuildFed]
    let threePs: ThreePs
    let curiosityWorthyFermentedCount: Int
}

enum FoodAttributeJoin {

    /// Every resolved item's attributes. (Sensitivity foods are still surfaced +
    /// counted — SPEC §9; there is no silent omit in the single-mode model.)
    static func surfacedAttributes(_ response: RecognitionResponse) -> [FoodAttributes] {
        response.items.compactMap(\.attributes)
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
}
