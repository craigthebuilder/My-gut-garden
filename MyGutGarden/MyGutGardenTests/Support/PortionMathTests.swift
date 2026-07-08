//
//  PortionMathTests.swift
//  MyGutGardenTests — the client mirror of the meal_items fiber trigger
//  (20260708000001). These pin the grams-ratio math so the live "~9g fiber"
//  on the review panel can never silently disagree with what the server
//  persists, and pin the ratio→tier shadowing that keeps `portion_tier`
//  meaningful for v1 readers.
//

import Testing
@testable import MyGutGarden

struct PortionMathTests {

    @Test func gramsRatioWinsWhenBothSidesKnown() {
        // 300g of a 240g-serving food → 1.25×.
        #expect(PortionMath.ratio(estGrams: 300, typicalServingG: 240, tier: PortionTier.lots) == 1.25)
        // The tier is ignored once grams are present.
        #expect(PortionMath.ratio(estGrams: 150, typicalServingG: 150, tier: PortionTier.trace) == 1.0)
    }

    @Test func ratioClampsToTheTriggerBand() {
        #expect(PortionMath.ratio(estGrams: 1, typicalServingG: 150, tier: PortionTier.serving) == 0.1)
        #expect(PortionMath.ratio(estGrams: 2000, typicalServingG: 100, tier: PortionTier.serving) == 4.0)
    }

    @Test func tierFallbackMatchesTheLegacyMultipliers() {
        #expect(PortionMath.ratio(estGrams: nil, typicalServingG: 150, tier: PortionTier.trace) == 0.5)
        #expect(PortionMath.ratio(estGrams: 120, typicalServingG: nil, tier: PortionTier.serving) == 1.0)
        #expect(PortionMath.ratio(estGrams: nil, typicalServingG: nil, tier: PortionTier.lots) == 1.5)
        // A zero/invalid serving anchor can't divide — fall back to the tier.
        #expect(PortionMath.ratio(estGrams: 120, typicalServingG: 0, tier: PortionTier.lots) == 1.5)
    }

    @Test func ratioShadowsBackToACoarseTier() {
        #expect(PortionMath.tier(forRatio: 0.4) == .trace)
        #expect(PortionMath.tier(forRatio: 0.5) == .trace)
        #expect(PortionMath.tier(forRatio: 1.0) == .serving)
        #expect(PortionMath.tier(forRatio: 1.49) == .serving)
        #expect(PortionMath.tier(forRatio: 1.5) == .lots)
        #expect(PortionMath.tier(forRatio: 4.0) == .lots)
    }
}
