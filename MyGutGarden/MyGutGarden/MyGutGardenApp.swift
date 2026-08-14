//
//  MyGutGardenApp.swift
//  MyGutGarden
//
//  Created by Carlos Esber on 6/25/26.
//

import SwiftUI

@main
struct MyGutGardenApp: App {
    // One AuthService, owned by the app-wide AppState (single source of truth
    // for session + mode + progression). The shell routes from here.
    @State private var appState: AppState

    init() {
        // UITests pass --mgg-reset-auth so every test starts at the sign-in
        // gate: the keychain-persisted session (and its cached profile)
        // survives app relaunches on the simulator and would otherwise leak
        // the previous test's signed-in state into the next test.
        if ProcessInfo.processInfo.arguments.contains("--mgg-reset-auth") {
            SessionStore.clear()
            ProfileCache.clear()
        }
        _appState = State(initialValue: AppState(auth: AuthService()))
    }

    var body: some Scene {
        WindowGroup {
            AppShell(appState: appState)
        }
    }
}
