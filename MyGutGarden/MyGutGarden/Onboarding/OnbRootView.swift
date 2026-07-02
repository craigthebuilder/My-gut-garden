//
//  OnbRootView.swift
//  MyGutGarden, Module A: the onboarding & intake flow (SPEC §6, §10).
//
//  THE module entry point. A warm, multi-step intake that:
//   - leads with the fun (never opens "how's your gut?"),
//   - captures goals, body basics, baseline, and food flags (§9 three-tier),
//   - derives the INTERNAL fiber numbers via the PURE OnbFiberGoal
//     (est_daily_kcal + fiber_target_g stay internal; no fiber number is shown
//     at onboarding, SPEC §10 / Fence 5),
//   - surfaces disclaimers as click-to-confirm (celiac/IBD ack, red-flag care
//     prompt), informs, never blocks,
//   - shows truthful success stories.
//
//  Single-mode: no routing, no modes, no Survive. The summary is a week-1
//  baseline quest that unlocks the fiber goal later; it shows NO number here.
//
//  Reads/writes only through AppState; composes DesignSystem components; reads
//  only Theme tokens. The shell injects `appState` and an `onFinished` hook.
//

import SwiftUI

struct OnbRootView: View {
    @State private var vm: OnbViewModel
    @State private var activeModal: OnbModal?
    private let onFinished: (() -> Void)?

    init(appState: AppState, onFinished: (() -> Void)? = nil) {
        _vm = State(initialValue: OnbViewModel(appState: appState))
        self.onFinished = onFinished
    }

    private enum OnbModal: Identifiable {
        case seriousConditions, redFlag
        var id: Int { hashValue }
    }

    var body: some View {
        content
            .themed()
    }

    private var content: some View {
        ThemedShell(vm: vm,
                    onChecksContinue: handleChecksContinue,
                    onStart: { Task { await vm.save() } })
            .task { await vm.loadSuccessStories() }
            .onChange(of: vm.didFinish) { _, done in
                if done { onFinished?() }
            }
            .overlay { modalOverlay }
    }

    // MARK: - Disclaimer sequencing (informs, never blocks, SPEC §6)

    private func handleChecksContinue() {
        if !vm.seriousConditions.isEmpty {
            activeModal = .seriousConditions
        } else if !vm.redFlags.isEmpty {
            activeModal = .redFlag
        } else {
            vm.advance()
        }
    }

    @ViewBuilder private var modalOverlay: some View {
        if let modal = activeModal {
            OnbModalScrim {
                switch modal {
                case .seriousConditions:
                    ConfirmationModal(
                        title: "Thanks for telling us",
                        message: seriousConditionsMessage,
                        confirmTitle: "I understand, continue",
                        cancelTitle: "Go back",
                        severity: .caution,
                        onConfirm: {
                            vm.acknowledgeSeriousConditions()
                            if !vm.redFlags.isEmpty {
                                activeModal = .redFlag
                            } else {
                                activeModal = nil
                                vm.advance()
                            }
                        },
                        onCancel: { activeModal = nil }
                    )
                case .redFlag:
                    ConfirmationModal(
                        title: "Worth a doctor's eyes",
                        message: "A few things you noted, like blood or unexplained weight loss, are worth getting checked in person. Keep using the app; this is a recommendation, not a stop sign.",
                        confirmTitle: "Got it, continue",
                        cancelTitle: "Go back",
                        severity: .carePrompt,
                        onConfirm: { activeModal = nil; vm.advance() },
                        onCancel: { activeModal = nil }
                    )
                }
            }
        }
    }

    private var seriousConditionsMessage: String {
        let celiac = vm.seriousConditions.contains(OnbSeriousCondition.celiac.key)
        let hasAutoimmune = vm.seriousConditions.contains(OnbSeriousCondition.otherAutoimmune.key)
        let hasIbd = vm.seriousConditions.contains(OnbSeriousCondition.ibd.key)

        // Medical/care copy ONLY — privacy reassurance lives on the checks step
        // itself, never mixed into a "see your doctor" message (owner, 2026-07-02).
        var parts: [String] = [
            "Conditions like these are serious and belong with your medical team. This app supports you; it does not replace your doctors."
        ]

        if hasAutoimmune || hasIbd {
            parts.append("If you have an autoimmune condition, your doctor is the right guide for dietary changes.")
        }

        if celiac {
            parts.append("We will add gluten as a loud allergy flag so it is caught even when hidden. You can change that any time.")
        }

        return parts.joined(separator: " ")
    }
}

// MARK: - Themed shell (header + step content + footer)

private struct ThemedShell: View {
    @Environment(\.theme) private var theme
    @Bindable var vm: OnbViewModel
    let onChecksContinue: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                stepContent
                    .padding(theme.metrics.space5)
            }
            footer
        }
        .background(theme.colors.background.ignoresSafeArea())
    }

    // MARK: Top bar

    @ViewBuilder private var topBar: some View {
        if vm.step != .welcome {
            HStack(spacing: theme.metrics.space3) {
                Button { vm.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.primary)
                }
                .accessibilityLabel("Back")
                OnbProgressDots(current: vm.step.progressIndex, total: OnbStep.progressTotal)
                Spacer()
            }
            .padding(.horizontal, theme.metrics.space5)
            .padding(.top, theme.metrics.space4)
        }
    }

    // MARK: Step content

    @ViewBuilder private var stepContent: some View {
        switch vm.step {
        case .welcome:    welcomeStep
        case .goals:      OnbGoalsStep(vm: vm)
        case .body:       OnbBodyStep(vm: vm)
        case .baseline:   OnbBaselineStep(vm: vm)
        case .flags:      OnbFlagsStep(vm: vm)
        case .checks:     OnbChecksStep(vm: vm)
        case .summary:    summaryStep
        }
    }

    // MARK: Welcome (lead with the fun, SPEC §6)
    //
    // ── OWNER-EDITABLE ────────────────────────────────────────────────────
    // • Title + subtitle: edit `OnbWelcomeCopy` just below.
    // • The plant picture: add an image named "OnboardingHero" to
    //   Assets.xcassets and it replaces the leaf placeholder automatically.
    // • The quote cards ("From people like you"): rows in the
    //   `success_stories` table — edit data/success_stories.csv, run
    //   data/build_seed_sql.py, and apply a seed refresh migration.

    private enum OnbWelcomeCopy {
        static let title = "Grow a garden you can eat"
        static let subtitle = "Snap your meals, fill a field guide of plants, and feed the invisible world that keeps you well. Two minutes to set up."
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space5) {
            IllustrationPlaceholder(systemImage: "leaf.fill", imageName: "OnboardingHero")
                .frame(height: 160)
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                Text(OnbWelcomeCopy.title)
                    .font(theme.typography.display(34))
                    .foregroundStyle(theme.colors.textPrimary)
                Text(OnbWelcomeCopy.subtitle)
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
            }
            successStories
        }
    }

    @ViewBuilder private var successStories: some View {
        if !vm.successStories.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "From people like you")
                ForEach(vm.successStories) { story in
                    Card {
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            Text("\u{201C}\(story.text)\u{201D}")
                                .font(theme.typography.body())
                                .foregroundStyle(theme.colors.textPrimary)
                            if let who = story.attribution {
                                HStack(spacing: theme.metrics.space2) {
                                    Text(", \(who)")
                                        .font(theme.typography.caption(weight: .medium))
                                        .foregroundStyle(theme.colors.textSecondary)
                                    if story.verified { Badge(text: "verified") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Summary — week-1 baseline quest
    //
    // Single-mode: NO fiber number is shown at onboarding. The surfaced fiber goal
    // is unlocked later, once the week-1 baseline quest is met (SPEC §10 / Fence 5).
    // est_daily_kcal + fiber_target_g are INTERNAL and never surfaced here.

    private var summaryStep: some View {
        OnbStepScaffold(title: "You're all set",
                        subtitle: "Here is where you are starting from.") {
            baselineQuestCard
        }
    }

    // MARK: Baseline-quest card
    // Replaces the old fiber-goal number. No anthropometric-derived number is ever
    // shown here; the goal in grams unlocks with the week-1 quest (SPEC §10 / Fence 5).

    private var baselineQuestCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Label("Your fiber goal unlocks this week", systemImage: "sparkles")
                    .font(theme.typography.body(weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Hit 30 plant foods and eat the rainbow \u{2014} we're learning your baseline.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: theme.metrics.space2) {
            if let error = vm.errorMessage {
                Text(error)
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            primaryAction
            if vm.step != .welcome && vm.step != .summary {
                SecondaryButton(title: "Back") { vm.goBack() }
            }
        }
        .padding(theme.metrics.space5)
        .background(theme.colors.surface.ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder private var primaryAction: some View {
        switch vm.step {
        case .welcome:
            PrimaryButton(title: "Begin", systemImage: "sparkles") { vm.advance() }
        case .checks:
            PrimaryButton(title: "Continue") { onChecksContinue() }
        case .summary:
            if vm.isSaving {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                PrimaryButton(title: "Start growing", systemImage: "leaf.fill") { onStart() }
            }
        default:
            PrimaryButton(title: "Continue") { vm.advance() }
        }
    }
}

// MARK: - Modal scrim

/// Dim + center a ConfirmationModal. Static (no entrance animation needed), so
/// it is inherently reduced-motion safe (DESIGN.md §3, §5).
private struct OnbModalScrim<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            content
        }
    }
}

// MARK: - Progress dots

/// Small step indicator (a real sequence, so ordered markers are legitimate,
/// DESIGN.md §2). Built from theme tokens; not a DesignSystem restyle.
private struct OnbProgressDots: View {
    @Environment(\.theme) private var theme
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: theme.metrics.space1) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? theme.colors.primary : theme.colors.divider)
                    .frame(width: i == current ? 18 : 8, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

#Preview {
    OnbRootView(appState: AppState(auth: AuthService()))
}
