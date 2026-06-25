//
//  CapModels.swift
//  MyGutGarden — Module B (Capture + recognition UX). Pure value types for the
//  snap → recognize → confirm flow (SPEC §4, §11). No SwiftUI, no networking
//  here — these are the small, testable pieces the view-model + persistence
//  layer compose. Public types are `Cap`-prefixed per the module contract.
//

import Foundation

// MARK: - Errors

enum CapError: LocalizedError {
    case notSignedIn
    case captureUnavailable
    case captureFailed
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to log this meal. Your photo and progress sync to your account."
        case .captureUnavailable:
            return "No camera here. Pick a photo from your library, or try the sample meal."
        case .captureFailed:
            return "That photo didn't come through. Try the shot again."
        case let .uploadFailed(detail):
            return "Couldn't save the photo (\(detail)). Logging the meal without it."
        }
    }
}

// MARK: - meal_items provenance (SPEC §5: source vision | manual | hidden_confirmed)

/// Where a logged item came from. Mirrors the `meal_items.source` enum exactly.
enum CapItemSource: String, Sendable, Equatable {
    case vision                              // the vision model identified it
    case manual                              // the user corrected an unmatched item
    case hiddenConfirmed = "hidden_confirmed" // the user confirmed an always-ask prompt
}

/// One row destined for `meal_items` (SPEC §5). Portion stays a coarse tier —
/// never a precise gram value surfaced as measured (CLAUDE.md rule #3). The
/// optional `est_fiber_g` column is deliberately left unset here: Module B does
/// not invent nutrition numbers (rule #2).
struct CapMealItem: Sendable, Equatable {
    let foodId: String
    let portion: PortionTier
    let source: CapItemSource
}

// MARK: - Food search (manual-confirm + hidden-ingredient resolution)

/// A candidate food the user can pick to resolve an unmatched guess or a
/// confirmed hidden ingredient. Decoded from `foods` (id + canonical_name).
struct CapFoodSearchResult: Identifiable, Sendable, Equatable, Decodable {
    let id: String
    let canonicalName: String
}

// MARK: - Manual confirm (SPEC §4 step 4 — unmatched items flagged for confirm)

/// An item the vision model named but the database could not resolve. The user
/// searches and picks the real food, or leaves it unresolved (we never log a
/// guess we aren't sure of — "when unsure, flag it", §4).
struct CapUnmatchedItem: Identifiable, Sendable, Equatable {
    let visionName: String                 // the model's best guess (what we show)
    var resolvedFood: CapFoodSearchResult? // the food the user picked (nil = skip)
    var portion: PortionTier = .serving    // coarse; user can adjust in review

    var id: String { visionName }
    var isResolved: Bool { resolvedFood != nil }
}

// MARK: - Hidden-ingredient prompts (SPEC §4 step 6, §11 — always-ask yes/no)

/// One always-ask hidden-ingredient question and the user's definite answer
/// ("this dish often contains onion — was it?"). `wasPresent == nil` means the
/// user hasn't answered yet; "always ask" means we want a real yes or no.
struct CapHiddenIngredientAnswer: Identifiable, Sendable {
    let prompt: HiddenIngredientPrompt   // HiddenIngredientPrompt isn't Equatable upstream
    var wasPresent: Bool?

    var id: String { prompt.id }
}

/// A hidden ingredient the user confirmed AND that resolved to a real food —
/// becomes a `hidden_confirmed` meal_item. A coarse default portion is used
/// because hidden aromatics aren't visible to size (rule #3).
struct CapResolvedHidden: Sendable, Equatable {
    let foodId: String
    var portion: PortionTier = .serving
}

// MARK: - The assembled draft handed to persistence

/// Everything Module B needs to persist one confirmed meal (SPEC §5 `meals` +
/// `meal_items`) and hand off to the mode-specific insight view (the
/// `ConfirmedMeal` seam). Built purely from the review state; no I/O.
struct CapMealDraft: Sendable {
    let mode: AppMode
    let photoURL: String?
    let response: RecognitionResponse
    let items: [CapMealItem]
    let hiddenAnswers: [CapHiddenIngredientAnswer]
    let capturedAt: Date
}
