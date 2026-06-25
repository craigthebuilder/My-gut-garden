//
//  CapMealAssembly.swift
//  MyGutGarden — Module B pure assembly logic (SPEC §4, §9, §11).
//
//  These are the deterministic helpers the view-model + persistence compose and
//  the unit tests pin down: how always-ask hidden-ingredient answers are
//  tracked, how unmatched items become manual corrections, and how the three
//  sources (vision / manual / hidden_confirmed) fold into one ordered set of
//  `meal_items`. No SwiftUI, no networking — easy to test against fixtures.
//

import Foundation

// MARK: - Hidden-ingredient handling (§4 step 6, §11 — "always ask")

enum CapHiddenIngredients {

    /// The initial unanswered set from a recognize response. Every prompt is
    /// surfaced — hidden-ingredient detection is mitigated, not solved, so we
    /// ask rather than guess (§4 "when unsure, flag it").
    static func initialAnswers(_ response: RecognitionResponse) -> [CapHiddenIngredientAnswer] {
        response.hiddenIngredientPrompts.map {
            CapHiddenIngredientAnswer(prompt: $0, wasPresent: nil)
        }
    }

    /// True once every prompt has a definite yes/no. "Always ask" means an
    /// unanswered prompt shouldn't be silently treated as "no".
    static func allAnswered(_ answers: [CapHiddenIngredientAnswer]) -> Bool {
        answers.allSatisfy { $0.wasPresent != nil }
    }

    /// Food names the user confirmed were present — candidates for resolution
    /// into `hidden_confirmed` meal_items.
    static func confirmedPresentFoodNames(_ answers: [CapHiddenIngredientAnswer]) -> [String] {
        answers.filter { $0.wasPresent == true }.map(\.prompt.foodName)
    }

    /// The `meals.hidden_ingredient_answers` payload (one record per answered
    /// prompt). Unanswered prompts are omitted. JSON-encodable.
    static func answersPayload(_ answers: [CapHiddenIngredientAnswer]) -> [[String: Any]] {
        answers.compactMap { answer in
            guard let present = answer.wasPresent else { return nil }
            return [
                "food_name": answer.prompt.foodName,
                "dish_type": answer.prompt.dishType,
                "was_present": present
            ]
        }
    }
}

// MARK: - Manual confirm of unmatched items (§4 step 4)

enum CapManualConfirm {

    /// The unmatched vision guesses awaiting the user's correction.
    static func initialItems(_ response: RecognitionResponse) -> [CapUnmatchedItem] {
        response.unmatched.map { CapUnmatchedItem(visionName: $0) }
    }

    /// Only the items the user actually resolved. The rest are intentionally
    /// dropped — logging an unconfirmed guess would claim a precision we don't
    /// have (§4). Skipping is a valid, blameless choice.
    static func resolved(_ items: [CapUnmatchedItem]) -> [CapUnmatchedItem] {
        items.filter(\.isResolved)
    }
}

// MARK: - meal_items assembly (the three sources → one ordered set)

enum CapMealDraftBuilder {

    /// Matched, surfaced vision items → `vision` meal_items. `preference_intolerance`
    /// matches (`silentlyOmitted`) are dropped, consistent with the surfaced-
    /// attributes seam: a quiet omission is never persisted as something fed
    /// (§9 — the two-faced model is honoured, not flattened).
    static func visionItems(items: [ResolvedItem]) -> [CapMealItem] {
        items.compactMap { item in
            guard item.silentlyOmitted != true, let attrs = item.attributes else { return nil }
            return CapMealItem(foodId: attrs.foodId,
                               portion: item.vision.portionTier,
                               source: .vision)
        }
    }

    static func visionItems(_ response: RecognitionResponse) -> [CapMealItem] {
        visionItems(items: response.items)
    }

    /// Resolved unmatched corrections → `manual` meal_items.
    static func manualItems(_ unmatched: [CapUnmatchedItem]) -> [CapMealItem] {
        unmatched.compactMap { item in
            guard let food = item.resolvedFood else { return nil }
            return CapMealItem(foodId: food.id, portion: item.portion, source: .manual)
        }
    }

    /// Confirmed-and-resolved hidden ingredients → `hidden_confirmed` meal_items.
    static func hiddenConfirmedItems(_ resolved: [CapResolvedHidden]) -> [CapMealItem] {
        resolved.map {
            CapMealItem(foodId: $0.foodId, portion: $0.portion, source: .hiddenConfirmed)
        }
    }

    /// The complete item set in a stable, debuggable order:
    /// vision first, then manual corrections, then confirmed hidden ingredients.
    /// Duplicate `food_id`s are collapsed, keeping the first (most-confident)
    /// source — a food shouldn't be logged twice if the user also corrects it.
    static func allItems(vision: [CapMealItem],
                         manual: [CapMealItem],
                         hidden: [CapMealItem]) -> [CapMealItem] {
        var seen = Set<String>()
        var result: [CapMealItem] = []
        for item in vision + manual + hidden where seen.insert(item.foodId).inserted {
            result.append(item)
        }
        return result
    }
}
