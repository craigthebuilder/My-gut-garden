//
//  OnbViewModel.swift
//  MyGutGarden — Module A: the intake flow state + persistence (SPEC §6, §10).
//
//  Holds every captured field, derives the fiber goal via the PURE OnbFiberGoal,
//  and writes through AppState.repository. Reads/writes the shared data model
//  only — never re-styles UI, never displays `est_daily_kcal`.
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

    // Body basics. Pre-filled with neutral medians so the goal is always
    // derivable; the user adjusts. ⚠️ Never framed as a weight-loss target (§10).
    var heightCm: Double = 170
    var weightKg: Double = 70
    var shareAge: Bool = false
    var ageValue: Int = 30
    var sex: OnbSex = .unspecified
    var activity: OnbActivityLevel = .moderate
    /// nil when the user declines to share — handled by OnbFiberGoal.
    var age: Int? { shareAge ? ageValue : nil }

    var baseline = OnbBaseline()

    // The two-faced exclusion model (§9) — scope + type kept distinct, never flattened.
    var exclusions: [OnbDraftExclusion] = []
    var foodQuery: String = ""
    var foodHits: [OnbFoodHit] = []

    // Disclaimer signals (drive modals, never blocks).
    var seriousConditions: Set<String> = []   // OnbSeriousCondition.key
    var redFlags: Set<String> = []            // OnbRedFlag.key

    // Social proof.
    var successStories: [OnbSuccessStory] = []

    // Mode choice: starts from the soft suggestion, user can override on summary.
    var chosenModeOverride: AppMode?

    // Status.
    var isSaving = false
    var errorMessage: String?
    var didFinish = false

    init(appState: AppState) { self.appState = appState }

    // MARK: - Derived (SPEC §10)

    /// ⚠️ Holds `estDailyKcal` (INTERNAL ONLY) + `fiberGoalG` (surfaced). Views
    /// read ONLY `.fiberGoalG`.
    var derivation: OnbFiberGoal.Derivation {
        OnbFiberGoal.derive(heightCm: heightCm, weightKg: weightKg, age: age,
                            sex: sex, activity: activity)
    }

    /// The single surfaced number from the body step (grams).
    var fiberGoalG: Int { derivation.fiberGoalG }

    // MARK: - Soft routing (SPEC §6)

    var hasReliefSignal: Bool { !redFlags.isEmpty || !seriousConditions.isEmpty }
    var suggestedMode: AppMode { OnbRouting.suggestedMode(goals: goals, hasReliefSignal: hasReliefSignal) }
    var chosenMode: AppMode { chosenModeOverride ?? suggestedMode }

    // MARK: - Mutations

    func toggleGoal(_ goal: OnbGoal) {
        if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) }
    }

    func addCategoryExclusion(_ category: OnbExclusionCategory) {
        addCategoryExclusion(key: category.key, label: category.label, type: category.suggestedType)
    }

    func addCategoryExclusion(key: String, label: String, type: ExclusionType) {
        let scope = OnbExclusionScope.category(key: key, label: label)
        guard !exclusions.contains(where: { $0.scope == scope }) else { return }
        exclusions.append(OnbDraftExclusion(scope: scope, exclusionType: type))
    }

    func addFoodExclusion(_ hit: OnbFoodHit) {
        let scope = OnbExclusionScope.food(id: hit.id, name: hit.canonicalName)
        guard !exclusions.contains(where: { $0.scope == scope }) else { return }
        // Default a specific food to the quiet type; the user escalates to allergy.
        exclusions.append(OnbDraftExclusion(scope: scope, exclusionType: .preferenceIntolerance))
        foodQuery = ""
        foodHits = []
    }

    func removeExclusion(_ id: OnbDraftExclusion.ID) {
        exclusions.removeAll { $0.id == id }
    }

    func toggleSeriousCondition(_ condition: OnbSeriousCondition) {
        if seriousConditions.contains(condition.key) { seriousConditions.remove(condition.key) }
        else { seriousConditions.insert(condition.key) }
    }

    func toggleRedFlag(_ flag: OnbRedFlag) {
        if redFlags.contains(flag.key) { redFlags.remove(flag.key) } else { redFlags.insert(flag.key) }
    }

    /// Celiac → propose a LOUD gluten exclusion (medical_allergy, §9). Called on
    /// acknowledgment; removable, never silently collapsed.
    func acknowledgeSeriousConditions() {
        if seriousConditions.contains(OnbSeriousCondition.celiac.key) {
            addCategoryExclusion(key: "gluten", label: "Gluten / wheat", type: .medicalAllergy)
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

    /// Truthful, representative only — prefer verified; hide the section if none.
    func loadSuccessStories() async {
        guard successStories.isEmpty, let repo = appState.repository else { return }
        let rows: [OnbSuccessStory]? = try? await repo.select(
            "success_stories", order: "verified.desc", limit: 2)
        if let rows { successStories = rows }
    }

    func searchFoods() async {
        let q = foodQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let repo = appState.repository else { foodHits = []; return }
        let hits: [OnbFoodHit]? = try? await repo.select(
            "foods", columns: "id,canonical_name",
            filters: ["canonical_name": "ilike.*\(q)*"], limit: 8)
        foodHits = hits ?? []
    }

    /// Persist intake, derive + store the fiber goal (and internal kcal), write
    /// the two-faced exclusions, set the chosen mode. Completes locally when
    /// offline/demo so the flow never dead-ends.
    func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        if let repo = appState.repository, let uid = appState.auth.user?.id {
            do {
                try await repo.update("users", set: usersWriteBody(), filters: ["id": "eq.\(uid)"])
                // Each exclusion written with its OWN type — never merged (§9).
                for draft in exclusions {
                    try await repo.insertVoid("exclusions",
                                              OnbExclusionWriter.insertBody(userId: uid, draft: draft))
                }
                await appState.refreshProfile()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
        }
        didFinish = true
    }

    /// The `users` PATCH body. ⚠️ `est_daily_kcal` is written here (internal
    /// column) but NEVER surfaced; only `fiber_goal_g` is ever shown (SPEC §10).
    private func usersWriteBody() -> [String: PGValue] {
        let d = derivation
        return [
            "height_cm":      .double(heightCm),
            "weight_kg":      .double(weightKg),
            "age":            age.map(PGValue.int) ?? .null,
            "sex":            sex.dbValue.map(PGValue.string) ?? .null,
            "activity_level": .string(activity.rawValue),
            "est_daily_kcal": .double(d.estDailyKcal),   // INTERNAL ONLY — never displayed
            "fiber_goal_g":   .int(d.fiberGoalG),         // the only surfaced derived number
            "baseline_mood":    .int(baseline.mood),
            "baseline_energy":  .int(baseline.energy),
            "baseline_clarity": .int(baseline.clarity),
            "goals":          .stringArray(goals.map(\.rawValue).sorted()),
            "current_mode":   .string(chosenMode.rawValue),
        ]
    }
}

// MARK: - Steps

/// The intake sequence (SPEC §6). Welcome leads with Thrive's fun (never opens
/// "how's your gut?"); body basics stay away from any number-framing; the fiber
/// goal is revealed as a gain on the summary.
enum OnbStep: Int, CaseIterable, Hashable {
    case welcome, goals, body, baseline, exclusions, checks, summary

    var next: OnbStep? { OnbStep(rawValue: rawValue + 1) }
    var previous: OnbStep? { OnbStep(rawValue: rawValue - 1) }

    /// Progress index excluding the welcome splash (for the dot indicator).
    var progressIndex: Int { max(0, rawValue - 1) }
    static var progressTotal: Int { allCases.count - 1 }
}
