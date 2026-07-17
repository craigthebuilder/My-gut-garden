//
//  AppShell.swift
//  MyGutGarden — the root shell. Routes auth → onboarding → the single-mode
//  surfaces, injects the insight presenter (which also fires the MealIngestion
//  coordinator so Capture stays untouched), and hosts the cross-cutting overlays:
//  the celebration channel and the calm guardian-prompt channel (SPEC §11).
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
            } else if appState.needsIntroStory {
                // After onboarding, before the setup tour (owner, 2026-07-09).
                OnbStoryView(gardenerName: appState.profile?.gardenerDisplayName ?? "Sprout") {
                    Task { await appState.markIntroStorySeen() }
                }
            } else {
                ShellHome(appState: appState)
            }
        }
        .themed()
        .task(id: appState.isSignedIn) {
            guard appState.isSignedIn else { return }
            await appState.refreshProfile()
            if let uid = appState.profile?.id, let repo = appState.repository {
                await MealIngestion(repository: repo, appState: appState).recomputeProgression(userId: uid)
                // Yesterday's soft "did you feel okay?" pop-up if due; otherwise the
                // guardian may surface a calm prompt. They don't stack (SPEC §11/§12).
                let offered = await DailyCheckInRunner(repository: repo, appState: appState).offerIfDue(userId: uid)
                if !offered {
                    await GuardianRunner(repository: repo, appState: appState).run(userId: uid)
                }
            }
        }
    }
}

// MARK: - Home (single-mode tabs)

/// Internal (not private) so Today's explore rows can ask the shell to switch
/// tabs (field guide / garden route straight to their tabs).
enum AppTab: Hashable { case today, snap, fieldGuide, garden, you }

private struct ShellHome: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    @State private var tab: AppTab = .today
    @State private var recognizer = RecognitionService()

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                Tab("Today", systemImage: "leaf", value: AppTab.today) {
                    ThrRootView(appState: appState, onSwitchTab: { tab = $0 })
                }
                Tab("Snap", systemImage: "camera", value: AppTab.snap) {
                    CapRootView(appState: appState, recognizer: recognizer)
                        .environment(\.mealInsightPresenter,
                                     ShellInsightPresenter(inner: ThrInsightPresenter(appState: appState), appState: appState))
                }
                Tab("Field Guide", systemImage: "book", value: AppTab.fieldGuide) {
                    NavigationStack { ThrPokedexView(appState: appState, latestMeal: nil) }
                }
                // Always visible (owner, 2026-07-09): week one shows a locked
                // tease instead of hiding the tab — new users should see the
                // garden exists and what opens it.
                Tab("Garden", systemImage: "map", value: AppTab.garden) {
                    if appState.progression.isTier2Unlocked {
                        GuildRootView(repository: appState.repository, progression: appState.progression,
                                      gardenerName: appState.profile?.gardenerDisplayName ?? "Sprout")
                    } else {
                        ShellGardenLocked(gardenerName: appState.profile?.gardenerDisplayName ?? "Sprout")
                    }
                }
                Tab("You", systemImage: "person", value: AppTab.you) { ShellSettings(appState: appState) }
            }
            // The dim-page spotlight tutorial (SPEC §7). Attached here (not a
            // ZStack sibling) so it can read the `.coachTarget` anchors that
            // bubble up from the tabs' views — and walk the tour across tabs.
            .overlayPreferenceValue(CoachTargetKey.self) { anchors in
                CoachMarkOverlay(controller: appState.coach, appState: appState,
                                 anchors: anchors,
                                 onNavigate: { hint in
                    // Only the INTRO tour walks across tabs. Section tours
                    // (plants, rainbow, phytochemicals, fermented, garden…) fire
                    // when the user is ALREADY on that screen, so navigating would
                    // yank them away from their own anchor and break the tour —
                    // e.g. "plants" maps to Today but its anchor lives in the
                    // Field Guide's Plant Garden (owner report, 2026-07-10).
                    guard appState.coach.sectionKey == "intro" else { return }
                    if let destination = Self.tab(forCoachHint: hint,
                                                  gardenUnlocked: appState.progression.isTier2Unlocked) {
                        tab = destination
                    }
                })
            }
            // All three shell modals stop above the tab bar (tabBarClearance):
            // a tap on a tab must always switch tabs, never silently dismiss a
            // scrim instead (owner, 2026-07-17: "bug when I click the You tab").
            if let event = appState.pendingCelebration {
                celebration(for: event)
                    .padding(.bottom, theme.metrics.tabBarClearance)
            }
            // A calm, user-confirmed guardian prompt (fiber-increase offer, flag
            // suggestion, care prompt). SEPARATE from celebrations (SPEC §11).
            if let prompt = appState.pendingGuardianPrompt {
                guardianPrompt(prompt)
                    .padding(.bottom, theme.metrics.tabBarClearance)
            }
            // The soft daily "did you feel okay yesterday?" pop-up (SPEC §12).
            if let offer = appState.pendingDailyCheckIn {
                dailyCheckIn(offer)
                    .padding(.bottom, theme.metrics.tabBarClearance)
            }
        }
        .tint(theme.colors.primary)
        .task {
            await appState.coach.loadCompleted(appState)
            await appState.coach.startIfNeeded("intro", appState: appState)
        }
        // First visit to the (unlocked) Garden tab starts its own tour (owner,
        // round 2 — rainbow + phytochemicals start theirs from inside their
        // views). The locked tease has no tour targets, so don't start it there.
        .onChange(of: tab) { _, newTab in
            // If a tour is showing and the user navigated somewhere the tour did
            // NOT send them, they've chosen to explore — end the tour so it never
            // traps them (owner report, 2026-07-10: "freezes when I click Garden").
            // Comparing against the tour's own target tab (rather than a flag)
            // stays correct even when the tour walks within one tab.
            if appState.coach.isShowing {
                let tourTab = appState.coach.current?.targetHint.flatMap {
                    Self.tab(forCoachHint: $0, gardenUnlocked: appState.progression.isTier2Unlocked)
                }
                if newTab != tourTab { appState.coach.skip(appState) }
            }
            if newTab == .garden, appState.progression.isTier2Unlocked {
                Task { await appState.coach.startIfNeeded("garden", appState: appState) }
            }
        }
    }

    /// Which tab a tutorial step's `target_hint` lives on, so the intro tour
    /// walks the real app. nil → stay put (the card centers if no target).
    static func tab(forCoachHint hint: String, gardenUnlocked: Bool) -> AppTab? {
        switch hint {
        case "home", "dashboard", "threeps", "trythis", "fiber", "plants", "rainbow", "checkin": .today
        case "snap": .snap
        case "fieldguide", "fermented", "phytochemicals": .fieldGuide
        case "garden": gardenUnlocked ? .garden : nil
        case "you", "customize": .you
        default: nil
        }
    }

    private static let feltOptions = ["Great", "Pretty good", "A bit off", "Rough"]  // → discomfort 0..3

    /// The one-tap daily pop-up: a warm fiber acknowledgement + "how did you feel?".
    /// The answer writes a `daily_popup` check-in, then the guardian gets a fresh look.
    @ViewBuilder
    private func dailyCheckIn(_ offer: DailyCheckInOffer) -> some View {
        ModalScrim(onTapOutside: { appState.pendingDailyCheckIn = nil }) {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                Text(offer.fiberG > 0 ? "Nice — \(offer.fiberG) g of fiber yesterday" : "Yesterday's check-in")
                    .font(theme.typography.title())
                    .foregroundStyle(theme.colors.textPrimary)
                Text("How did you feel? (directional — no wrong answer)")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(Self.feltOptions.enumerated()), id: \.offset) { i, label in
                    Button { answerDaily(discomfort: i, date: offer.date) } label: {
                        Text(label)
                            .font(theme.typography.body(weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, theme.metrics.space3)
                            .foregroundStyle(theme.colors.textPrimary)
                            .background(theme.colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(theme.metrics.space5)
            .frame(maxWidth: theme.metrics.calloutMaxWidth)
            .background(theme.colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusLarge, style: .continuous))
        }
    }

    private func answerDaily(discomfort: Int, date: Date) {
        appState.pendingDailyCheckIn = nil
        Task {
            guard let repo = appState.repository, let uid = appState.profile?.id else { return }
            try? await CheckInWriter(repository: repo, userId: uid).saveDailyFeltOkay(discomfort: discomfort, on: date)
            // Now that yesterday's comfort is recorded, let the guardian take a fresh look.
            await GuardianRunner(repository: repo, appState: appState).run(userId: uid)
        }
    }

    private func dismissCelebration() { appState.pendingCelebration = nil }
    private func dismissGuardian() { appState.pendingGuardianPrompt = nil }

    // MARK: Guardian prompts (SPEC §11) — the user confirms every step.

    @ViewBuilder
    private func guardianPrompt(_ event: GuardianPrompt) -> some View {
        // The guardian IS the gardener: every nudge speaks in their voice, by
        // name (owner, 2026-07-09). Still deterministic + user-confirmed (§11).
        let name = appState.profile?.gardenerDisplayName ?? "Sprout"
        return ModalScrim(onTapOutside: dismissGuardian) {
            switch event {
            case let .fiberGoalIncrease(current, proposed):
                ConfirmationModal(
                    title: "Ready for a little more fiber?",
                    message: "You've been handling \(current) g comfortably, so \(name) thinks you're ready for a little more. Nudge your daily goal up to \(proposed) g? Add a little water to match.",
                    confirmTitle: "Raise it",
                    cancelTitle: "Not yet",
                    severity: .info,
                    onConfirm: { dismissGuardian(); Task { await applyFiberGoal(proposed) } },
                    onCancel: dismissGuardian
                )
            case let .suggestWatching(foodName, foodId):
                ConfirmationModal(
                    title: "Keep an eye on \(foodName)?",
                    message: "\(name) noticed you've felt off after a few meals with \(foodName). Want to keep an eye on it together? It stays on your plate — we'll just watch how it sits.",
                    confirmTitle: "Yes, add it",
                    cancelTitle: "Not now",
                    severity: .info,
                    onConfirm: { dismissGuardian(); Task { await setFlag(foodId: foodId, tier: "watching") } },
                    onCancel: dismissGuardian
                )
            case let .couldBeAllergy(foodName, foodId):
                ConfirmationModal(
                    title: "Worth a closer look?",
                    message: "\(foodName) really doesn't seem to agree with you. \(name) thinks it could be worth raising with a doctor or allergist. Want to mark it as an allergy so we always flag it clearly?",
                    confirmTitle: "Mark as allergy",
                    cancelTitle: "Not now",
                    severity: .caution,
                    onConfirm: { dismissGuardian(); Task { await setFlag(foodId: foodId, tier: "allergy") } },
                    onCancel: dismissGuardian
                )
            case let .overcameSensitivity(foodName, foodId):
                ConfirmationModal(
                    title: "\(foodName) looks good again",
                    message: "You've been enjoying \(foodName) with no trouble lately — \(name) thinks it's earned its place back. Bring it back in and stop flagging it?",
                    confirmTitle: "Bring it back",
                    cancelTitle: "Keep flagging",
                    severity: .info,
                    onConfirm: { dismissGuardian(); Task { await clearFlag(foodId: foodId) } },
                    onCancel: dismissGuardian
                )
            case let .rampSlower(currentComfort):
                // SPEC §17: adaptation is the FIRST hypothesis — offered before
                // any food suggestion, and the user authors the change.
                ConfirmationModal(
                    title: "A big fermenting day",
                    message: "That was a lot of fast-fermenting fiber, and you felt it. \(name) reckons that's your crews adapting to new fuel, not a problem food — comfort builds as their capacity grows. Ramp a little gentler for a while?",
                    confirmTitle: "Go gentler",
                    cancelTitle: "Keep my pace",
                    severity: .info,
                    onConfirm: { dismissGuardian(); Task { await setGasComfort(currentComfort.gentler) } },
                    onCancel: dismissGuardian
                )
            case let .balance(kind):
                // SPEC §17 quiet balance: one calm sentence, dismiss-only, words
                // never numbers (rule #6 as amended). // RD-REVIEW-REQUIRED copy.
                ConfirmationModal(
                    title: "A note from \(name)",
                    message: balanceMessage(kind, gardener: name),
                    confirmTitle: "Got it",
                    cancelTitle: nil,
                    severity: .info,
                    onConfirm: dismissGuardian,
                    onCancel: dismissGuardian
                )
            }
        }
    }

    /// 🔒 FENCE 3/4 (RD-REVIEW-REQUIRED): curated balance copy — educational,
    /// gain-framed, never a number, score, or instruction to restrict.
    private func balanceMessage(_ kind: GuardianPrompt.BalanceKind, gardener: String) -> String {
        switch kind {
        case .proteinLight:
            "\(gardener) noticed your recent meals look a little light on protein-rich foods. Protein keeps energy steady and repairs the body — beans, lentils, tofu, yogurt, eggs, fish, or meat all count. Just something to keep in mind."
        case .proteinHeavy:
            "\(gardener) noticed your recent plates lean heavily on protein-rich foods. Nothing wrong with protein — but variety is what feeds your garden. A few more plants alongside would round things out nicely."
        case .energyLight:
            "\(gardener) noticed your recent meals look light on overall fuel. Gardens need energy to grow — whole grains, nuts, olive oil, or simply heartier portions all help everything work better."
        }
    }

    private func setGasComfort(_ comfort: GasComfort) async {
        guard let repo = appState.repository, let id = appState.profile?.id else { return }
        try? await repo.update("users", set: ["gas_comfort": .string(comfort.rawValue)],
                               filters: ["id": "eq.\(id)"])
        await appState.refreshProfile()
    }

    private func applyFiberGoal(_ g: Int) async {
        guard let repo = appState.repository, let id = appState.profile?.id else { return }
        try? await repo.update("users", set: ["fiber_goal_g": .int(g)], filters: ["id": "eq.\(id)"])
        await appState.refreshProfile()
    }
    private func setFlag(foodId: String, tier: String) async {
        guard let repo = appState.repository, let id = appState.profile?.id else { return }
        try? await repo.upsert("food_flags", [
            "user_id": .string(id), "food_id": .string(foodId),
            "flag_tier": .string(tier), "source": .string("user"), "user_confirmed": .bool(true),
            "updated_at": .date(Date()),
        ], onConflict: "user_id,food_id")
    }
    private func clearFlag(foodId: String) async {
        guard let repo = appState.repository, let id = appState.profile?.id else { return }
        try? await repo.delete("food_flags", filters: ["user_id": "eq.\(id)", "food_id": "eq.\(foodId)"])
    }

    @ViewBuilder
    private func celebration(for event: CelebrationEvent) -> some View {
        switch event {
        case let .districtUnlock(name):
            CelebrationOverlay(
                title: "New district unlocked!",
                message: "Tap to explore \(name).",
                systemImage: "map.fill",
                primaryTitle: "Explore",
                onPrimary: { dismissCelebration(); tab = .garden },
                onDismiss: dismissCelebration
            )
        case let .worldUnlock(name):
            CelebrationOverlay(
                title: "A new world opened!",
                message: "Tap to explore \(name).",
                systemImage: "globe.americas.fill",
                primaryTitle: "Explore",
                onPrimary: { dismissCelebration(); tab = .garden },
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
        case let .fiberGoalUnlocked(goal):
            // The one surfaced derived number, and only after this unlock (§10).
            CelebrationOverlay(
                title: "Your fiber goal is ready",
                message: "You've explored enough plants for us to learn your baseline. From here, aim for \(goal) g of fiber a day — we'll offer gentle raises as it sits well, with water reminders along the way.",
                systemImage: "target",
                onDismiss: dismissCelebration
            )
        }
    }
}

/// Wraps the insight presenter so confirming a meal also runs the ingestion
/// coordinator (plants, guild feeding, progression). Capture never learns about
/// the coordinator. The side effect runs once, when the insight appears.
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

// MARK: - You (spine version; the full You surface is Phase 1E)

private struct ShellSettings: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    @State private var showFoods = false
    @State private var showCheckIn = false
    @State private var showCustomize = false
    @State private var showBadges = false
    @State private var showGasComfort = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                SectionHeader(title: "You")
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space3) {
                        if let goal = ThrHomeModel.surfacedGoal(appState.profile) {
                            Text("Daily fiber goal: \(goal) g")     // the only surfaced derived number (§10)
                                .font(theme.typography.title())
                                .foregroundStyle(theme.colors.textPrimary)
                            Text("We'll offer to raise this as you consistently hit it.")
                                .font(theme.typography.caption())
                                .foregroundStyle(theme.colors.textSecondary)
                        } else {
                            Text("Your fiber goal unlocks after your first week")
                                .font(theme.typography.title())
                                .foregroundStyle(theme.colors.textPrimary)
                            Text("Hit 30 plant foods this week and eat the rainbow — we're learning your baseline.")
                                .font(theme.typography.caption())
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                        SecondaryButton(title: "Daily check-in", systemImage: "checklist") {
                            showCheckIn = true
                        }
                        SecondaryButton(title: "Customize check-in", systemImage: "slider.horizontal.3") {
                            showCustomize = true
                        }
                        SecondaryButton(title: "Gas comfort: \(currentGasComfort.label)", systemImage: "wind") {
                            showGasComfort = true
                        }
                        SecondaryButton(title: "Badges", systemImage: "rosette") {
                            showBadges = true
                        }
                        SecondaryButton(title: "Foods you're keeping an eye on", systemImage: "eye") {
                            showFoods = true
                        }
                        SecondaryButton(title: "Replay the intro tour", systemImage: "sparkles") {
                            Task { await appState.coach.start("intro", appState: appState) }
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
        .sheet(isPresented: $showFoods) { YouFoodFlagsView(appState: appState) }
        .sheet(isPresented: $showCheckIn) { ThrCheckInLogView(appState: appState) }
        .sheet(isPresented: $showCustomize) { YouCheckInPrefsSheet(appState: appState) { showCustomize = false } }
        .sheet(isPresented: $showBadges) { YouBadgesView(appState: appState) }
        // SPEC §17: the gas-for-growth dial — a preference, never a symptom
        // score. Presented from the CONTAINER, and the row is a stock
        // SecondaryButton: two bespoke versions of this row (a Menu, then a
        // Button, each with full-width chrome INSIDE the label) wedged
        // SwiftUI's AttributeGraph on iOS 26 into a permanent main-thread
        // freeze (owner reports 2026-07-17; both `sample`d live, all frames
        // flooring in this row). Keep it identical to its sibling rows.
        .confirmationDialog("Gas comfort", isPresented: $showGasComfort, titleVisibility: .visible) {
            ForEach(GasComfort.allCases, id: \.self) { option in
                Button(option == currentGasComfort
                       ? "\(option.label) — \(option.explainer) ✓"
                       : "\(option.label) — \(option.explainer)") {
                    Task { await setGasComfort(option) }
                }
            }
        }
    }

    private var currentGasComfort: GasComfort {
        appState.profile?.gasComfort.flatMap(GasComfort.init(rawValue:)) ?? .balanced
    }

    private func setGasComfort(_ option: GasComfort) async {
        guard let repo = appState.repository, let id = appState.profile?.id else { return }
        try? await repo.update("users", set: ["gas_comfort": .string(option.rawValue)],
                               filters: ["id": "eq.\(id)"])
        await appState.refreshProfile()
    }
}

// MARK: - Locked garden (week one; owner, 2026-07-09)

/// What the Garden tab shows before tier 2 unlocks: a tease, never a wall.
/// Gain-framed (what's coming + how it opens), no countdowns, no shame —
/// every plant already counts, the gates just aren't open yet.
private struct ShellGardenLocked: View {
    @Environment(\.theme) private var theme
    var gardenerName: String = "Sprout"

    var body: some View {
        ScrollView {
            VStack(spacing: theme.metrics.space5) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(theme.colors.primary.opacity(0.25))
                    Image(systemName: "lock.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(theme.colors.secondary)
                        .padding(theme.metrics.space2)
                        .background(theme.colors.surface, in: Circle())
                }
                .padding(.top, theme.metrics.space6)
                .accessibilityHidden(true)

                VStack(spacing: theme.metrics.space2) {
                    Text("Your garden is taking root")
                        .font(theme.typography.title())
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("A living map of the microbe crews your plants feed — worlds, districts, and guilds that bloom as you eat. \(gardenerName) opens it up after your first week.")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, theme.metrics.space5)

                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space3) {
                        SectionHeader(title: "How the gates open")
                        HStack(alignment: .top, spacing: theme.metrics.space3) {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(theme.colors.primary)
                            Text("Snap meals on 5 different days this week — or land a 30-plant week early.")
                                .font(theme.typography.body())
                                .foregroundStyle(theme.colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(alignment: .top, spacing: theme.metrics.space3) {
                            Image(systemName: "leaf.fill")
                                .foregroundStyle(theme.colors.primary)
                            Text("Everything you eat already counts — your crews are getting fed while the map grows in.")
                                .font(theme.typography.body())
                                .foregroundStyle(theme.colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, theme.metrics.space5)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, theme.metrics.space6)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Garden, locked. Opens after your first week of logging.")
    }
}

// MARK: - Auth gate (email + Sign in with Apple, SPEC §3)

private struct ShellAuthGate: View {
    @Environment(\.theme) private var theme
    let auth: AuthService

    /// Two screens: the sign-in landing, and a DEDICATED create-account screen.
    /// "Create account" on the landing NAVIGATES here (it no longer POSTs an
    /// empty sign-up, which surfaced the "anonymous sign-ins disabled" error —
    /// owner report, 2026-07-10).
    private enum Mode { case signIn, createAccount }
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""

    private func switchTo(_ m: Mode) {
        mode = m
        auth.errorMessage = nil     // don't carry an error across screens
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space5) {
                VStack(alignment: .leading, spacing: theme.metrics.space2) {
                    Text(mode == .signIn ? "Relish" : "Create your account")
                        .font(theme.typography.display())
                        .foregroundStyle(theme.colors.primary)
                    Text(mode == .signIn ? "Grow a garden you can feed."
                                         : "Just an email and a password to get started.")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Card {
                    VStack(spacing: theme.metrics.space3) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                        if mode == .signIn {
                            PrimaryButton(title: "Sign in") { Task { await auth.signIn(email: email, password: password) } }
                            SecondaryButton(title: "Create account") { switchTo(.createAccount) }
                            SignInWithAppleButton(.signIn) { auth.prepareAppleRequest($0) }
                                onCompletion: { result in Task { await auth.handleAppleCompletion(result) } }
                                .frame(height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium))
                        } else {
                            PrimaryButton(title: "Create account") { Task { await auth.signUp(email: email, password: password) } }
                            Button("Already have an account? Sign in") { switchTo(.signIn) }
                                .font(theme.typography.caption(weight: .medium))
                                .foregroundStyle(theme.colors.primary)
                                .frame(maxWidth: .infinity)
                        }
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
