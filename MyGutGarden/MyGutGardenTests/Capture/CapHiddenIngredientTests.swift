//
//  CapHiddenIngredientTests.swift
//  MyGutGardenTests, Module B: always-ask hidden-ingredient handling (§4, §11).
//
//  The canonical fixture carries one hidden-ingredient prompt (carrot in a
//  stir fry). These pin the "always ask" contract: nothing is logged until each
//  prompt has a definite yes/no, and a "yes" becomes a confirmable ingredient.
//

import Testing
import Foundation
@testable import MyGutGarden

struct CapHiddenIngredientTests {

    @Test func initialAnswersAreUnansweredForEveryPrompt() throws {
        let response = try Fixtures.recognition()
        let answers = CapHiddenIngredients.initialAnswers(response)

        #expect(answers.count == response.hiddenIngredientPrompts.count)
        #expect(answers.count == 1)
        #expect(answers.allSatisfy { $0.wasPresent == nil })
        #expect(answers.first?.prompt.foodName == "Carrot")
    }

    @Test func allAnsweredGatesOnEveryPromptHavingAYesOrNo() throws {
        var answers = CapHiddenIngredients.initialAnswers(try Fixtures.recognition())
        #expect(CapHiddenIngredients.allAnswered(answers) == false)

        answers[0].wasPresent = false
        #expect(CapHiddenIngredients.allAnswered(answers) == true)
    }

    @Test func confirmedPresentNamesAreOnlyTheYeses() throws {
        var answers = CapHiddenIngredients.initialAnswers(try Fixtures.recognition())

        answers[0].wasPresent = true
        #expect(CapHiddenIngredients.confirmedPresentFoodNames(answers) == ["Carrot"])

        answers[0].wasPresent = false
        #expect(CapHiddenIngredients.confirmedPresentFoodNames(answers).isEmpty)
    }

    @Test func payloadRecordsAnsweredPromptsAndOmitsUnanswered() throws {
        var answers = CapHiddenIngredients.initialAnswers(try Fixtures.recognition())

        // Unanswered → no record.
        #expect(CapHiddenIngredients.answersPayload(answers).isEmpty)

        answers[0].wasPresent = true
        let payload = CapHiddenIngredients.answersPayload(answers)
        #expect(payload.count == 1)
        #expect(payload[0]["food_name"] as? String == "Carrot")
        #expect(payload[0]["dish_type"] as? String == "stir_fry")
        #expect(payload[0]["was_present"] as? Bool == true)
    }
}
