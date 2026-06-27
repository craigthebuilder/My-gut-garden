//
//  SrvOffRampView.swift
//  MyGutGarden, Module E. The blameless off-ramp from Survive
//  (🔒 Fence 5 / CLAUDE.md §3, rule #7; SPEC §14).
//
//  Tracking should help, not stress. R4: there is no "lighter check-in" (it
//  undercut the reset's methodical logging). The two ways out are PAUSE the
//  Survive episode (progress is kept, nothing is lost) and RETURN TO THRIVE, the
//  full, healthy exit from restriction. Nothing here frames stopping as failure;
//  no streak, count, or restriction metric is shown.
//

import SwiftUI

struct SrvOffRampView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: SrvStore
    @Bindable var resetModel: SrvResetModel

    @State private var confirmLeave = false

    private var isPaused: Bool { resetModel.reset?.pausedAt != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    intro
                    pauseCard
                    leaveCard
                }
                .padding(theme.metrics.space4)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Survive, your way")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(theme.colors.primary)
                }
            }
            .sheet(isPresented: $confirmLeave) {
                ConfirmationModal(
                    title: "Return to Thrive?",
                    message: "We'll switch you to the garden side, same data, lighter touch. You can come back to Survive anytime it helps.",
                    confirmTitle: "Take me to Thrive",
                    cancelTitle: "Stay here",
                    severity: .info,
                    onConfirm: {
                        confirmLeave = false
                        Task { await store.leaveSurvive(); dismiss() }
                    },
                    onCancel: { confirmLeave = false }
                )
                .presentationDetents([.medium])
            }
        }
    }

    private var intro: some View {
        Text("Survive is here to help you feel better, not to be one more thing to keep up. You can pause it, or head back to Thrive whenever you like.")
            .font(theme.typography.body())
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var pauseCard: some View {
        Card {
            HStack(alignment: .top, spacing: theme.metrics.space3) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.colors.primary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: theme.metrics.space2) {
                    Text(isPaused ? "Survive is paused" : "Pause Survive")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(isPaused
                         ? "Everything you've logged is saved. Resume whenever you're ready."
                         : "Take a break whenever you like. Nothing is lost, and you can resume right where you left off.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(isPaused ? "Resume" : "Pause anytime") {
                        Task { isPaused ? await resetModel.resume() : await resetModel.pause() }
                    }
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.primary)
                }
                Spacer()
            }
        }
    }

    private var leaveCard: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text("Feeling steady?")
                .font(theme.typography.title(18))
                .foregroundStyle(theme.colors.textPrimary)
            Text("If symptoms have settled, you might be ready for the garden side. It's a step forward, not a goodbye.")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SecondaryButton(title: "Return to Thrive", systemImage: "arrow.forward.circle") {
                confirmLeave = true
            }
        }
        .padding(.top, theme.metrics.space3)
    }
}
