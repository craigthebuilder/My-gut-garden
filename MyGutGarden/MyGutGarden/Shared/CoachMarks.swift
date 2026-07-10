//
//  CoachMarks.swift
//  MyGutGarden — the dim-page spotlight tutorial system (SPEC §7, DESIGN §4).
//
//  A shared component so every surface teaches itself the same way: the screen
//  dims with a CUTOUT around the step's target (views register themselves via
//  `.coachTarget("hint")`, matched to `tutorial_steps.target_hint`), a compact
//  card sits beside the spotlight explaining WHAT this is and WHY it matters
//  (curated copy, never runtime-generated — rule #11), and the user moves with
//  Back / Next / Skip. Steps can walk the app: the overlay reports each step's
//  hint via `onNavigate` and the shell switches tabs so the tour visits the
//  real surfaces. When a step's target isn't on screen the card centers over a
//  plain dim (never blocks). Completion is tracked per section in
//  `tutorial_state`; tours are replayable from You.
//

import SwiftUI
import Observation

// MARK: - Target registration

/// Collected map of coach-target anchors, keyed by `tutorial_steps.target_hint`.
struct CoachTargetKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Register this view as the spotlight target for tutorial steps whose
    /// `target_hint` equals `key`.
    func coachTarget(_ key: String) -> some View {
        anchorPreference(key: CoachTargetKey.self, value: .bounds) { [key: $0] }
    }
}

// MARK: - Controller

@MainActor
@Observable
final class CoachMarkController {
    private(set) var activeSteps: [TutorialStepRow] = []
    private(set) var index = 0
    private(set) var sectionKey: String?
    private var completed: Set<String> = []

    var isShowing: Bool { !activeSteps.isEmpty && index < activeSteps.count }
    var current: TutorialStepRow? { isShowing ? activeSteps[index] : nil }
    var isLast: Bool { index + 1 >= activeSteps.count }
    var isFirst: Bool { index == 0 }

    private struct CompletedRow: Decodable { let sectionKey: String }

    func loadCompleted(_ appState: AppState) async {
        guard let repo = appState.repository, let uid = appState.profile?.id else { return }
        let rows: [CompletedRow] = (try? await repo.select(
            "tutorial_state", columns: "section_key", filters: ["user_id": "eq.\(uid)"])) ?? []
        completed = Set(rows.map(\.sectionKey))
    }

    /// Start the section's tour only if the user hasn't completed it (first-run tours).
    func startIfNeeded(_ sectionKey: String, appState: AppState) async {
        guard !completed.contains(sectionKey), !isShowing else { return }
        await start(sectionKey, appState: appState)
    }

    /// Force-start a tour (e.g. a "replay" button in You).
    func start(_ sectionKey: String, appState: AppState) async {
        guard let repo = appState.repository else { return }
        let steps: [TutorialStepRow] = (try? await repo.select(
            "tutorial_steps", filters: ["section_key": "eq.\(sectionKey)"], order: "order")) ?? []
        guard !steps.isEmpty else { return }
        self.sectionKey = sectionKey
        self.activeSteps = steps
        self.index = 0
    }

    func next(_ appState: AppState) {
        if index + 1 < activeSteps.count { index += 1 } else { finish(appState) }
    }

    func back() {
        if index > 0 { index -= 1 }
    }

    func skip(_ appState: AppState) { finish(appState) }

    private func finish(_ appState: AppState) {
        if let sk = sectionKey {
            completed.insert(sk)
            Task { [weak appState] in
                guard let appState, let repo = appState.repository, let uid = appState.profile?.id else { return }
                try? await repo.upsert("tutorial_state",
                    ["user_id": .string(uid), "section_key": .string(sk), "completed_at": .date(Date())],
                    onConflict: "user_id,section_key")
            }
        }
        activeSteps = []; index = 0; sectionKey = nil
    }
}

// MARK: - Overlay (dim + spotlight cutout + anchored card)

struct CoachMarkOverlay: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let controller: CoachMarkController
    let appState: AppState
    /// Anchors registered by `.coachTarget(_:)` below this overlay in the tree.
    var anchors: [String: Anchor<CGRect>] = [:]
    /// The shell hooks this to switch tabs so a tour can walk the app.
    var onNavigate: ((String) -> Void)? = nil

    private let spotlightPadding: CGFloat = 8

    var body: some View {
        if let step = controller.current {
            GeometryReader { proxy in
                let rect = step.targetHint.flatMap { hint in
                    anchors[hint].map { proxy[$0] }
                }
                ZStack(alignment: .topLeading) {
                    dimLayer(spotlight: rect)
                        .onTapGesture { controller.next(appState) }
                    if let rect {
                        RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous)
                            .strokeBorder(theme.colors.accent, lineWidth: 2)
                            .frame(width: rect.width + spotlightPadding * 2,
                                   height: rect.height + spotlightPadding * 2)
                            .position(x: rect.midX, y: rect.midY)
                            .accessibilityHidden(true)
                    }
                    card(step, spotlight: rect, in: proxy.size)
                }
            }
            // Reserve the bottom tab-bar strip: the dim covers the content +
            // status area but NOT the tab bar, so a user can still switch tabs
            // during a tour instead of feeling frozen (the shell ends the tour
            // when they navigate away). 2026-07-10.
            .padding(.bottom, 90)
            .ignoresSafeArea(edges: [.top, .horizontal])
            .transition(reduceMotion ? .identity : .opacity)
            .onAppear { if let hint = step.targetHint { onNavigate?(hint) } }
            .onChange(of: controller.current?.targetHint) { _, hint in
                if let hint { onNavigate?(hint) }
            }
        }
    }

    /// The dim with a punched-out spotlight around the target (plain dim when
    /// the step has no on-screen target). Static, so reduced-motion safe.
    private func dimLayer(spotlight rect: CGRect?) -> some View {
        Color.black.opacity(0.55)
            .mask {
                Rectangle()
                    .overlay {
                        if let rect {
                            RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous)
                                .frame(width: rect.width + spotlightPadding * 2,
                                       height: rect.height + spotlightPadding * 2)
                                .position(x: rect.midX, y: rect.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
            }
            .accessibilityHidden(true)
    }

    /// The call-out card: below the spotlight when the target sits in the top
    /// half, above it otherwise, centered when there's no target.
    @ViewBuilder
    private func card(_ step: TutorialStepRow, spotlight rect: CGRect?, in size: CGSize) -> some View {
        VStack(spacing: 0) {
            if let rect, rect.midY < size.height / 2 {
                Color.clear.frame(height: min(rect.maxY + spotlightPadding * 2, size.height * 0.62))
                cardContent(step)
                Spacer(minLength: theme.metrics.space5)
            } else if let rect {
                Spacer(minLength: theme.metrics.space5)
                cardContent(step)
                Color.clear.frame(height: min(max(size.height - rect.minY + spotlightPadding * 2,
                                                  theme.metrics.space5),
                                              size.height * 0.62))
            } else {
                Spacer()
                cardContent(step)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Personalize seed copy with the user's chosen gardener name: any
    /// "{gardener}" token becomes their name (owner, 2026-07-09) so the tour can
    /// speak as their guide without baking a name into static seed data.
    private func personalize(_ text: String) -> String {
        text.replacingOccurrences(of: "{gardener}", with: appState.profile?.gardenerDisplayName ?? "Sprout")
    }

    private func cardContent(_ step: TutorialStepRow) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.space3) {
            if let title = step.title {
                Text(personalize(title))
                    .font(theme.typography.title())
                    .foregroundStyle(theme.colors.textPrimary)
            }
            Text(personalize(step.body))
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: theme.metrics.space2) {
                Button("Skip") { controller.skip(appState) }
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer()
                Text("\(controller.index + 1) / \(controller.activeSteps.count)")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer()
                if !controller.isFirst {
                    SecondaryButton(title: "Back") { controller.back() }
                        .fixedSize()
                }
                PrimaryButton(title: controller.isLast ? "Got it" : "Next") {
                    controller.next(appState)
                }
                .fixedSize()
            }
            .padding(.top, theme.metrics.space2)
        }
        .padding(theme.metrics.space5)
        .frame(maxWidth: theme.metrics.calloutMaxWidth)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusLarge, style: .continuous))
        .padding(theme.metrics.space5)
        .accessibilityAddTraits(.isModal)
    }
}
