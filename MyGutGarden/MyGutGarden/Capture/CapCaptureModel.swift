//
//  CapCaptureModel.swift
//  MyGutGarden, Module B flow controller (SPEC §4, §11).
//
//  Drives the Batch C snap pipeline: capture → PREVIEW (accept / retake / annotate
//  before any analysis) → recognizing → AUTO-LOG → confirmed insight. The blocking
//  review step is gone: a meal is persisted automatically on recognition success,
//  WITHOUT forcing the user through the question/serving steps. Those (hidden
//  ingredients, manual corrections, relative amounts) move to the non-blocking
//  edit sheet, opened from the confirmed screen.
//
//  It composes the pure assembly helpers and the I/O services; the views stay thin.
//  Offline-safe: with no backend configured it runs the bundled fixture end to end
//  (CLAUDE.md Phase-0 exit criteria), skipping upload + persistence.
//

import Foundation
import Observation

@MainActor
@Observable
final class CapCaptureModel {

    enum Phase: Equatable {
        case capture        // choose a photo source
        case preview        // NEW (Batch C): accept / retake / annotate before analysis
        case recognizing    // uploading + calling the pipeline
        case confirmed      // logged, show the mode-specific insight
    }

    private(set) var phase: Phase = .capture
    var errorText: String?

    // Preview state (Batch C)
    private(set) var stagedImage: Data?     // the snapped photo awaiting accept (nil = sample meal)
    var userAnnotation: String = ""         // the snapchat-style note (bound by the overlay)

    // Recognize result + review/edit state
    private(set) var response: RecognitionResponse?
    private(set) var annotationFoodIds: Set<String> = []   // food_ids the note added (source='annotation')
    var hiddenAnswers: [CapHiddenIngredientAnswer] = []
    var unmatchedItems: [CapUnmatchedItem] = []

    // Outputs
    private(set) var confirmedMeal: ConfirmedMeal?
    private(set) var persistedMealId: String?     // the DB meals.id (nil offline) - drives the edit flow
    private(set) var isSaving = false

    private let appState: AppState
    private let recognizer: RecognitionService
    private var photoURL: String?
    private var capturedAt = Date()

    init(appState: AppState, recognizer: RecognitionService) {
        self.appState = appState
        self.recognizer = recognizer
    }

    /// Allergy alerts are LOUD (§9): rendered BEFORE any insight content and never
    /// suppressed. Server-computed from the user's `food_flags` (flag_tier=allergy).
    var allergyAlerts: [AllergyAlert] { response?.allergyAlerts ?? [] }

    /// Soft, in-overview sensitivity heads-up (§9). The food is still eaten +
    /// logged; this only reminds the user it's on their watch list. Server-computed
    /// from `food_flags` (flag_tier=sensitivity).
    var sensitivityFlags: [SensitivityFlag] { response?.sensitivityFlags ?? [] }

    var canConfirm: Bool {
        // Retained for the (non-blocking) edit flow's hidden-ingredient gate; the
        // auto-log path does not gate on it.
        CapHiddenIngredients.allAnswered(hiddenAnswers)
    }

    // MARK: - Capture → preview (Batch C: accept/retake before analysis)

    /// A real photo (camera or library): stage it for the accept/retake preview.
    func stage(imageData: Data) {
        stagedImage = imageData
        userAnnotation = ""
        errorText = nil
        phase = .preview
    }

    /// The no-camera / demo path: stage a sample meal (no image → fixture).
    func useSampleMeal() {
        stagedImage = nil
        userAnnotation = ""
        errorText = nil
        phase = .preview
    }

    /// Retake (the preview's top-left ✕): discard the photo + note, back to capture.
    func retake() {
        stagedImage = nil
        userAnnotation = ""
        errorText = nil
        phase = .capture
    }

    /// Accept (the preview's top-right ✓): run recognition, then AUTO-LOG.
    func accept() async {
        await analyzeAndLog(imageData: stagedImage)
    }

    private func analyzeAndLog(imageData: Data?) async {
        phase = .recognizing
        errorText = nil
        photoURL = nil
        capturedAt = Date()
        persistedMealId = nil

        // Best-effort upload; a flaky photo upload never blocks logging a meal.
        if let imageData,
           let token = appState.auth.session?.accessToken,
           let userId = appState.auth.session?.user?.id {
            do {
                photoURL = try await CapStorageUploader()
                    .upload(imageData: imageData, userId: userId, accessToken: token)
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }

        // The annotated path carries the note (→ server's second, text-only call)
        // through the Capture-owned client; the un-annotated path keeps using the
        // injected spine recognizer unchanged.
        let trimmedNote = userAnnotation.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmedNote.isEmpty {
                await recognizer.recognize(auth: appState.auth,
                                           imageBase64: imageData?.base64EncodedString())
                guard let recognized = recognizer.lastResponse else {
                    throw CapError.captureFailed
                }
                response = recognized
                annotationFoodIds = []
            } else {
                let result = try await CapRecognizer().recognize(
                    accessToken: appState.auth.session?.accessToken,
                    imageBase64: imageData?.base64EncodedString(),
                    userAnnotation: trimmedNote
                )
                response = result.response
                annotationFoodIds = result.annotationFoodIds
            }
        } catch {
            errorText = recognizer.errorMessage
                ?? (error as? LocalizedError)?.errorDescription
                ?? "Recognition didn't return anything. Try again."
            phase = .preview      // keep the photo + note so the user can retry
            return
        }

        // Prime the (deferred) edit-only review state from the response.
        if let recognized = response {
            hiddenAnswers = CapHiddenIngredients.initialAnswers(recognized)
            unmatchedItems = CapManualConfirm.initialItems(recognized)
        }

        await confirm()
    }

    // MARK: - Auto-log (persist meals + meal_items, no question/serving gate)

    /// Assembles the draft from the recognized (vision + annotation) items,
    /// persists the meal, and advances to the insight hand-off. Food restrictions
    /// (allergy/sensitivity) are server-computed and carried on `response`; there
    /// is no client-side food-status pass.
    func confirm() async {
        guard let response else { return }
        isSaving = true
        defer { isSaving = false }

        // Auto-log items: the recognized (vision + annotation) set. Manual + hidden
        // corrections are deferred to the edit sheet, so they're empty here.
        let hiddenItems = await resolveConfirmedHidden()
        let items = CapMealDraftBuilder.allItems(
            vision: CapMealDraftBuilder.visionItems(response, annotationFoodIds: annotationFoodIds),
            manual: CapMealDraftBuilder.manualItems(unmatchedItems),
            hidden: hiddenItems
        )

        let draft = CapMealDraft(
            photoURL: photoURL,
            response: response,
            items: items,
            hiddenAnswers: hiddenAnswers,
            capturedAt: capturedAt,
            userAnnotation: userAnnotation
        )

        // Persist when online; offline the flow still completes (fixture demo).
        if let repo = appState.repository, let userId = appState.auth.session?.user?.id {
            do {
                persistedMealId = try await CapMealPersistence(repository: repo, userId: userId).persist(draft)
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }

        confirmedMeal = ConfirmedMeal(
            id: UUID(),
            response: response,
            capturedAt: capturedAt
        )

        phase = .confirmed
    }

    // MARK: - Edit (non-blocking, opened from the confirmed screen)

    /// True once a meal is persisted (offline meals can't be edited).
    var canEditMeal: Bool { persistedMealId != nil && appState.repository != nil }

    /// Build the editor for the just-logged meal, carrying the deferred
    /// hidden-ingredient prompts so they reappear there (SPEC §4).
    func makeEditModel() -> CapEditMealModel? {
        guard let repo = appState.repository,
              let userId = appState.auth.session?.user?.id,
              let mealId = persistedMealId else { return nil }
        return CapEditMealModel(
            repository: repo,
            userId: userId,
            mealId: mealId,
            deferredHiddenPrompts: response?.hiddenIngredientPrompts ?? []
        )
    }

    // MARK: - Review/edit interactions (retained for the edit flow)

    func setHiddenAnswer(_ answer: CapHiddenIngredientAnswer, wasPresent: Bool) {
        guard let idx = hiddenAnswers.firstIndex(where: { $0.id == answer.id }) else { return }
        hiddenAnswers[idx].wasPresent = wasPresent
    }

    func resolveUnmatched(_ item: CapUnmatchedItem, with food: CapFoodSearchResult) {
        guard let idx = unmatchedItems.firstIndex(where: { $0.id == item.id }) else { return }
        unmatchedItems[idx].resolvedFood = food
    }

    func setUnmatchedPortion(_ item: CapUnmatchedItem, portion: PortionTier) {
        guard let idx = unmatchedItems.firstIndex(where: { $0.id == item.id }) else { return }
        unmatchedItems[idx].portion = portion
    }

    func clearUnmatched(_ item: CapUnmatchedItem) {
        guard let idx = unmatchedItems.firstIndex(where: { $0.id == item.id }) else { return }
        unmatchedItems[idx].resolvedFood = nil
    }

    /// Live food search for the manual-confirm / add-item picker.
    func searchFoods(_ term: String) async -> [CapFoodSearchResult] {
        guard let repo = appState.repository else { return [] }
        return (try? await CapFoodSearchService(repository: repo).search(term)) ?? []
    }

    /// Resolve each confirmed-present hidden ingredient to a `food_id` so it can
    /// be logged as a `hidden_confirmed` item. Empty on the auto-log path (no
    /// prompts answered yet); used by the edit flow.
    private func resolveConfirmedHidden() async -> [CapMealItem] {
        guard let repo = appState.repository else { return [] }
        let search = CapFoodSearchService(repository: repo)
        var resolved: [CapResolvedHidden] = []
        for name in CapHiddenIngredients.confirmedPresentFoodNames(hiddenAnswers) {
            if let match = try? await search.bestMatch(for: name) {
                resolved.append(CapResolvedHidden(foodId: match.id))
            }
        }
        return CapMealDraftBuilder.hiddenConfirmedItems(resolved)
    }

    // MARK: - Reset

    /// Back to the start for another snap (used by the result screen's ✕ + "Snap another").
    func reset() {
        phase = .capture
        errorText = nil
        response = nil
        annotationFoodIds = []
        hiddenAnswers = []
        unmatchedItems = []
        confirmedMeal = nil
        persistedMealId = nil
        stagedImage = nil
        userAnnotation = ""
        photoURL = nil
    }
}
