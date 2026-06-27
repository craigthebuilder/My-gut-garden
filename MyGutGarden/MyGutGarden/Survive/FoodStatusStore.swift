//
//  FoodStatusStore.swift
//  MyGutGarden, Module E. The SHARED food-status store + engine (Batch E).
//
//  This is the "Lab Notebook": one `food_suspects` row per (user, food); four
//  tabs are four queries over it. The user is the scientist, the app is the
//  notebook, it SUGGESTS, it never concludes. Both surfaces render it:
//    • Survive's Suspects / Re-intro / Timeline / Avoid tabs (Module E views),
//    • Thrive's ThrYourFoodsView (Module C reads this public API verbatim).
//
//  HARD INVARIANTS encoded here (CLAUDE.md rules #1/#4/#7):
//   • NO severity / score / confidence / "problem-foods" meter, anywhere. Only
//     neutral bucket counts. `consecutive_unwell_count` is an UNSURFACED gate.
//   • The app auto-WRITES only the system SUGGESTION and the POSITIVE clear.
//     Every negative commit (confirm-suspect, move-to-Avoid, deny) is a user tap.
//   • The reintro bar is EVENT-DRIVEN (felt-fine meals), NEVER time-based. We
//     never read elapsed time / reintroChallengeDays for food_suspect challenges.
//   • `avoid` is NOT an exclusion_type and is never merged into `exclusions`.
//   • A `medical_allergy` food can never be added as a suspect (it stays LOUD).
//   • Reintro thresholds are RD-REVIEW-REQUIRED (Fence 3, see GameConfig).
//

import Foundation
import Observation

@MainActor
@Observable
final class FoodStatusStore {
    private let repository: Repository
    private let userId: String
    private let appState: AppState
    private let config = GameConfig.shared

    // MARK: Public, observed state (Thrive + Survive read these)

    private(set) var suspects: [FoodSuspectRow] = []
    /// The user's single active food_suspect challenge (one-at-a-time, DB-enforced).
    private(set) var activeFoodChallenge: ReintroChallengeRow?

    // MARK: Internal supporting state

    /// All food_suspect challenges (active + history) for the Timeline.
    private(set) var foodChallenges: [ReintroChallengeRow] = []
    /// foodId -> canonical name, hydrated in `load()`.
    private var foodNames: [String: String] = [:]
    /// foodIds carrying an `exclusion_type='medical_allergy'` exclusion: the
    /// allergy block. (Category-only allergies aren't resolved to ids here, see
    /// the integration note, the LOUD camera pass still covers those.)
    private(set) var medicalAllergyFoodIds: Set<String> = []

    /// Surfaced after the bar auto-authors a POSITIVE clear, so the view can show
    /// the additive "you can enjoy it again" gain. NEVER "you got through it".
    private(set) var lastClearedFoodName: String?
    /// Set when a fine-but-trace meal records without advancing, so the view can
    /// show a coarse-tier titration nudge ("try a normal serving next time").
    private(set) var titrationFoodId: String?

    private(set) var isLoading = false
    var errorMessage: String?

    init(repository: Repository, userId: String, appState: AppState) {
        self.repository = repository
        self.userId = userId
        self.appState = appState
    }

    // MARK: - Names

    func foodName(_ foodId: String) -> String { foodNames[foodId] ?? "this food" }

    func isMedicalAllergy(_ foodId: String) -> Bool { medicalAllergyFoodIds.contains(foodId) }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let suspectRows: [FoodSuspectRow] = repository.select(
                "food_suspects", filters: ["user_id": "eq.\(userId)"], order: "created_at.asc")
            async let challengeRows: [ReintroChallengeRow] = repository.select(
                "reintro_challenges", filters: ["challenge_kind": "eq.food_suspect"])
            async let exclusionRows: [ExclusionRow] = repository.fetchExclusions()

            suspects = try await suspectRows
            foodChallenges = try await challengeRows
            activeFoodChallenge = foodChallenges.first { $0.status == "testing" }
            medicalAllergyFoodIds = Set(try await exclusionRows
                .filter { $0.exclusionType == .medicalAllergy }
                .compactMap { $0.foodId })

            await hydrateNames(for: suspects.map(\.foodId))
        } catch {
            errorMessage = "Couldn't load your food list. Pull to retry."
        }
    }

    /// Resolve canonical names for a set of food ids (only the missing ones).
    private func hydrateNames(for ids: [String]) async {
        let missing = Set(ids).subtracting(foodNames.keys)
        guard !missing.isEmpty else { return }
        let list = missing.joined(separator: ",")
        let hits: [FoodSearchHit]? = try? await repository.select(
            "foods", columns: "id,canonical_name", filters: ["id": "in.(\(list))"])
        for hit in hits ?? [] { foodNames[hit.id] = hit.canonicalName }
    }

    // MARK: - Derived buckets (the four tabs are four queries over one table)

    /// Dismissible "Worth a look?" tray: a pending SYSTEM suggestion only.
    func suggested() -> [FoodSuspectRow] {
        suspects.filter { $0.addedBy == "system" && $0.userVerdict == nil && $0.status == "suspect" }
    }

    /// Foods being kept an eye on (status=suspect, not set aside).
    func checking() -> [FoodSuspectRow] {
        suspects.filter { $0.status == "suspect" && !$0.avoid }
    }

    func reintroducing() -> [FoodSuspectRow] {
        suspects.filter { $0.status == "reintroducing" }
    }

    func avoided() -> [FoodSuspectRow] {
        suspects.filter { $0.avoid }
    }

    // MARK: - Food search (manual add)

    struct FoodSearchHit: Identifiable, Sendable, Decodable, Equatable {
        let id: String
        let canonicalName: String
    }

    /// Case-insensitive substring search for the manual "add a food" picker.
    func searchFoods(_ term: String, limit: Int = 12) async -> [FoodSearchHit] {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        let hits: [FoodSearchHit]? = try? await repository.select(
            "foods", columns: "id,canonical_name",
            filters: ["canonical_name": "ilike.%\(q)%"], order: "canonical_name", limit: limit)
        return hits ?? []
    }

    // MARK: - Suspect lifecycle (every NEGATIVE commit is a user tap)

    /// User adds a food via search. Caller ensures it is NOT a medical_allergy;
    /// we also guard defensively here (a confirm/deny flow would falsely imply
    /// uncertainty about an allergy that stays LOUD).
    func addSuspect(foodId: String) async {
        guard !isMedicalAllergy(foodId) else {
            errorMessage = "That's already flagged as an allergy, it stays loud."
            return
        }
        // Upsert so re-adding a previously cleared/denied food revives it cleanly.
        let body: [String: PGValue] = [
            "user_id": .string(userId), "food_id": .string(foodId),
            "added_by": .string("user"), "status": .string("suspect"),
            "user_verdict": .string("confirmed"), "avoid": .bool(false),
            "updated_at": .date(Date())
        ]
        await persist { try await repository.upsert("food_suspects", body, onConflict: "user_id,food_id") }
    }

    /// Accept a system suggestion: user authors it as a real suspect.
    func confirmSuggestion(_ s: FoodSuspectRow) async {
        await update(s, ["user_verdict": .string("confirmed")])
    }

    /// Dismiss a system suggestion: it never became a suspect.
    func denySuggestion(_ s: FoodSuspectRow) async {
        await update(s, ["status": .string("cleared"), "user_verdict": .string("denied")])
    }

    /// Remove a food from the list, cascading any active challenge to failed.
    func removeSuspect(_ s: FoodSuspectRow) async {
        if let ch = activeFoodChallenge, ch.suspectId == s.id || ch.foodId == s.foodId {
            await failChallenge(ch)
        }
        await update(s, ["status": .string("cleared")])
    }

    // MARK: - Challenge lifecycle (EVENT-DRIVEN, never time-based)

    /// Begin reintroducing a food. One at a time: any existing active food
    /// challenge is ended first (the UI also guards with "End [food] first?").
    func startChallenge(_ s: FoodSuspectRow) async {
        if let existing = activeFoodChallenge { await failChallenge(existing) }
        let body: [String: PGValue] = [
            "user_id": .string(userId),
            "challenge_kind": .string("food_suspect"),
            "food_id": .string(s.foodId),
            "suspect_id": .string(s.id),
            "status": .string("testing"),
            "meals_feeling_fine_count": .int(0),
            "consecutive_unwell_count": .int(0),
            "progress_pct": .int(0)
        ]
        await persist {
            try await repository.insertVoid("reintro_challenges", body)
            try await repository.update("food_suspects",
                set: ["status": .string("reintroducing"), "updated_at": .date(Date())],
                filters: ["id": "eq.\(s.id)"])
        }
    }

    /// End the active challenge early. The food returns to "checking" (still on
    /// the list, retry-able), the challenge is recorded as failed (no enum churn).
    func endActiveChallenge() async {
        guard let ch = activeFoodChallenge else { return }
        await failChallenge(ch)
    }

    private func failChallenge(_ ch: ReintroChallengeRow) async {
        await persist {
            try await repository.update("reintro_challenges",
                set: ["status": .string("failed"), "ended_at": .date(Date())],
                filters: ["id": "eq.\(ch.id)"])
            // The food drops back to "checking" so reintroducing() stays accurate.
            if let sid = ch.suspectId {
                try await repository.update("food_suspects",
                    set: ["status": .string("suspect"), "updated_at": .date(Date())],
                    filters: ["id": "eq.\(sid)"])
            }
        }
    }

    /// Record a meal containing the active reintro food and the user's "how did
    /// it feel?" answer. Drives the EVENT-DRIVEN bar:
    ///   • felt-fine AND portion >= reintroMinPortionToCount → +1, unwell reset to 0
    ///   • felt-fine BUT trace                              → records, no advance,
    ///                                                          shows a titration nudge
    ///   • rough                                            → no advance, +1 unwell gate
    /// At reintroMealsToPass felt-fine meals the POSITIVE clear is auto-authored.
    func recordReintroMeal(foodId: String, mealId: String?, portion: PortionTier, feltFine: Bool) async {
        guard let ch = activeFoodChallenge, ch.foodId == foodId else { return }
        titrationFoodId = nil

        // The meal-check row (only when tied to a real meal, meal_id is NOT NULL).
        if let mealId {
            let row: [String: PGValue] = [
                "user_id": .string(userId), "challenge_id": .string(ch.id),
                "meal_id": .string(mealId), "felt_fine": .bool(feltFine),
                "portion_tier": .string(portion.rawValue)
            ]
            try? await repository.insertVoid("reintro_meal_checks", row)
        }

        var fineCount = ch.mealsFeelingFineCount
        var unwell = ch.consecutiveUnwellCount
        let advances = feltFine && rank(portion) >= rank(config.reintroMinPortionToCount)

        if advances {
            fineCount += 1
            unwell = 0
        } else if feltFine {
            // Fine-but-trace: it counts as a gentle data point, not progress.
            titrationFoodId = foodId
        } else {
            // Rough: never advances; the unwell gate is CAPPED at threshold so it
            // can never grow into an accumulating "bad-guy" meter.
            unwell = min(config.avoidOfferAfterUnwellCount, unwell + 1)
        }

        let pct = min(100, fineCount * 100 / max(1, config.reintroMealsToPass))
        let cleared = fineCount >= config.reintroMealsToPass

        await persist {
            try await repository.update("reintro_challenges",
                set: ["meals_feeling_fine_count": .int(fineCount),
                      "consecutive_unwell_count": .int(unwell),
                      "progress_pct": .int(pct),
                      "status": .string(cleared ? "passed" : "testing"),
                      "ended_at": cleared ? .date(Date()) : .null],
                filters: ["id": "eq.\(ch.id)"])
            if cleared, let sid = ch.suspectId {
                // AUTO-AUTHORED POSITIVE CLEAR (the one negative-adjacent transition
                // the app may write itself, because it is an additive GAIN).
                try await repository.update("food_suspects",
                    set: ["status": .string("cleared"), "updated_at": .date(Date())],
                    filters: ["id": "eq.\(sid)"])
            }
        }
        if cleared { lastClearedFoodName = foodName(foodId) }
    }

    /// Event-driven progress, 0...100. NEVER reads elapsed time / challengeDays.
    func challengeProgressPct() -> Int {
        guard let ch = activeFoodChallenge else { return 0 }
        return min(100, ch.mealsFeelingFineCount * 100 / max(1, config.reintroMealsToPass))
    }

    /// The active challenge's food, once the unsurfaced unwell gate is reached,
    /// so the view can present the move-to-Avoid OFFER (never auto-commit it).
    func shouldOfferAvoid() -> FoodSuspectRow? {
        guard let ch = activeFoodChallenge,
              ch.consecutiveUnwellCount >= config.avoidOfferAfterUnwellCount else { return nil }
        return suspects.first { $0.id == ch.suspectId || $0.foodId == ch.foodId }
    }

    // MARK: - Avoid ("setting aside for now")

    /// User taps the move-to-Avoid OFFER. Sets the food aside (NOT an exclusion)
    /// and, at/over the threshold, fires the informational Survive-switch prompt
    /// (the SEPARATE care channel, re-firing, NEVER a celebration).
    func moveToAvoid(_ s: FoodSuspectRow) async {
        if let ch = activeFoodChallenge, ch.suspectId == s.id || ch.foodId == s.foodId {
            await failChallenge(ch)
        }
        await update(s, ["avoid": .bool(true), "status": .string("avoided")])
        if avoided().count >= config.avoidFoodsForSurviveSwitchPrompt {
            appState.survivePrompt(.switchToSurvivePrompt(avoidCount: avoided().count))
        }
    }

    /// Bring a set-aside food back to "checking".
    func revisit(_ s: FoodSuspectRow) async {
        await update(s, ["avoid": .bool(false), "status": .string("suspect")])
    }

    // MARK: - Persistence helpers

    private func update(_ s: FoodSuspectRow, _ set: [String: PGValue]) async {
        var body = set
        body["updated_at"] = .date(Date())
        await persist { try await repository.update("food_suspects", set: body, filters: ["id": "eq.\(s.id)"]) }
    }

    private func persist(_ work: () async throws -> Void) async {
        do {
            try await work()
            await load()
        } catch {
            errorMessage = "Couldn't save that just now. Try again."
        }
    }

    private func rank(_ t: PortionTier) -> Int {
        switch t { case .trace: 0; case .serving: 1; case .lots: 2 }
    }
}

// MARK: - Camera read seam (injected into Capture by the lead)

/// Queries `food_suspects` / `reintro_challenges` directly so Capture (Module B)
/// can do its LAYER-2 soft pass without importing any Module-E view type. This is
/// the soft, informational pass ONLY, the LOUD medical_allergy pass is LAYER 1
/// and is untouched here (rule #1, two independent passes never merged).
struct RepositorySuspectCheckService: SuspectCheckService {
    let repository: Repository

    private struct IdRow: Decodable, Sendable { let foodId: String? }

    func suspectFoodIds(for userId: String) async -> Set<String> {
        let rows: [IdRow]? = try? await repository.select(
            "food_suspects", columns: "food_id",
            filters: ["user_id": "eq.\(userId)", "status": "eq.suspect", "avoid": "eq.false"])
        return Set((rows ?? []).compactMap(\.foodId))
    }

    func avoidFoodIds(for userId: String) async -> Set<String> {
        let rows: [IdRow]? = try? await repository.select(
            "food_suspects", columns: "food_id",
            filters: ["user_id": "eq.\(userId)", "avoid": "eq.true"])
        return Set((rows ?? []).compactMap(\.foodId))
    }

    func reintroFoodIds(for userId: String) async -> Set<String> {
        let rows: [IdRow]? = try? await repository.select(
            "reintro_challenges", columns: "food_id",
            filters: ["user_id": "eq.\(userId)", "challenge_kind": "eq.food_suspect", "status": "eq.testing"])
        return Set((rows ?? []).compactMap(\.foodId))
    }
}

// MARK: - Timeline events (read-only "your own observations")

/// A single chronological observation derived from the user's own food list +
/// challenge history. Non-clinical, no verdicts, "worth raising with a dietitian."
struct SrvFoodEvent: Identifiable, Sendable {
    enum Kind: Sendable {
        case noted, confirmed, dismissed, reintroStarted, cleared, setAside, revisited
    }
    let id: String
    let date: Date
    let foodName: String
    let kind: Kind

    var systemImage: String {
        switch kind {
        case .noted: "eye"
        case .confirmed: "checkmark.circle"
        case .dismissed: "xmark.circle"
        case .reintroStarted: "arrow.up.forward.circle"
        case .cleared: "checkmark.seal"
        case .setAside: "tray.and.arrow.down"
        case .revisited: "arrow.counterclockwise"
        }
    }

    /// Calm, observational phrasing, never a verdict (rule #4).
    var summary: String {
        switch kind {
        case .noted: "Started keeping an eye on \(foodName)"
        case .confirmed: "Added \(foodName) to your list to check"
        case .dismissed: "Set \(foodName) aside as not worth checking"
        case .reintroStarted: "Began easing \(foodName) back in"
        case .cleared: "\(foodName) felt fine, back in your diet"
        case .setAside: "Set \(foodName) aside for now"
        case .revisited: "Decided to revisit \(foodName)"
        }
    }
}

extension FoodStatusStore {
    /// Synthesized timeline from current state (we don't keep a full event log;
    /// this renders the observable transitions the user has made).
    func timelineEvents() -> [SrvFoodEvent] {
        var events: [SrvFoodEvent] = []
        for s in suspects {
            let created = SrvDateParse.timestamp(s.createdAt) ?? Date.distantPast
            let updated = SrvDateParse.timestamp(s.updatedAt) ?? created
            let name = foodName(s.foodId)
            events.append(SrvFoodEvent(id: "\(s.id)-noted", date: created, foodName: name,
                                       kind: s.addedBy == "system" ? .noted : .confirmed))
            switch s.status {
            case "cleared" where s.userVerdict == "denied":
                events.append(SrvFoodEvent(id: "\(s.id)-dismissed", date: updated, foodName: name, kind: .dismissed))
            case "cleared":
                events.append(SrvFoodEvent(id: "\(s.id)-cleared", date: updated, foodName: name, kind: .cleared))
            case "avoided":
                events.append(SrvFoodEvent(id: "\(s.id)-aside", date: updated, foodName: name, kind: .setAside))
            case "reintroducing":
                events.append(SrvFoodEvent(id: "\(s.id)-reintro", date: updated, foodName: name, kind: .reintroStarted))
            default: break
            }
        }
        return events.sorted { $0.date > $1.date }
    }
}
