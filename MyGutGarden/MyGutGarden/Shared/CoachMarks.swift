//
//  CoachMarks.swift
//  MyGutGarden — the dim-page call-out tutorial system (SPEC §7, DESIGN §4).
//
//  A shared component so every surface teaches itself the same way: the screen
//  dims, a compact card explains WHAT this is and WHY it matters (curated copy from
//  `tutorial_steps`, never runtime-generated — rule #9), and the user taps Next or
//  Skip. Completion is tracked per section in `tutorial_state`; tours are replayable.
//  Health-claim steps carry an inline [emerging science] tag (Fence 4/8).
//

import SwiftUI
import Observation

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

/// The dim + call-out card overlay. Renders above everything; nil when idle.
struct CoachMarkOverlay: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let controller: CoachMarkController
    let appState: AppState

    var body: some View {
        if let step = controller.current {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: theme.metrics.space3) {
                    if let title = step.title {
                        Text(title)
                            .font(theme.typography.title())
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                    Text(step.body)
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if step.claimRisk {
                        Text("[emerging science]")
                            .font(theme.typography.caption(weight: .semibold))
                            .foregroundStyle(theme.colors.secondary)
                    }
                    HStack {
                        Button("Skip") { controller.skip(appState) }
                            .font(theme.typography.caption(weight: .semibold))
                            .foregroundStyle(theme.colors.textSecondary)
                        Spacer()
                        Text("\(controller.index + 1) / \(controller.activeSteps.count)")
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                        Spacer()
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
            .transition(reduceMotion ? .identity : .opacity)
        }
    }
}
