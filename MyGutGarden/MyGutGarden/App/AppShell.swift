//
//  AppShell.swift
//  MyGutGarden, the root shell (orchestrator-owned consolidation). Routes
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

private enum ThriveTab: Hashable { case today, snap, checkin, garden, you }

private struct ShellHome: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    @State private var thriveTab: ThriveTab = .today

    var body: some View {
        ZStack {
            if appState.mode == .thrive {
                ThriveTabs(appState: appState, selection: $thriveTab)
            } else {
                SurviveTabs(appState: appState)
            }
            if let event = appState.pendingCelebration {
                celebration(for: event)
            }
            // Care prompt (Avoid→Survive offer, graduate offer). Calm + dismissible,
            // never a celebration, and it fires in either mode (Batch E).
            if let prompt = appState.pendingSurvivePrompt {
                survivePrompt(prompt)
            }
        }
        .tint(theme.colors.primary)
    }

    private func dismissCelebration() { appState.pendingCelebration = nil }
    private func dismissSurvivePrompt() { appState.pendingSurvivePrompt = nil }

    @ViewBuilder
    private func survivePrompt(_ event: SurvivePromptEvent) -> some View {
        ModalScrim(onTapOutside: dismissSurvivePrompt) {
            switch event {
            case let .switchToSurvivePrompt(count):
                ConfirmationModal(
                    title: "A calmer way to sort this out?",
                    message: "You're keeping an eye on \(count) foods right now. Survive mode gives you a gentler, more structured way to find what your gut is reacting to. Want to try it?",
                    confirmTitle: "Try Survive",
                    cancelTitle: "Not now",
                    severity: .info,
                    onConfirm: { dismissSurvivePrompt(); Task { await appState.setMode(.survive) } },
                    onCancel: dismissSurvivePrompt
                )
            case .graduateToThrive:
                ConfirmationModal(
                    title: "Ready for Thrive?",
                    message: "You've been feeling good. The foods you're still checking come with you. Want to move to Thrive and start growing?",
                    confirmTitle: "Move to Thrive",
                    cancelTitle: "Not yet",
                    severity: .info,
                    onConfirm: { dismissSurvivePrompt(); Task { await appState.setMode(.thrive); appState.celebrate(.graduation) } },
                    onCancel: dismissSurvivePrompt
                )
            }
        }
        .themed(for: appState.mode)
    }

    @ViewBuilder
    private func celebration(for event: CelebrationEvent) -> some View {
        switch event {
        case let .districtUnlock(name):
            // Tapping "Explore" routes straight to the garden map (the new district).
            CelebrationOverlay(
                title: "New district unlock!",
                message: "Tap to explore \(name).",
                systemImage: "map.fill",
                primaryTitle: "Explore",
                onPrimary: { dismissCelebration(); thriveTab = .garden },
                onDismiss: dismissCelebration
            )
        case .graduation:
            CelebrationOverlay(
                title: "Congratulations!",
                message: "Welcome to Thrive. Your garden is blooming, and your safe foods are flowing in.",
                systemImage: "party.popper.fill",
                onDismiss: dismissCelebration
            )
        case let .rareFind(plant, rarity):
            CelebrationOverlay(
                title: "A \(rarity.label.lowercased()) find!",
                message: "You discovered \(plant).",
                onDismiss: dismissCelebration
            )
        case let .guildBloom(name):
            CelebrationOverlay(
                title: "\(name) is blooming!",
                message: "Your sustained feeding paid off.",
                systemImage: "leaf.fill",
                onDismiss: dismissCelebration
            )
        case let .guildUnlock(name):
            CelebrationOverlay(
                title: "\(name) joined your garden",
                message: "A new crew to feed.",
                systemImage: "leaf.fill",
                onDismiss: dismissCelebration
            )
        }
    }
}

private struct ThriveTabs: View {
    let appState: AppState
    @Binding var selection: ThriveTab
    @State private var recognizer = RecognitionService()

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "leaf", value: ThriveTab.today) { ThrRootView(appState: appState) }
            Tab("Snap", systemImage: "camera", value: ThriveTab.snap) {
                CapRootView(appState: appState, recognizer: recognizer)
                    .environment(\.mealInsightPresenter,
                                 ShellInsightPresenter(inner: ThrInsightPresenter(appState: appState), appState: appState))
                    .captureSeams(appState: appState)
            }
            // The Thrive "test" check-in: reintroduce 1-2 foods while thriving (Batch E).
            Tab("Check-in", systemImage: "checklist", value: ThriveTab.checkin) {
                ThrTestTabView(appState: appState)
            }
            if appState.progression.isTier2Unlocked {
                Tab("Garden", systemImage: "map", value: ThriveTab.garden) {
                    GuildRootView(repository: appState.repository, progression: appState.progression)
                }
            }
            Tab("You", systemImage: "person", value: ThriveTab.you) { ShellSettings(appState: appState) }
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
                    .captureSeams(appState: appState)
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
/// ingestion coordinator (plants, guild feeding, progression), Module B never
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

// MARK: - Capture seam injection (Module E food-status services → Module B)

private struct CaptureSeams: ViewModifier {
    let appState: AppState
    func body(content: Content) -> some View {
        content
            .environment(\.suspectCheckService, Self.suspectService(appState))
            .environment(\.capReintroFeelingRecorder, { reintroFoodId, mealId, feltFine in
                await recordReintroAnswer(appState, foodId: reintroFoodId, mealId: mealId, feltFine: feltFine)
            })
    }
    private static func suspectService(_ appState: AppState) -> any SuspectCheckService {
        if let repo = appState.repository { return RepositorySuspectCheckService(repository: repo) }
        return NoopSuspectCheckService()
    }
}

private extension View {
    func captureSeams(appState: AppState) -> some View { modifier(CaptureSeams(appState: appState)) }
}

/// Writes a reintro "How did [food] feel?" answer: derives the meal's coarse
/// portion from meal_items, then records it through Module E's store, which
/// advances the event-driven challenge and upserts the check-in entry.
@MainActor
private func recordReintroAnswer(_ appState: AppState, foodId: String, mealId: String, feltFine: Bool) async {
    guard let repo = appState.repository, let uid = appState.profile?.id else { return }
    let portion = (await mealItemPortion(repo, mealId: mealId, foodId: foodId)) ?? .serving
    let store = FoodStatusStore(repository: repo, userId: uid, appState: appState)
    await store.load()
    await store.recordReintroMeal(foodId: foodId, mealId: mealId, portion: portion, feltFine: feltFine)
}

private struct MealItemPortionRow: Decodable, Sendable { let portionTier: String }

@MainActor
private func mealItemPortion(_ repo: Repository, mealId: String, foodId: String) async -> PortionTier? {
    let rows: [MealItemPortionRow]? = try? await repo.select(
        "meal_items", columns: "portion_tier",
        filters: ["meal_id": "eq.\(mealId)", "food_id": "eq.\(foodId)"], limit: 1)
    guard let raw = rows?.first?.portionTier else { return nil }
    return PortionTier(rawValue: raw)
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
                        // Thrive-only: Survive has no fiber goal (it uses the fiber
                        // calc as a residue ceiling, never a target to hit).
                        if appState.mode == .thrive, let goal = appState.profile?.fiberGoalG {
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
        // A clear-backed full-screen cover + scrim, so the dialog floats over the
        // dimmed app instead of on an opaque white sheet.
        .fullScreenCover(item: $pending) { which in
            ModalScrim(onTapOutside: { pending = nil }) {
                switch which {
                case .toSurvive:
                    ConfirmationModal(
                        title: "Switch to Survive?",
                        message: "Survive is for finding triggers and easing symptoms. Nothing you've grown is lost, and you can switch back any time.",
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
            .themed(for: appState.mode)
            .presentationBackground(.clear)
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
