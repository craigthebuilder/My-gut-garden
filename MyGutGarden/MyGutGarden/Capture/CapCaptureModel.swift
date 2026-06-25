//
//  CapCaptureModel.swift
//  MyGutGarden — Module B flow controller (SPEC §4, §11).
//
//  Drives the snap → recognize → review → confirm pipeline and owns all the
//  review-screen state (hidden-ingredient answers, unmatched corrections). It
//  composes the pure assembly helpers and the I/O services; the views stay thin.
//  Offline-safe: with no backend configured it runs the bundled fixture end to
//  end (CLAUDE.md Phase-0 exit criteria), skipping upload + persistence.
//

import Foundation
import Observation

@MainActor
@Observable
final class CapCaptureModel {

    enum Phase: Equatable {
        case capture        // choose a photo source
        case recognizing    // uploading + calling the pipeline
        case review         // confirm / correct before logging
        case confirmed      // logged — show the mode-specific insight
    }

    private(set) var phase: Phase = .capture
    var errorText: String?

    // Recognize result + review state
    private(set) var response: RecognitionResponse?
    var hiddenAnswers: [CapHiddenIngredientAnswer] = []
    var unmatchedItems: [CapUnmatchedItem] = []

    // Outputs
    private(set) var confirmedMeal: ConfirmedMeal?
    private(set) var isSaving = false

    private let appState: AppState
    private let recognizer: RecognitionService
    private var photoURL: String?
    private var capturedAt = Date()

    init(appState: AppState, recognizer: RecognitionService) {
        self.appState = appState
        self.recognizer = recognizer
    }

    var mode: AppMode { appState.mode }

    /// Allergy alerts are LOUD across both modes (§9) — surfaced wherever review
    /// renders, never suppressed mid-flow.
    var allergyAlerts: [AllergyAlert] { response?.allergyAlerts ?? [] }

    var canConfirm: Bool {
        // "Always ask": every hidden-ingredient prompt needs a definite yes/no
        // before we log. Unmatched items may be left unresolved (skipping is OK).
        CapHiddenIngredients.allAnswered(hiddenAnswers)
    }

    // MARK: - Capture entry points

    /// A real photo (camera or library): upload best-effort, then recognize.
    func submit(imageData: Data) async {
        await run(imageData: imageData)
    }

    /// The no-camera / demo path: no image → the pipeline uses the fixture, and
    /// we skip upload + (later) persistence has no photo to attach.
    func useSampleMeal() async {
        await run(imageData: nil)
    }

    private func run(imageData: Data?) async {
        phase = .recognizing
        errorText = nil
        photoURL = nil
        capturedAt = Date()

        // Best-effort upload — a flaky photo upload never blocks logging a meal.
        // A live access token + user id mean we're online + signed in.
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

        await recognizer.recognize(mode: mode, auth: appState.auth,
                                   imageBase64: imageData?.base64EncodedString())

        if let recognized = recognizer.lastResponse {
            response = recognized
            hiddenAnswers = CapHiddenIngredients.initialAnswers(recognized)
            unmatchedItems = CapManualConfirm.initialItems(recognized)
            phase = .review
        } else {
            errorText = recognizer.errorMessage ?? "Recognition didn't return anything. Try again."
            phase = .capture
        }
    }

    // MARK: - Review interactions

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

    /// Live food search for the manual-confirm picker.
    func searchFoods(_ term: String) async -> [CapFoodSearchResult] {
        guard let repo = appState.repository else { return [] }
        return (try? await CapFoodSearchService(repository: repo).search(term)) ?? []
    }

    // MARK: - Confirm

    /// Assembles the draft, persists it (when online), builds the `ConfirmedMeal`
    /// seam, and advances to the insight hand-off.
    func confirm() async {
        guard let response else { return }
        isSaving = true
        defer { isSaving = false }

        let hiddenItems = await resolveConfirmedHidden()
        let items = CapMealDraftBuilder.allItems(
            vision: CapMealDraftBuilder.visionItems(response),
            manual: CapMealDraftBuilder.manualItems(unmatchedItems),
            hidden: hiddenItems
        )

        let draft = CapMealDraft(
            mode: mode,
            photoURL: photoURL,
            response: response,
            items: items,
            hiddenAnswers: hiddenAnswers,
            capturedAt: capturedAt
        )

        // Persist when online; offline the flow still completes (fixture demo).
        if let repo = appState.repository, let userId = appState.auth.session?.user?.id {
            do {
                try await CapMealPersistence(repository: repo, userId: userId).persist(draft)
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }

        confirmedMeal = ConfirmedMeal(id: UUID(), response: response, capturedAt: capturedAt)
        phase = .confirmed
    }

    /// Resolve each confirmed-present hidden ingredient to a `food_id` so it can
    /// be logged as a `hidden_confirmed` item. Unresolvable names still keep
    /// their yes/no in `hidden_ingredient_answers`; only the meal_item is skipped.
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

    /// Back to the start for another snap (used by the result screen).
    func reset() {
        phase = .capture
        errorText = nil
        response = nil
        hiddenAnswers = []
        unmatchedItems = []
        confirmedMeal = nil
        photoURL = nil
    }
}
