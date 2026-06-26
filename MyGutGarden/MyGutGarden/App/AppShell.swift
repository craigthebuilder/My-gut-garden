//
//  AppShell.swift
//  MyGutGarden — the root shell (orchestrator-owned consolidation). Routes
//  auth → onboarding → the mode-themed surfaces, injects the per-mode insight
//  presenter (which also fires the MealIngestion coordinator so Module B stays
//  untouched), and hosts the cross-cutting flows: mode switch (disclaimer +
//  click-to-confirm, §2), graduation, and the celebration overlay.
//

import SwiftUI
import AuthenticationServices

struct AppShell: View {
    let appState: AppState

    var body: some View {
        Group {
            if !appState.isSignedIn {
                ShellAuthGate(auth: appState.auth)
            } else if !appState.isOnboarded {
                OnbRootView(appState: appState, onFinished: {
                    Task { await appState.refreshProfile() }
                })
            } else {
                ShellHome(appState: appState)
            }
        }
        .themed(for: appState.mode)
        .task(id: appState.isSignedIn) {
            guard appState.isSignedIn else { return }
            await appState.refreshProfile()
            if let uid = appState.profile?.id, let repo = appState.repository {
                await MealIngestion(repository: repo, appState: appState).recomputeProgression(userId: uid)
            }
        }
    }
}

// MARK: - Mode home (tabs themed by current mode)

private struct ShellHome: View {
    @Environment(\.theme) private var theme
    let appState: AppState

    var body: some View {
        ZStack {
            if appState.mode == .thrive {
                ThriveTabs(appState: appState)
            } else {
                SurviveTabs(appState: appState)
            }
            if let event = appState.pendingCelebration {
                celebration(for: event)
            }
        }
        .tint(theme.colors.primary)
    }

    @ViewBuilder
    private func celebration(for event: CelebrationEvent) -> some View {
        let (title, message, symbol): (String, String, String) = {
            switch event {
            case let .rareFind(plant, rarity): ("A \(rarity.label.lowercased()) find!", "You discovered \(plant).", "sparkles")
            case let .guildBloom(name): ("\(name) is blooming!", "Your sustained feeding paid off.", "leaf.fill")
            case let .guildUnlock(name): ("\(name) joined your garden", "A new crew to feed.", "leaf.fill")
            case let .districtUnlock(name): ("\(name) unlocked", "A new district to explore.", "map.fill")
            case .graduation: ("Welcome to Thrive", "Your garden is blooming — safe foods are flowing in.", "sun.max.fill")
            }
        }()
        CelebrationOverlay(title: title, message: message, systemImage: symbol) {
            appState.pendingCelebration = nil
        }
    }
}

private struct ThriveTabs: View {
    let appState: AppState
    @State private var recognizer = RecognitionService()

    var body: some View {
        TabView {
            Tab("Today", systemImage: "leaf") { ThrRootView(appState: appState) }
            Tab("Snap", systemImage: "camera") {
                CapRootView(appState: appState, recognizer: recognizer)
                    .environment(\.mealInsightPresenter,
                                 ShellInsightPresenter(inner: ThrInsightPresenter(appState: appState), appState: appState))
            }
            if appState.progression.isTier2Unlocked {
                Tab("Garden", systemImage: "map") {
                    GuildRootView(repository: appState.repository, progression: appState.progression)
                }
            }
            Tab("You", systemImage: "person") { ShellSettings(appState: appState) }
        }
    }
}

private struct SurviveTabs: View {
    let appState: AppState
    @State private var recognizer = RecognitionService()
    @State private var store: SrvStore

    init(appState: AppState) {
        self.appState = appState
        _store = State(initialValue: SrvStore(appState: appState))
    }

    var body: some View {
        TabView {
            Tab("Today", systemImage: "heart.text.square") { SrvRootView(store: store) }
            Tab("Snap", systemImage: "camera") {
                CapRootView(appState: appState, recognizer: recognizer)
                    .environment(\.mealInsightPresenter,
                                 ShellInsightPresenter(inner: store.makeInsightPresenter(), appState: appState))
            }
            Tab("You", systemImage: "person") { ShellSettings(appState: appState) }
        }
        .task {
            // Wire Module F: refresh the (read-only) pattern assessment on entry.
            if let uid = appState.profile?.id, let repo = appState.repository {
                try? await PatPatternEngine().refresh(repository: repo, userId: uid, asOf: Date())
            }
        }
    }
}

/// Wraps the mode's insight presenter so confirming a meal also runs the
/// ingestion coordinator (plants, guild feeding, progression) — Module B never
/// learns about the coordinator. Side effect runs once, when the insight appears.
private struct ShellInsightPresenter: MealInsightPresenting {
    let inner: any MealInsightPresenting
    let appState: AppState

    func insightView(for meal: ConfirmedMeal) -> AnyView {
        let base = inner.insightView(for: meal)
        let state = appState
        return AnyView(base.task {
            if let repo = state.repository {
                await MealIngestion(repository: repo, appState: state).ingest(meal)
            }
        })
    }
}

// MARK: - Settings / mode switch / graduation (cross-cutting, §2)

private struct ShellSettings: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    @State private var pending: PendingSwitch?

    private enum PendingSwitch: Identifiable { case toSurvive, graduate ; var id: Int { hashValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                SectionHeader(title: "You")
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space3) {
                        Text(appState.mode == .thrive ? "You're in Thrive" : "You're in Survive")
                            .font(theme.typography.title())
                            .foregroundStyle(theme.colors.textPrimary)
                        if let goal = appState.profile?.fiberGoalG {
                            Text("Daily fiber goal: \(goal) g")     // the only surfaced derived number (§10)
                                .font(theme.typography.body())
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                        if appState.mode == .thrive {
                            SecondaryButton(title: "Go back to basics (Survive)", systemImage: "arrow.uturn.down") {
                                pending = .toSurvive
                            }
                        } else {
                            PrimaryButton(title: "Graduate to Thrive", systemImage: "sun.max") {
                                pending = .graduate
                            }
                        }
                        SecondaryButton(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                            appState.auth.signOut()
                        }
                    }
                }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .sheet(item: $pending) { which in
            switch which {
            case .toSurvive:
                ConfirmationModal(
                    title: "Switch to Survive?",
                    message: "Survive is for finding triggers and easing symptoms. Nothing you've grown is lost — switch back any time.",
                    confirmTitle: "Switch to Survive",
                    severity: .caution,
                    onConfirm: { pending = nil; Task { await appState.setMode(.survive) } },
                    onCancel: { pending = nil }
                )
            case .graduate:
                ConfirmationModal(
                    title: "Graduate to Thrive?",
                    message: "You've done the hard part. Your garden blooms and your confirmed-safe foods flow into your collection.",
                    confirmTitle: "Begin the ceremony",
                    severity: .info,
                    onConfirm: {
                        pending = nil
                        Task {
                            await appState.setMode(.thrive)
                            appState.celebrate(.graduation)
                        }
                    },
                    onCancel: { pending = nil }
                )
            }
        }
    }
}

// MARK: - Auth gate (email + Sign in with Apple, SPEC §3)

private struct ShellAuthGate: View {
    @Environment(\.theme) private var theme
    let auth: AuthService
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space5) {
                VStack(alignment: .leading, spacing: theme.metrics.space2) {
                    Text("My Gut Garden")
                        .font(theme.typography.display())
                        .foregroundStyle(theme.colors.primary)
                    Text("Grow a garden you can feed.")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Card {
                    VStack(spacing: theme.metrics.space3) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                        PrimaryButton(title: "Sign in") { Task { await auth.signIn(email: email, password: password) } }
                        SecondaryButton(title: "Create account") { Task { await auth.signUp(email: email, password: password) } }
                        SignInWithAppleButton(.signIn) { auth.prepareAppleRequest($0) }
                            onCompletion: { result in Task { await auth.handleAppleCompletion(result) } }
                            .frame(height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium))
                        if auth.isBusy { ProgressView() }
                        if let error = auth.errorMessage {
                            Text(error).font(theme.typography.caption()).foregroundStyle(theme.colors.error)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
    }
}
