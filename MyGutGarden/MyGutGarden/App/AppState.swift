//
//  AppState.swift
//  MyGutGarden — the app-wide observable injected through the environment.
//  Single source of truth for the signed-in user, current mode, progression
//  (Tier-2 + district unlocks), and the celebration channel. Modules read it.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    let auth: AuthService
    private(set) var profile: UserProfile?
    private(set) var progression = ProgressionState()
    /// Thrive-only celebration to present at the shell (nil when none pending).
    var pendingCelebration: CelebrationEvent?

    init(auth: AuthService) { self.auth = auth }

    var isSignedIn: Bool { auth.isSignedIn }
    var mode: AppMode { profile?.currentMode ?? .thrive }
    /// Onboarding is complete once the fiber goal has been derived (SPEC §10).
    var isOnboarded: Bool { profile?.fiberGoalG != nil }

    /// RLS-scoped data layer for the current session (nil when offline/signed out).
    var repository: Repository? {
        guard SupabaseConfig.isConfigured, let token = auth.session?.accessToken else { return nil }
        return Repository(baseURL: SupabaseConfig.baseURL, anonKey: SupabaseConfig.anonKey, accessToken: token)
    }

    func refreshProfile() async {
        guard let repo = repository else { return }
        profile = try? await repo.fetchProfile()
    }

    /// Mode switch is always available, gated only by a disclaimer + confirm in
    /// the UI (SPEC §2). This performs the persisted write after confirmation.
    func setMode(_ newMode: AppMode) async {
        guard let repo = repository, let id = profile?.id else { return }
        try? await repo.update("users", set: ["current_mode": .string(newMode.rawValue)],
                               filters: ["id": "eq.\(id)"])
        await refreshProfile()
    }

    func updateProgression(_ p: ProgressionState) { progression = p }

    /// Celebrations are Thrive-only juice (DESIGN.md §3); ignored in Survive so
    /// nothing ever "rewards restriction" (Fence 5).
    func celebrate(_ event: CelebrationEvent) {
        guard mode == .thrive else { return }
        pendingCelebration = event
    }
}
