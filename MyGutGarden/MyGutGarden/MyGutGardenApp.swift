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
    @State private var appState = AppState(auth: AuthService())

    var body: some Scene {
        WindowGroup {
            AppShell(appState: appState)
        }
    }
}
