//
//  OnbViewModel.swift
//  MyGutGarden, Module A: the intake flow state + persistence (SPEC §6, §10).
//
//  Holds every captured field, derives the fiber goal via the PURE OnbFiberGoal,
//  and writes through AppState.repository. Reads/writes the shared data model
//  only, never re-styles UI, never displays `est_daily_kcal`.
//
//  Phase-2 (Batch B):
//    - unitSystem toggle (metric/US display only; canonical storage cm/kg)
//    - age always captured via ageValue (no shareAge toggle)
//    - plantConsumptionLevel added; fiber goal multiplied accordingly
//    - bowelConsistency baseline added
//    - mood stored CANONICAL high=better via 6 - uiValue (see usersWriteBody)
//    - otherAutoimmune serious condition writes users.other_autoimmune
//    - Survive path writes residue_ceiling_g (INTERNAL), no fiber_goal_g
//    - Thrive path writes fiber_goal_g; plant_consumption_level always written
//    - toggleCategoryExclusion supports deselecting a chip
//    - food search filter fixed to ilike.%q% (PostgREST standard wildcard)
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

    // MARK: Body basics. Pre-filled with neutral medians so the goal is always
    // derivable; the user adjusts. Never framed as a weight-loss target (§10).

    /// Unit system for display only. Storage is always cm/kg.
    var unitSystem: UnitSystem = .metric

    var heightCm: Double = 170
    var weightKg: Double = 70

    // Phase-2 (Batch B): age is always captured via the wheel picker (no toggle).
    // The "Optional" callout in the UI is informational, not a gate.
    var ageValue: Int = 30

    var sex: OnbSex = .unspecified
    var activity: OnbActivityLevel = .moderate

    /// Phase-2 (Batch B): plant-food consumption level, drives the fiber-goal multiplier.
    /// Always written (universal isOnboarded marker).
    var plantConsumptionLevel: PlantConsumptionTier = .moderate

    var baseline = OnbBaseline()

    // The two-faced exclusion model (§9), scope + type kept distinct, never flattened.
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

    // MARK: - Derived (SPEC §10, Phase-2 Batch B)

    /// Holds `estDailyKcal` (INTERNAL ONLY), `baseFiberGoalG` (INTERNAL ONLY),
    /// and `fiberGoalG` (the ONE surfaced number, Thrive only). Views read ONLY
    /// `.fiberGoalG`, and only on the Thrive summary screen.
    var derivation: OnbFiberGoal.Derivation {
        OnbFiberGoal.derive(heightCm: heightCm, weightKg: weightKg,
                            age: ageValue,
                            sex: sex, activity: activity,
                            plantConsumptionLevel: plantConsumptionLevel)
    }

    /// The single surfaced number from the body step (grams, Thrive only).
    var fiberGoalG: Int { derivation.fiberGoalG }

    // MARK: - Soft routing (SPEC §6)

    var hasReliefSignal: Bool { !redFlags.isEmpty || !seriousConditions.isEmpty }
    var suggestedMode: AppMode { OnbRouting.suggestedMode(goals: goals, hasReliefSignal: hasReliefSignal) }
    var chosenMode: AppMode { chosenModeOverride ?? suggestedMode }

    // MARK: - Mutations

    func toggleGoal(_ goal: OnbGoal) {
        if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) }
    }

    /// Phase-2 (Batch B): toggle-style add/remove so tapping a selected chip deselects it.
    func toggleCategoryExclusion(_ category: OnbExclusionCategory) {
        let scope = OnbExclusionScope.category(key: category.key, label: category.label)
        if exclusions.contains(where: { $0.scope == scope }) {
            exclusions.removeAll { $0.scope == scope }
        } else {
            addCategoryExclusion(key: category.key, label: category.label, type: category.suggestedType)
        }
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

    /// Celiac -> propose a LOUD gluten exclusion (medical_allergy, §9). Called on
    /// acknowledgment; removable, never silently collapsed.
    /// otherAutoimmune: NO universal exclusion proposed (Phase-2 Batch B).
    func acknowledgeSeriousConditions() {
        if seriousConditions.contains(OnbSeriousCondition.celiac.key) {
            addCategoryExclusion(key: "gluten", label: "Gluten / wheat", type: .medicalAllergy)
        }
        // other_autoimmune and ibd: noted via users.other_autoimmune / goals, no food exclusion.
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

    /// Phase-2 (Batch B): food search uses ilike.%q% (PostgREST standard SQL wildcard).
    /// The old ilike.*q* did not work with PostgREST's filter encoding.
    func searchFoods() async {
        let q = foodQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let repo = appState.repository else { foodHits = []; return }
        let hits: [OnbFoodHit]? = try? await repo.select(
            "foods", columns: "id,canonical_name",
            filters: ["canonical_name": "ilike.%\(q)%"], limit: 8)
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
                // Each exclusion written with its OWN type, never merged (§9).
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

    /// The `users` PATCH body.
    ///
    /// DUTY-OF-CARE notes:
    ///   - `est_daily_kcal`: INTERNAL column; written but never displayed (Fence 5).
    ///   - `baseline_mood`: CANONICAL high=better. The UI now shows Regulated(1)..Erratic(5),
    ///     which is INVERTED from high=better. We store `6 - baseline.mood` so the pattern
    ///     engine (which expects high=better, 5=regulated) is never aware of the UI polarity.
    ///     This is the SINGLE inversion point for onboarding baseline mood.
    ///   - Thrive: writes `fiber_goal_g` (the only surfaced number, SPEC §10).
    ///     TODO: Fiber auto-increase is a coordinator job (MealIngestion), not onboarding.
    ///   - Survive: writes `residue_ceiling_g` (INTERNAL ONLY, never surfaced or decoded
    ///     into UserProfile, like est_daily_kcal). Does NOT write fiber_goal_g.
    ///   - `plant_consumption_level`: ALWAYS written (universal isOnboarded marker checked
    ///     by AppState.isOnboarded for the Survive branch).
    private func usersWriteBody() -> [String: PGValue] {
        let d = derivation
        var body: [String: PGValue] = [
            "height_cm":      .double(heightCm),
            "weight_kg":      .double(weightKg),
            "age":            .int(ageValue),
            "sex":            sex.dbValue.map(PGValue.string) ?? .null,
            "activity_level": .string(activity.rawValue),
            "est_daily_kcal": .double(d.estDailyKcal),   // INTERNAL ONLY, never displayed (Fence 5)

            // MOOD CANONICAL INVERSION (Phase-2 Batch B, single point):
            // UI shows Regulated(1=best)..Erratic(5=worst); canonical is high=better.
            // Stored as 6 - uiValue so 1 (Regulated/best) -> 5 (stored best).
            "baseline_mood":             .int(6 - baseline.mood),
            "baseline_energy":           .int(baseline.energy),
            "baseline_clarity":          .int(baseline.clarity),
            "baseline_bowel_consistency": .int(baseline.bowelConsistency),

            "goals":         .stringArray(goals.map(\.rawValue).sorted()),
            "current_mode":  .string(chosenMode.rawValue),

            // plant_consumption_level is always written: it is the universal
            // isOnboarded marker (AppState checks fiberGoalG != nil OR plantConsumptionLevel != nil).
            "plant_consumption_level": .string(plantConsumptionLevel.rawValue),

            // other_autoimmune: true if the user flagged it in Q5.
            "other_autoimmune": .bool(seriousConditions.contains(OnbSeriousCondition.otherAutoimmune.key)),
        ]

        if chosenMode == .survive {
            // Survive: write residue_ceiling_g (INTERNAL ONLY, never surfaced or decoded
            // into UserProfile). Do NOT write fiber_goal_g (stays null for Survive users).
            body["residue_ceiling_g"] = .int(GameConfig.shared.surviveResidueCeilingStartG)
            // TODO: fiber auto-increase is handled by coordinator (MealIngestion), not here.
        } else {
            // Thrive: write the plant-adjusted fiber goal. The ONLY surfaced derived number.
            body["fiber_goal_g"] = .int(d.fiberGoalG)
        }

        return body
    }
}

// MARK: - Steps

/// The intake sequence (SPEC §6). Welcome leads with Thrive's fun (never opens
/// "how's your gut?"); body basics stay away from any number-framing; the fiber
/// goal is revealed as a gain on the summary (Thrive only).
enum OnbStep: Int, CaseIterable, Hashable {
    case welcome, goals, body, baseline, exclusions, checks, summary

    var next: OnbStep? { OnbStep(rawValue: rawValue + 1) }
    var previous: OnbStep? { OnbStep(rawValue: rawValue - 1) }

    /// Progress index excluding the welcome splash (for the dot indicator).
    var progressIndex: Int { max(0, rawValue - 1) }
    static var progressTotal: Int { allCases.count - 1 }
}
