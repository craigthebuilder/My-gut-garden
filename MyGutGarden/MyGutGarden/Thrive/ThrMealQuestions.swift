//
//  ThrMealQuestions.swift
//  MyGutGarden, Module C: the KEY hidden-ingredient questions (owner rework,
//  2026-07-02 round 2).
//
//  The old always-ask prompt wall ("this stir fry often contains…") drowned the
//  edit sheet, so it's gone. In its place: at most one or two questions that are
//  actually worth asking, surfaced as a small ⚠︎ on the meal's Recent-Meals
//  thumbnail and answered in the meal pop-up. "Key" means:
//    • a food the USER HAS FLAGGED (allergy/sensitivity/watching) that commonly
//      hides in one of this meal's dish types — up to two of these; else
//    • the single most common hidden ingredient for the dish, so the plant
//      count stays honest without nagging.
//  Pure + unit-testable; the views do the IO.
//

import Foundation

struct ThrMealKeyQuestion: Identifiable, Sendable, Hashable {
    let foodId: String
    let foodName: String
    let dishType: String
    /// True when the user has a food flag matching this food (the loud reason
    /// to ask). Never surfaced as blame — it's a "worth a check".
    let flagged: Bool

    var id: String { foodId + "|" + dishType }
    var prompt: String {
        "This \(dishType.replacingOccurrences(of: "_", with: " ")) often has \(foodName.lowercased()) in it — was it in there?"
    }
}

enum ThrMealQuestions {
    /// A food row trimmed to what the question logic needs.
    struct HiddenFoodRef: Sendable {
        let id: String
        let name: String
        let commonHiddenIn: [String]
        let categories: [String]
    }

    /// A user flag trimmed to matching shape (any tier counts as "key").
    struct FlagRef: Sendable {
        let foodId: String?
        let category: String?
    }

    /// The questions still worth asking for one meal.
    /// - Parameters:
    ///   - dishTypes: the meal's recognized dish types (from vision_raw_json).
    ///   - loggedFoodIds: foods already on the meal (never ask about those).
    ///   - answeredFoodNames: hidden answers already recorded on the meal.
    static func pending(dishTypes: Set<String>,
                        loggedFoodIds: Set<String>,
                        answeredFoodNames: Set<String>,
                        foods: [HiddenFoodRef],
                        flags: [FlagRef]) -> [ThrMealKeyQuestion] {
        guard !dishTypes.isEmpty else { return [] }
        let flaggedFoodIds = Set(flags.compactMap(\.foodId))
        let flaggedCategories = Set(flags.compactMap { $0.category?.lowercased() })
        let answered = Set(answeredFoodNames.map { $0.lowercased() })

        var candidates: [ThrMealKeyQuestion] = []
        for food in foods {
            guard !loggedFoodIds.contains(food.id),
                  !answered.contains(food.name.lowercased()),
                  let dish = food.commonHiddenIn.first(where: { dishTypes.contains($0) })
            else { continue }
            let flagged = flaggedFoodIds.contains(food.id)
                || food.categories.contains { flaggedCategories.contains($0.lowercased()) }
            candidates.append(ThrMealKeyQuestion(foodId: food.id, foodName: food.name,
                                                 dishType: dish, flagged: flagged))
        }

        // Flagged foods are the questions that MATTER — up to two. Without any,
        // one gentle check keeps the count honest without turning into a chore.
        let flaggedQs = candidates.filter(\.flagged).sorted { $0.foodName < $1.foodName }
        if !flaggedQs.isEmpty { return Array(flaggedQs.prefix(2)) }
        return Array(candidates.sorted { $0.foodName < $1.foodName }.prefix(1))
    }
}
