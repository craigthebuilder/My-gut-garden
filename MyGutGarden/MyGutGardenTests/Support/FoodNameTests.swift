//
//  FoodNameTests.swift
//  MyGutGardenTests — the plural-tolerant food-name matcher (owner testing
//  find, 2026-07-07: "model detects scrambled eggs but alias is scrambled
//  egg"). Mirrors the Edge Function's singularizeLastWord; these tests pin the
//  Swift side so the two matchers can't silently drift apart in behavior.
//

import Testing
@testable import MyGutGarden

struct FoodNameTests {

    @Test func pluralsSingularizeOnTheLastWordOnly() {
        #expect(FoodName.singularizedLastWord("scrambled eggs") == "scrambled egg")
        #expect(FoodName.singularizedLastWord("cherry tomatoes") == "cherry tomato")
        #expect(FoodName.singularizedLastWord("anchovies") == "anchovy")
        #expect(FoodName.singularizedLastWord("radishes") == "radish")
        #expect(FoodName.singularizedLastWord("green peas") == "green pea")
        #expect(FoodName.singularizedLastWord("brussels sprouts") == "brussels sprout")
    }

    @Test func conservativeEndingsAreLeftAlone() {
        #expect(FoodName.singularizedLastWord("watercress") == "watercress")
        #expect(FoodName.singularizedLastWord("asparagus") == "asparagus")
        #expect(FoodName.singularizedLastWord("couscous") == "couscous")
        #expect(FoodName.singularizedLastWord("hummus") == "hummus")
    }

    @Test func pluralCanonicalsNormalizeTheSameFromBothSides() {
        // "Oats" is a plural canonical; a singular query must still land on it.
        #expect(FoodName.singularizedLastWord("oats") == "oat")
        #expect(FoodName.matches(haystack: "Oats", query: "oat"))
        #expect(FoodName.matches(haystack: "Oats", query: "oats"))
    }

    @Test func matchesToleratesPluralOnEitherSide() {
        #expect(FoodName.matches(haystack: "scrambled egg", query: "scrambled eggs"))
        #expect(FoodName.matches(haystack: "Egg", query: "eggs"))
        #expect(FoodName.matches(haystack: "cherry tomato", query: "Cherry Tomatoes"))
        #expect(!FoodName.matches(haystack: "Egg", query: "eggplant"))
    }
}
