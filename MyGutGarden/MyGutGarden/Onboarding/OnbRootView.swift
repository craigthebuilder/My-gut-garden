//
//  OnbRootView.swift
//  MyGutGarden, Module A: the onboarding & intake flow (SPEC §6, §10).
//
//  THE module entry point. A warm, multi-step intake that:
//   - leads with Thrive's fun (never opens "how's your gut?"),
//   - captures goals, body basics, baseline, and the two-faced exclusions (§9),
//   - derives the fiber goal via the PURE OnbFiberGoal (est_daily_kcal stays
//     internal, only grams are ever shown on the Thrive summary, SPEC §10 / Fence 5),
//   - surfaces disclaimers as click-to-confirm (celiac/IBD ack, red-flag care
//     prompt), informs, never blocks,
//   - soft-routes to a suggested mode (suggestion, never a gate),
//   - shows truthful success stories.
//
//  Phase-2 (Batch B): summary branches on chosenMode.
//    Thrive: shows fiber_goal_g in grams.
//    Survive: shows calm low-residue framing, NO numeric ceiling.
//    residue_ceiling_g is NEVER surfaced here or anywhere in the UI.
//    // RD-REVIEW-REQUIRED on Survive summary copy.
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
            // Onboarding leads with Thrive's fun, so it themes Thrive regardless
            // of the eventual mode choice (DESIGN.md §6 / SPEC §6).
            .themed(for: .thrive)
    }

    private var content: some View {
        ThemedShell(vm: vm,
                    onChecksContinue: handleChecksContinue,
                    onStart: { Task { await vm.save() } })
            .task { await vm.loadSuccessStories() }
            .onChange(of: vm.didFinish) { _, done in
                if done { onFinished?(); vm.offerSurviveIfWarranted() }
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

        var parts: [String] = [
            "Conditions like these are serious and belong with your medical team. This app supports you; it does not replace your doctors."
        ]

        if hasAutoimmune || hasIbd {
            parts.append("If you have an autoimmune condition, your doctor is the right guide for dietary changes. We will keep your data private.")
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
        case .exclusions: OnbExclusionsStep(vm: vm)
        case .checks:     OnbChecksStep(vm: vm)
        case .summary:    summaryStep
        }
    }

    // MARK: Welcome (lead with Thrive's fun, SPEC §6)

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space5) {
            IllustrationPlaceholder(systemImage: "leaf.fill")
                .frame(height: 160)
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                Text("Grow a garden you can eat")
                    .font(theme.typography.display(34))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Snap your meals, fill a field guide of plants, and feed the invisible world that keeps you well. Two minutes to set up.")
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

    // MARK: Summary (Phase-2 Batch B: branch on chosenMode)
    //
    // Thrive: show fiber_goal_g in grams + auto-increase caption.
    // Survive: show calm framing, no numeric residue ceiling.
    //   residue_ceiling_g is INTERNAL ONLY; it is NEVER surfaced here.
    //   // RD-REVIEW-REQUIRED: Survive summary copy below.

    private var summaryStep: some View {
        OnbStepScaffold(title: "You're all set",
                        subtitle: "Here is where you are starting from.") {
            // R5 #4: everyone starts in Thrive. If signals lean relief we OFFER a
            // Survive reset right after, via a disclaimer pop-up (never auto-entered).
            thriveGoalCard
            if vm.shouldOfferSurvive { surviveOfferNote }
        }
    }

    // MARK: Thrive goal card
    // The ONLY anthropometric-derived number ever shown is the fiber goal in grams.
    // est_daily_kcal and residue_ceiling_g are never surfaced (SPEC §10 / Fence 5).

    private var thriveGoalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Text("Your daily fiber goal")
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                Text("\(vm.fiberGoalG) g")
                    .font(theme.typography.display(40))
                    .foregroundStyle(theme.colors.primary)
                Text("Reach it by eating a wide, colorful range of plants. We will help you get there, one snap at a time.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
                Text("We will raise this automatically as you consistently hit it.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Survive offer note
    // Shown only when signals lean relief. Everyone still STARTS in Thrive; the
    // actual Survive disclaimer pop-up fires after onboarding finishes (R5 #4).
    // // RD-REVIEW-REQUIRED: copy below is clinical-adjacent; confirm before launch.

    private var surviveOfferNote: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Label("A gentler start might help", systemImage: "leaf.circle")
                    .font(theme.typography.body(weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("From what you shared, a short low-residue reset could help settle things first. We'll offer it in a moment, no pressure, and you can always switch later.")
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
                let label = vm.chosenMode == .thrive ? "Start growing" : "Start"
                let icon  = vm.chosenMode == .thrive ? "leaf.fill" : "arrow.right"
                PrimaryButton(title: label, systemImage: icon) { onStart() }
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
