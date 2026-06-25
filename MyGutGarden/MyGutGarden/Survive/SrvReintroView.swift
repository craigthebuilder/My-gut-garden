//
//  SrvReintroView.swift
//  MyGutGarden — Module E. Reintro-as-leveling (SPEC §11b, §13; Fence 3).
//
//  Each FODMAP group is a level to clear. Starting a challenge begins the
//  testing window (length from GameConfig — Fence 3); clearing it unlocks the
//  food back into the collection (a visible win) and advances the symptom-free
//  streak. Framing is relief + progress — NEVER gamified restriction (rule #7):
//  a "failed" challenge is a blameless "needs a rest", retry-able later.
//

import SwiftUI

struct SrvReintroView: View {
    @Environment(\.theme) private var theme
    @Bindable var store: SrvStore

    private var ordered: [SrvChallenge] {
        // Stable display order: by canonical group order.
        SrvFodmapGroup.allCases.compactMap { group in
            store.challenges.first { $0.group == group }
                ?? SrvChallenge(id: "new-\(group.rawValue)", group: group, status: .pending, startedAt: nil, endedAt: nil)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                header
                ForEach(ordered) { challenge in
                    SrvChallengeRow(store: store, challenge: challenge)
                }
                fenceNote
            }
            .padding(theme.metrics.space4)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Reintroductions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text("One group at a time")
                .font(theme.typography.title())
                .foregroundStyle(theme.colors.textPrimary)
            Text("Test a fiber group back in over \(SrvReintroEngine.challengeDays) days. Clear it and the foods it gates rejoin your collection.")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var fenceNote: some View {
        Text("Phase lengths are starting points your dietitian can tune.")
            .font(theme.typography.caption())
            .foregroundStyle(theme.colors.textSecondary)
    }
}

struct SrvChallengeRow: View {
    @Environment(\.theme) private var theme
    let store: SrvStore
    let challenge: SrvChallenge

    private var isResolved: Bool { challenge.status == .passed || challenge.status == .failed }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(challenge.group.displayName)
                            .font(theme.typography.body(weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                        Text("e.g. \(challenge.group.exampleFood)")
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    Spacer()
                    Label(challenge.status.label, systemImage: challenge.status.systemImage)
                        .font(theme.typography.caption(weight: .medium))
                        .foregroundStyle(statusTint)
                }

                if challenge.status == .testing {
                    testingDetail
                }

                actions
            }
        }
    }

    @ViewBuilder private var testingDetail: some View {
        let progress = SrvReintroEngine.progress(challenge, now: Date())
        VStack(alignment: .leading, spacing: theme.metrics.space1) {
            ProgressView(value: progress)
                .tint(theme.colors.primary)
            Text(SrvReintroEngine.isWindowComplete(challenge, now: Date())
                 ? "Window complete — how did it go?"
                 : "Keep eating a little each day. We'll watch how you feel.")
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    @ViewBuilder private var actions: some View {
        switch challenge.status {
        case .pending, .failed:
            SecondaryButton(title: challenge.status == .failed ? "Try this one again" : "Start this challenge",
                            systemImage: "play.circle") {
                Task { await store.startChallenge(challenge.group) }
            }
        case .testing:
            HStack(spacing: theme.metrics.space2) {
                PrimaryButton(title: "Felt fine", systemImage: "checkmark") {
                    Task { await store.resolveChallenge(challenge, tolerated: true) }
                }
                SecondaryButton(title: "Rough", systemImage: "arrow.counterclockwise") {
                    Task { await store.resolveChallenge(challenge, tolerated: false) }
                }
            }
        case .passed:
            Label("Cleared — these foods are back in your collection.", systemImage: "checkmark.seal.fill")
                .font(theme.typography.caption(weight: .medium))
                .foregroundStyle(theme.colors.safetyGreen)
        }
    }

    private var statusTint: Color {
        switch challenge.status {
        case .pending: theme.colors.textSecondary
        case .testing: theme.colors.primary
        case .passed: theme.colors.safetyGreen
        case .failed: theme.colors.warning
        }
    }
}
