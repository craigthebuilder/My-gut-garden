//
//  AppState.swift
//  MyGutGarden — the app-wide observable injected through the environment.
//  Single source of truth for the signed-in user, progression (Tier-2 + world/
//  district unlocks), the celebration channel, and the guardian-prompt channel.
//

import Foundation
import Observation

/// The daily pop-up's payload: yesterday's date + its (directional) fiber total.
struct DailyCheckInOffer: Sendable, Equatable {
    let date: Date
    let fiberG: Int
}

@MainActor
@Observable
final class AppState {
    let auth: AuthService
    private(set) var profile: UserProfile?
    private(set) var progression = ProgressionState()
    /// A celebration to present at the shell (nil when none pending).
    var pendingCelebration: CelebrationEvent?
    /// A calm guardian prompt (fiber-increase offer, flag suggestion, care prompt).
    /// SEPARATE channel from celebrations — the guardian is quiet, never juice (SPEC §11).
    var pendingGuardianPrompt: GuardianPrompt?
    /// The soft daily "did you feel okay yesterday?" pop-up offer (SPEC §12); nil when none due.
    var pendingDailyCheckIn: DailyCheckInOffer?
    /// The shared coach-mark tutorial controller (SPEC §7) — app-wide so You can replay tours.
    let coach = CoachMarkController()

    init(auth: AuthService) {
        self.auth = auth
        // A restored session pairs with the last-known profile so an offline
        // launch (or a paused backend) never re-onboards an onboarded user.
        if auth.isSignedIn { profile = ProfileCache.load() }
    }

    var isSignedIn: Bool { auth.isSignedIn }

    /// Onboarding is complete once `onboarded_at` is stamped (SPEC §6). The fiber
    /// goal is deliberately absent until the week-one baseline quest unlocks it,
    /// so it must NOT be used as the completion marker.
    var isOnboarded: Bool { profile?.onboardedAt != nil }

    /// Set the instant the user finishes/skips the intro story, so the shell
    /// advances THIS session even if the DB write is deferred or fails offline
    /// (otherwise a dropped connection at that moment traps them on the story
    /// with no way forward — 2026-07-09 review).
    private var introStoryDismissedThisSession = false

    /// Meals already run through MealIngestion this process. The ingest task
    /// re-fires when the insight view re-mounts; feeding is additive and must
    /// apply exactly once per meal (2026-08-13 review).
    private var ingestedMealIds: Set<UUID> = []

    /// True the first time a meal id is seen; false on every repeat.
    func markIngestedOnce(_ mealId: UUID) -> Bool {
        ingestedMealIds.insert(mealId).inserted
    }

    /// The 3-frame intro story plays once, AFTER onboarding and BEFORE the setup
    /// tour (owner, 2026-07-09). Gated on `intro_seen_at` being nil.
    var needsIntroStory: Bool {
        isOnboarded && profile?.introSeenAt == nil && !introStoryDismissedThisSession
    }

    /// Stamp the story as seen and refresh. Advances the UI immediately (local
    /// flag) so the user is never stuck; the DB write persists it across launches
    /// (best-effort — a failed write just means the story may reappear once on a
    /// future online launch, never a dead end).
    func markIntroStorySeen() async {
        introStoryDismissedThisSession = true
        guard let repo = repository, let uid = profile?.id else { return }
        try? await repo.update("users", set: ["intro_seen_at": .date(Date())],
                               filters: ["id": "eq.\(uid)"])
        await refreshProfile()
    }

    /// RLS-scoped data layer for the current session (nil when offline/signed out).
    /// Carries a refresh hook so any write that hits an expired JWT recovers
    /// transparently instead of surfacing a 401.
    var repository: Repository? {
        guard SupabaseConfig.isConfigured, let token = auth.session?.accessToken else { return nil }
        return Repository(baseURL: SupabaseConfig.baseURL, anonKey: SupabaseConfig.anonKey, accessToken: token,
                          refreshAccessToken: { [auth] in await auth.refreshSession() })
    }

    func refreshProfile() async {
        guard let repo = repository else { return }
        if let fresh = try? await repo.fetchProfile() {
            profile = fresh
            ProfileCache.save(fresh)
        } else if profile == nil {
            // Unreachable backend: fall back to the cached profile rather than
            // dropping to nil (which reads as "not onboarded" and would replay
            // onboarding over a signed-in user's data).
            profile = ProfileCache.load()
        }
    }

    func updateProgression(_ p: ProgressionState) { progression = p }

    /// Celebrations queued behind the presented one — a varied plate can bloom
    /// two guilds in one meal, and a single slot would swallow the first.
    private var celebrationQueue: [CelebrationEvent] = []

    /// Celebrations are positive-outcome juice only (DESIGN §3); never attached
    /// to restriction (rule #7).
    func celebrate(_ event: CelebrationEvent) {
        if pendingCelebration == nil {
            pendingCelebration = event
        } else {
            celebrationQueue.append(event)
        }
    }

    /// Dismiss the presented celebration and surface the next queued one.
    func dismissCelebration() {
        pendingCelebration = celebrationQueue.isEmpty ? nil : celebrationQueue.removeFirst()
    }

    /// A calm, user-confirmed guardian prompt (SPEC §11): a fiber-increase offer,
    /// a "keep an eye on this?" suggestion, a care prompt, or an "you've overcome
    /// it" demote. Presented dismissibly; rewards nothing.
    func guardianPrompt(_ event: GuardianPrompt) { pendingGuardianPrompt = event }
}
