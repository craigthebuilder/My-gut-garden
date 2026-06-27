//
//  PatSuspectGate.swift
//  MyGutGarden, Module F (Survive pattern engine).
//
//  ╔══════════════════════════════════════════════════════════════════════╗
//  ║  🔒 FENCE 7, RD-REVIEW-REQUIRED                                       ║
//  ║                                                                        ║
//  ║  The suspect auto-suggestion gate. EVERY threshold here (how many      ║
//  ║  meals, what severity, what proximity window) is PLACEHOLDER clinical  ║
//  ║  content and must be reviewed by a registered dietitian + the owner    ║
//  ║  before launch (SPEC §14 Fence 7, CLAUDE.md §3).                       ║
//  ║                                                                        ║
//  ║  WHAT THIS IS: a gentle observation. The app may only SUGGEST a food   ║
//  ║  to keep an eye on (added_by='system', status='suspect',               ║
//  ║  user_verdict=NULL). It is NEVER an accusation, NEVER a verdict, and    ║
//  ║  there is NO severity / score / confidence field (no bad-guy meter,    ║
//  ║  rule #4). The user authors every confirm / deny / avoid elsewhere.    ║
//  ║  `avoid` is NOT an exclusion_type and is never written here (rule #1).  ║
//  ╚══════════════════════════════════════════════════════════════════════╝
//

import Foundation

/// Minimal `meal_items` projection (PatternEngine-owned; the spine has no struct
/// for this join table, so the engine decodes just the two columns it needs).
struct PatMealItemRow: Decodable, Sendable {
    let mealId: String
    let foodId: String
}

extension PatPatternEngine {

    // MARK: - Pure gate logic (RD-REVIEW-REQUIRED, Fence 7)

    /// PURE. Returns the food ids that qualify for a SUGGESTION: a food eaten on
    /// at least `suspectSuggestionMinMeals` occasions where a symptom of severity
    /// >= `suspectSuggestionMinSeverity` followed the meal within
    /// `suspectSuggestionProximityHours`. Deterministic (sorted) output.
    ///
    /// `blockedFoodIds` is the set of medical_allergy food ids, which are NEVER
    /// suggested: that LOUD pass owns those foods (rule #1).
    ///
    /// // RD-REVIEW-REQUIRED: every threshold below is a Fence-7 placeholder.
    static func suspectFoodIdsToSuggest(
        meals: [MealRow],
        mealItems: [PatMealItemRow],
        symptomEntries: [SymptomEntryRow],
        excluding blockedFoodIds: Set<String> = [],
        config: GameConfig = .shared
    ) -> [String] {
        let minMeals = config.suspectSuggestionMinMeals            // RD-REVIEW-REQUIRED
        let minSeverity = config.suspectSuggestionMinSeverity      // RD-REVIEW-REQUIRED
        let windowHours = config.suspectSuggestionProximityHours   // RD-REVIEW-REQUIRED
        let window = TimeInterval(windowHours) * 3600

        // Timestamps of symptoms severe enough to count. A symptom with no
        // recorded time can't establish proximity, so it is skipped (not guessed).
        let symptomTimes: [Date] = symptomEntries.compactMap { entry in
            guard entry.severity >= minSeverity else { return nil }   // RD-REVIEW-REQUIRED
            guard let occurred = entry.occurredAt,
                  let time = parseTimestamp(occurred) else { return nil }
            return time
        }

        // Foods present in each meal.
        var foodsByMeal: [String: Set<String>] = [:]
        for item in mealItems {
            foodsByMeal[item.mealId, default: []].insert(item.foodId)
        }

        // Count, per food, the meals followed by a qualifying symptom in-window.
        var qualifyingMealsByFood: [String: Int] = [:]
        for meal in meals {
            guard let foods = foodsByMeal[meal.id], !foods.isEmpty else { continue }
            guard let mealTime = parseTimestamp(meal.capturedAt) else { continue }
            // The symptom must FOLLOW the meal within the window. // RD-REVIEW-REQUIRED
            let followed = symptomTimes.contains { $0 > mealTime && $0 <= mealTime + window }
            guard followed else { continue }
            for foodId in foods where !blockedFoodIds.contains(foodId) {
                qualifyingMealsByFood[foodId, default: 0] += 1
            }
        }

        return qualifyingMealsByFood
            .filter { $0.value >= minMeals }   // RD-REVIEW-REQUIRED
            .keys
            .sorted()
    }

    /// The insert body for a system SUGGESTION. Deliberately minimal:
    ///   • added_by = 'system'  → a dismissible suggestion, not a verdict
    ///   • status   = 'suspect' → "keeping an eye on", the gentlest state
    ///   • user_verdict is OMITTED (stays NULL) → the user authors every verdict
    ///   • avoid is OMITTED (defaults false)    → never an accusation / exclusion
    ///   • NO severity / score / confidence key exists by design (rule #4)
    /// Exposed so tests can assert the suggestion shape without a live DB.
    static func suspectSuggestionBody(userId: String, foodId: String) -> [String: PGValue] {
        [
            "user_id": .string(userId),
            "food_id": .string(foodId),
            "added_by": .string("system"),
            "status": .string("suspect"),
        ]
    }

    // MARK: - Persistence (I/O, not pure)

    /// Fetches the user's meals + meal_items, runs the gate, and INSERTS a
    /// suggestion for each qualifying food. Idempotent: the `unique(user_id,
    /// food_id)` constraint + `ignoreDuplicates` make a re-run a no-op and never
    /// overwrite a row the user already authored (suspect/avoid/cleared).
    func suggestSuspects(
        repository: Repository,
        userId: String,
        symptomEntries: [SymptomEntryRow],
        asOf: Date = Date()
    ) async throws {
        let meals: [MealRow] = try await repository.select(
            "meals", filters: ["user_id": "eq.\(userId)"], order: "captured_at.asc")
        guard !meals.isEmpty else { return }

        // meal_items has no user_id column (RLS flows through the parent meal), so
        // scope the fetch to this user's meal ids.
        let inList = "in.(\(meals.map(\.id).joined(separator: ",")))"
        let mealItems: [PatMealItemRow] = try await repository.select(
            "meal_items", filters: ["meal_id": inList])

        // Never suggest a medical_allergy food: that LOUD pass owns those foods,
        // and the soft suspect channel must not touch them (rule #1). A failed
        // exclusions read degrades to "no extra blocking", never to a crash.
        let blocked = Set(
            ((try? await repository.fetchExclusions()) ?? [])
                .filter { $0.exclusionType == .medicalAllergy }
                .compactMap(\.foodId))

        let foodIds = Self.suspectFoodIdsToSuggest(
            meals: meals, mealItems: mealItems,
            symptomEntries: symptomEntries, excluding: blocked, config: config)

        for foodId in foodIds {
            try await repository.upsert(
                "food_suspects",
                Self.suspectSuggestionBody(userId: userId, foodId: foodId),
                onConflict: "user_id,food_id",
                ignoreDuplicates: true)
        }
    }
}
