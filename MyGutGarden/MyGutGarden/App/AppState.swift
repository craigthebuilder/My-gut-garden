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

    init(auth: AuthService) { self.auth = auth }

    var isSignedIn: Bool { auth.isSignedIn }

    /// Onboarding is complete once `onboarded_at` is stamped (SPEC §6). The fiber
    /// goal is deliberately absent until the week-one baseline quest unlocks it,
    /// so it must NOT be used as the completion marker.
    var isOnboarded: Bool { profile?.onboardedAt != nil }

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
        profile = try? await repo.fetchProfile()
    }

    func updateProgression(_ p: ProgressionState) { progression = p }

    /// Celebrations are positive-outcome juice only (DESIGN §3); never attached
    /// to restriction (rule #7).
    func celebrate(_ event: CelebrationEvent) { pendingCelebration = event }

    /// A calm, user-confirmed guardian prompt (SPEC §11): a fiber-increase offer,
    /// a "keep an eye on this?" suggestion, a care prompt, or an "you've overcome
    /// it" demote. Presented dismissibly; rewards nothing.
    func guardianPrompt(_ event: GuardianPrompt) { pendingGuardianPrompt = event }
}
