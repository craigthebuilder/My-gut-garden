//
//  CapEditMealModel.swift
//  MyGutGarden, Module B non-blocking meal editor (SPEC §4, Batch C).
//
//  Opened from the confirmed screen (or, later, Recent Meals). Loads a logged
//  meal's items, lets the user add / delete ingredients and change RELATIVE
//  amounts (coarse trace/serving/lots tiers only, never grams, rule #3), and
//  re-surfaces the deferred hidden-ingredient prompts. Saving replaces the
//  meal_items wholesale (delete-then-reinsert). The `meals` row (photo, note,
//  vision_raw_json) is read-only here. Offline meals (no id) can't be edited.
//

import Foundation
import Observation

@MainActor
@Observable
final class CapEditMealModel: Identifiable {
    let id = UUID()

    /// One editable ingredient row. `mealItemId` is nil for rows the user just
    /// added (not yet persisted); the editor reinserts the whole set on save.
    struct Row: Identifiable, Sendable {
        let rowID = UUID()
        var mealItemId: String?
        let foodId: String
        let name: String
        var portion: PortionTier
        var source: CapItemSource

        var id: UUID { rowID }
    }

    private(set) var rows: [Row] = []
    private(set) var photoURL: String?
    private(set) var photoRemoved = false      // photos are permanent; photo_url is nil only if the user deleted it
    private(set) var userAnnotation: String?   // shown read-only
    var hiddenAnswers: [CapHiddenIngredientAnswer] = []

    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var didSave = false
    var errorText: String?

    private let repository: Repository
    private let userId: String
    let mealId: String
    private let deferredHiddenPrompts: [HiddenIngredientPrompt]

    init(repository: Repository, userId: String, mealId: String,
         deferredHiddenPrompts: [HiddenIngredientPrompt] = []) {
        self.repository = repository
        self.userId = userId
        self.mealId = mealId
        self.deferredHiddenPrompts = deferredHiddenPrompts
        self.hiddenAnswers = deferredHiddenPrompts.map {
            CapHiddenIngredientAnswer(prompt: $0, wasPresent: nil)
        }
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // The meals row (photo + annotation, read-only).
            let meals: [MealRow] = try await repository.select(
                "meals", filters: ["id": "eq.\(mealId)"], limit: 1)
            if let meal = meals.first {
                photoURL = meal.photoUrl
                photoRemoved = meal.photoUrl == nil      // nil photo_url means the user deleted the photo
                userAnnotation = meal.userAnnotation
            }

            // The meal_items, joined to the food's canonical name.
            let items: [CapMealItemRow] = try await repository.select(
                "meal_items",
                columns: "id,food_id,portion_tier,source,foods(canonical_name)",
                filters: ["meal_id": "eq.\(mealId)"]
            )
            rows = items.map { item in
                Row(
                    mealItemId: item.id,
                    foodId: item.foodId,
                    name: item.foods?.canonicalName ?? "Food",
                    portion: PortionTier(rawValue: item.portionTier) ?? .serving,
                    source: CapItemSource(rawValue: item.source) ?? .manual
                )
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Edit interactions

    func setPortion(_ row: Row, portion: PortionTier) {
        guard let idx = rows.firstIndex(where: { $0.rowID == row.rowID }) else { return }
        rows[idx].portion = portion
    }

    func delete(_ row: Row) {
        rows.removeAll { $0.rowID == row.rowID }
    }

    /// Add a manually-chosen ingredient (skips if its food is already present).
    func addFood(_ food: CapFoodSearchResult) {
        guard !rows.contains(where: { $0.foodId == food.id }) else { return }
        rows.append(Row(mealItemId: nil, foodId: food.id, name: food.canonicalName,
                        portion: .serving, source: .manual))
    }

    func setHiddenAnswer(_ answer: CapHiddenIngredientAnswer, wasPresent: Bool) {
        guard let idx = hiddenAnswers.firstIndex(where: { $0.id == answer.id }) else { return }
        hiddenAnswers[idx].wasPresent = wasPresent
    }

    func searchFoods(_ term: String) async -> [CapFoodSearchResult] {
        (try? await CapFoodSearchService(repository: repository).search(term)) ?? []
    }

    /// Delete the meal's photo (privacy, Fence 5). Nils photo_url server-side; the
    /// food data is kept. Photos are otherwise permanent (SPEC §4/§15).
    func deletePhoto() async {
        do {
            try await CapMealPersistence(repository: repository, userId: userId).deletePhoto(mealId: mealId)
            photoRemoved = true
            photoURL = nil
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Save (delete-then-reinsert, coarse tiers only)

    func save() async {
        isSaving = true
        defer { isSaving = false }

        // Resolve any newly-confirmed hidden ingredients to real foods.
        let search = CapFoodSearchService(repository: repository)
        var items: [CapMealItem] = rows.map {
            CapMealItem(foodId: $0.foodId, portion: $0.portion, source: $0.source)
        }
        var seen = Set(items.map(\.foodId))
        for name in CapHiddenIngredients.confirmedPresentFoodNames(hiddenAnswers) {
            if let match = try? await search.bestMatch(for: name), seen.insert(match.id).inserted {
                items.append(CapMealItem(foodId: match.id, portion: .serving, source: .hiddenConfirmed))
            }
        }

        do {
            try await CapMealPersistence(repository: repository, userId: userId)
                .updateItems(mealId: mealId, items: items)
            didSave = true
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - meal_items row (Cap-local; the shared Repository has no meal_items type)

/// Decodes a meal_items row joined to its food's canonical name. snake_case keys
/// map via the Repository decoder's `.convertFromSnakeCase`.
struct CapMealItemRow: Decodable, Sendable {
    let id: String
    let foodId: String
    let portionTier: String
    let source: String
    let foods: FoodNameRef?

    struct FoodNameRef: Decodable, Sendable {
        let canonicalName: String
    }
}
