//
//  OnbViewModel.swift
//  MyGutGarden, Module A: the intake flow state + persistence (SPEC §6, §10).
//
//  Holds every captured field, derives the INTERNAL fiber numbers via the PURE
//  OnbFiberGoal, and writes through AppState.repository. Reads/writes the shared
//  data model only; never re-styles UI; never displays est_daily_kcal or the
//  fiber target.
//
//  Single-mode: no routing, no modes, no Survive. Food restrictions are written
//  to `food_flags` (three-tier model, SPEC §9). The surfaced fiber goal stays
//  unset until the week-1 baseline quest unlocks it, so onboarding writes only
//  the INTERNAL est_daily_kcal + fiber_target_g and leaves fiber_goal_state at
//  its DB default ('baseline_pending').
//

import Foundation
import Observation

@MainActor
@Observable
final class OnbViewModel {
    // The app-wide state (data layer, auth, profile). Module A only reads/writes
    // through it; the shell wires it in.
    private let appState: AppState

    // MARK: Flow position
    var step: OnbStep = .welcome

    // MARK: Captured intake (SPEC §6)
    var goals: Set<OnbGoal> = []

    // MARK: Body basics. Pre-filled with neutral medians so the internal fiber
    // target is always derivable; the user adjusts. Never framed as a weight-loss
    // target (§10).

    /// Unit system for display only. Storage is always cm/kg.
    var unitSystem: UnitSystem = .metric

    var heightCm: Double = 170
    var weightKg: Double = 70

    // Age is always captured via the wheel picker (no toggle). The "Optional"
    // callout in the UI is informational, not a gate.
    var ageValue: Int = 30

    var sex: OnbSex = .unspecified
    var activity: OnbActivityLevel = .moderate

    /// Plant-food consumption level; drives the fiber-target multiplier. Always written.
    var plantConsumptionLevel: PlantConsumptionTier = .moderate

    /// SPEC §17: the gas-for-growth trade. A preference (tunes ramp + guardian
    /// thresholds), never a symptom score. Always written.
    var gasComfort: GasComfort = .balanced

    /// The user-chosen gut-gardener name (owner, 2026-07-09). Guides the intro
    /// story, greets on the map, fronts the tour, signs guardian nudges.
    var gardenerName: String = OnbGardener.defaultName

    var baseline = OnbBaseline()

    // Food flags (§9 three-tier model). Each draft keeps scope + tier distinct,
    // never flattened; written to `food_flags` on save.
    var foodFlags: [OnbDraftFlag] = []
    var foodQuery: String = ""
    var foodHits: [OnbFoodHit] = []

    // Disclaimer signals (drive modals, never blocks).
    var seriousConditions: Set<String> = []   // OnbSeriousCondition.key
    var redFlags: Set<String> = []            // OnbRedFlag.key

    // Social proof.
    var successStories: [OnbSuccessStory] = []

    // Status.
    var isSaving = false
    var errorMessage: String?
    var didFinish = false

    init(appState: AppState) { self.appState = appState }

    // MARK: - US unit display helpers (display only; do not store these)

    var heightFeet: Int { Int(heightCm / 30.48) }
    var heightRemainingInches: Int { Int((heightCm / 2.54).rounded()) % 12 }
    var weightLbs: Int { Int((weightKg * 2.20462).rounded()) }

    func setHeightFromUS(feet: Int, inches: Int) {
        heightCm = Double(feet) * 30.48 + Double(inches) * 2.54
    }

    func setWeightFromUS(lbs: Int) {
        weightKg = Double(lbs) / 2.20462
    }

    // MARK: - Derived (SPEC §10)

    /// INTERNAL ONLY. Holds `estDailyKcal` and the plant-adjusted grams that we
    /// persist to `fiber_target_g`. NEVER surfaced to a view at onboarding — the
    /// user-facing fiber goal is unlocked later by the week-1 baseline quest.
    /// Kept private so no view can reach it (Fence 5).
    private var derivation: OnbFiberGoal.Derivation {
        OnbFiberGoal.derive(heightCm: heightCm, weightKg: weightKg,
                            age: ageValue, sex: sex, activity: activity,
                            plantConsumptionLevel: plantConsumptionLevel)
    }

    // MARK: - Mutations

    func toggleGoal(_ goal: OnbGoal) {
        if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) }
    }

    // MARK: Food flags (§9)

    /// Toggle-style add/remove so tapping a selected category chip deselects it.
    func toggleCategoryFlag(_ category: OnbFlagCategory) {
        let scope = OnbFlagScope.category(key: category.key, label: category.label)
        if foodFlags.contains(where: { $0.scope == scope }) {
            foodFlags.removeAll { $0.scope == scope }
        } else {
            addCategoryFlag(key: category.key, label: category.label, tier: category.suggestedTier)
        }
    }

    func addCategoryFlag(key: String, label: String, tier: FlagTier) {
        let scope = OnbFlagScope.category(key: key, label: label)
        guard !foodFlags.contains(where: { $0.scope == scope }) else { return }
        foodFlags.append(OnbDraftFlag(scope: scope, flagTier: tier))
    }

    func addFoodFlag(_ hit: OnbFoodHit) {
        let scope = OnbFlagScope.food(id: hit.id, name: hit.canonicalName)
        guard !foodFlags.contains(where: { $0.scope == scope }) else { return }
        // Default a specific food to the softer health tier; the user escalates to allergy.
        foodFlags.append(OnbDraftFlag(scope: scope, flagTier: .sensitivity))
        foodQuery = ""
        foodHits = []
    }

    func removeFoodFlag(_ id: OnbDraftFlag.ID) {
        foodFlags.removeAll { $0.id == id }
    }

    // MARK: Disclaimers

    func toggleSeriousCondition(_ condition: OnbSeriousCondition) {
        if seriousConditions.contains(condition.key) { seriousConditions.remove(condition.key) }
        else { seriousConditions.insert(condition.key) }
    }

    func toggleRedFlag(_ flag: OnbRedFlag) {
        if redFlags.contains(flag.key) { redFlags.remove(flag.key) } else { redFlags.insert(flag.key) }
    }

    /// Celiac -> propose a LOUD gluten flag (`flag_tier = allergy`, §9). Called on
    /// acknowledgment; removable, never silently collapsed. otherAutoimmune + ibd
    /// note the disclaimer only (no food flag, no persisted column).
    func acknowledgeSeriousConditions() {
        if seriousConditions.contains(OnbSeriousCondition.celiac.key) {
            addCategoryFlag(key: "gluten", label: "Gluten", tier: .allergy)
        }
    }

    // MARK: - Navigation

    func advance() {
        if let next = step.next { step = next }
    }

    func goBack() {
        if let prev = step.previous { step = prev }
    }

    // MARK: - IO

    /// Truthful, representative only, prefer verified; hide the section if none.
    func loadSuccessStories() async {
        guard successStories.isEmpty, let repo = appState.repository else { return }
        let rows: [OnbSuccessStory]? = try? await repo.select(
            "success_stories", order: "verified.desc", limit: 2)
        if let rows { successStories = rows }
    }

    /// One search row carrying aliases so "meat" finds Beef, "acv" finds apple
    /// cider vinegar, etc. The catalog is small; fetch once, filter in memory.
    private struct OnbFoodSearchRow: Decodable, Sendable {
        let id: String
        let canonicalName: String
        let aliases: [String]
    }
    private var allFoodRows: [OnbFoodSearchRow] = []

    /// Case-insensitive, plural-tolerant substring match over canonical names
    /// AND aliases ("scrambled eggs" finds the "scrambled egg" alias).
    func searchFoods() async {
        let q = foodQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let repo = appState.repository else { foodHits = []; return }
        if allFoodRows.isEmpty {
            allFoodRows = (try? await repo.select(
                "foods", columns: "id,canonical_name,aliases", order: "canonical_name")) ?? []
        }
        foodHits = allFoodRows.filter { row in
            FoodName.matches(haystack: row.canonicalName, query: q)
                || row.aliases.contains { FoodName.matches(haystack: $0, query: q) }
        }
        .prefix(8)
        .map { OnbFoodHit(id: $0.id, canonicalName: $0.canonicalName) }
    }

    /// Persist intake: PATCH the internal profile fields + stamp onboarded_at, then
    /// INSERT each food flag with its own tier. Completes locally when offline/demo
    /// so the flow never dead-ends.
    func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        if let repo = appState.repository, let uid = appState.auth.user?.id {
            do {
                try await repo.update("users", set: usersWriteBody(), filters: ["id": "eq.\(uid)"])
                // Each flag written with its OWN tier, never merged (§9).
                for draft in foodFlags {
                    try await repo.insertVoid("food_flags",
                                              OnbFlagWriter.insertBody(userId: uid, draft: draft))
                }
                await appState.refreshProfile()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
        }
        didFinish = true
    }

    /// The `users` PATCH body. Single-mode + duty-of-care notes:
    ///   - `est_daily_kcal` + `fiber_target_g`: INTERNAL columns; written but NEVER
    ///     decoded into UserProfile or displayed (SPEC §10 / Fence 5).
    ///   - The SURFACED `fiber_goal_g` is deliberately NOT written, and
    ///     `fiber_goal_state` is left at its DB default ('baseline_pending') so the
    ///     week-1 baseline quest unlocks the goal (no fiber number at onboarding).
    ///   - `baseline_mood`: CANONICAL high=better. The UI shows Regulated(1)..Erratic(5),
    ///     which is INVERTED from high=better. We store `6 - baseline.mood` so the
    ///     pattern engine (high=better, 5=regulated) never sees the UI polarity. This
    ///     is the SINGLE inversion point for onboarding baseline mood.
    ///   - `plant_consumption_level`: ALWAYS written.
    ///   - `onboarded_at`: the clean isOnboarded marker (AppState.isOnboarded).
    private func usersWriteBody() -> [String: PGValue] {
        let d = derivation
        return [
            "height_cm":      .double(heightCm),
            "weight_kg":      .double(weightKg),
            "age":            .int(ageValue),
            "sex":            sex.dbValue.map(PGValue.string) ?? .null,
            "activity_level": .string(activity.rawValue),

            // INTERNAL ONLY (Fence 5): never displayed, never framed as calories/target.
            "est_daily_kcal": .double(d.estDailyKcal),
            "fiber_target_g": .int(d.fiberGoalG),

            // MOOD CANONICAL INVERSION (single point):
            // UI shows Regulated(1=best)..Erratic(5=worst); canonical is high=better.
            // Stored as 6 - uiValue so 1 (Regulated/best) -> 5 (stored best).
            "baseline_mood":    .int(6 - baseline.mood),
            "baseline_energy":  .int(baseline.energy),
            "baseline_clarity": .int(baseline.clarity),

            "plant_consumption_level": .string(plantConsumptionLevel.rawValue),
            "gas_comfort":             .string(gasComfort.rawValue),
            "gardener_name":           .string(OnbGardener.sanitized(gardenerName)),
            "goals":                   .stringArray(goals.map(\.rawValue).sorted()),

            // Clean isOnboarded marker: onboarded_at != nil (SPEC §6).
            "onboarded_at": .date(Date()),
        ]
    }
}

// MARK: - Steps

/// The intake sequence (SPEC §6). Welcome leads with the fun (never opens
/// "how's your gut?"); body basics stay away from number-framing; the summary is
/// a week-1 baseline quest (no fiber number is ever shown at onboarding).
enum OnbStep: Int, CaseIterable, Hashable {
    case welcome, goals, body, baseline, flags, checks, gardener, summary

    var next: OnbStep? { OnbStep(rawValue: rawValue + 1) }
    var previous: OnbStep? { OnbStep(rawValue: rawValue - 1) }

    /// Progress index excluding the welcome splash (for the dot indicator).
    var progressIndex: Int { max(0, rawValue - 1) }
    static var progressTotal: Int { allCases.count - 1 }
}
