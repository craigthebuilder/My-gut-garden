//
//  ThrMealQuestionsTests.swift
//  MyGutGardenTests — the KEY hidden-ingredient questions (owner rework, round 2).
//
//  Load-bearing invariants: FLAGGED foods win and cap at two; without a flag we
//  ask at most one gentle check; a food already logged or already answered is
//  never asked; no dish types → no questions (the wall is gone).
//

import Testing
@testable import MyGutGarden

struct ThrMealQuestionsTests {
    typealias Food = ThrMealQuestions.HiddenFoodRef
    typealias Flag = ThrMealQuestions.FlagRef

    static let onion = Food(id: "f-onion", name: "Onion", commonHiddenIn: ["stir_fry", "soup"], categories: ["allium"])
    static let garlic = Food(id: "f-garlic", name: "Garlic", commonHiddenIn: ["stir_fry"], categories: ["allium"])
    static let butter = Food(id: "f-butter", name: "Butter", commonHiddenIn: ["stir_fry"], categories: ["dairy"])
    static let carrot = Food(id: "f-carrot", name: "Carrot", commonHiddenIn: ["stir_fry"], categories: [])

    @Test func noDishTypesMeansNoQuestions() {
        let qs = ThrMealQuestions.pending(dishTypes: [], loggedFoodIds: [], answeredFoodNames: [],
                                          foods: [Self.onion], flags: [])
        #expect(qs.isEmpty)
    }

    @Test func withoutAFlagWeAskAtMostOne() {
        let qs = ThrMealQuestions.pending(dishTypes: ["stir_fry"], loggedFoodIds: [], answeredFoodNames: [],
                                          foods: [Self.onion, Self.garlic, Self.carrot], flags: [])
        #expect(qs.count == 1)
    }

    @Test func flaggedFoodsWinAndCapAtTwo() {
        // Onion + garlic flagged via the allium category; butter unflagged.
        let qs = ThrMealQuestions.pending(
            dishTypes: ["stir_fry"], loggedFoodIds: [], answeredFoodNames: [],
            foods: [Self.onion, Self.garlic, Self.butter],
            flags: [Flag(foodId: nil, category: "allium")])
        #expect(qs.count == 2)
        #expect(qs.allSatisfy { $0.flagged })
        #expect(Set(qs.map(\.foodName)) == ["Garlic", "Onion"])
    }

    @Test func aFoodFlaggedByIdIsKey() {
        let qs = ThrMealQuestions.pending(
            dishTypes: ["stir_fry"], loggedFoodIds: [], answeredFoodNames: [],
            foods: [Self.onion, Self.carrot],
            flags: [Flag(foodId: "f-onion", category: nil)])
        #expect(qs.count == 1)
        #expect(qs.first?.foodName == "Onion")
        #expect(qs.first?.flagged == true)
    }

    @Test func alreadyLoggedFoodsAreNeverAsked() {
        let qs = ThrMealQuestions.pending(
            dishTypes: ["stir_fry"], loggedFoodIds: ["f-onion", "f-garlic", "f-carrot"],
            answeredFoodNames: [], foods: [Self.onion, Self.garlic, Self.carrot], flags: [])
        #expect(qs.isEmpty)
    }

    @Test func alreadyAnsweredFoodsAreNeverAskedAgain() {
        let qs = ThrMealQuestions.pending(
            dishTypes: ["stir_fry"], loggedFoodIds: [], answeredFoodNames: ["Onion"],
            foods: [Self.onion], flags: [Flag(foodId: nil, category: "allium")])
        #expect(qs.isEmpty)
    }
}
