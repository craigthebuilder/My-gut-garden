//
//  SrvOffRampView.swift
//  MyGutGarden, Module E. The blameless off-ramp from tracking
//  (🔒 Fence 5 / CLAUDE.md §3, rule #7; SPEC §14).
//
//  Tracking should help, not stress. This screen makes softening, pausing, or
//  leaving tracking easy and shame-free, reachable directly from the Survive
//  home. Nothing here frames stopping as failure; switching to Thrive is "back
//  to basics," not a demotion (SPEC §2). No streak, count, or restriction
//  metric is shown here.
//

import SwiftUI

struct SrvOffRampView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: SrvStore

    @State private var confirmLeave = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    intro

                    option(
                        title: "Keep the full check-in",
                        body: "The complete ~20-second evening read. Best when you're actively trigger-finding.",
                        systemImage: "checklist",
                        isOn: store.trackingPreference == .full
                    ) { store.trackingPreference = .full }

                    option(
                        title: "Switch to a light check-in",
                        body: "Just the essentials, form, gas, and how you felt. Fewer taps, less to think about.",
                        systemImage: "minus.circle",
                        isOn: store.trackingPreference == .lite
                    ) { store.trackingPreference = .lite }

                    option(
                        title: "Pause tracking for now",
                        body: "Take a break whenever you like. Everything you've logged stays exactly where it is.",
                        systemImage: "pause.circle",
                        isOn: store.trackingPreference == .paused
                    ) { store.trackingPreference = .paused }

                    leaveCard
                }
                .padding(theme.metrics.space4)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Tracking, your way")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.colors.primary)
                }
            }
            .sheet(isPresented: $confirmLeave) {
                ConfirmationModal(
                    title: "Move to Thrive?",
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
        Text("Tracking is here to help you feel better, not to be one more thing to keep up. Choose what fits right now.")
            .font(theme.typography.body())
            .foregroundStyle(theme.colors.textSecondary)
    }

    private func option(title: String, body: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Card {
                HStack(alignment: .top, spacing: theme.metrics.space3) {
                    Image(systemName: systemImage)
                        .font(.system(size: 22))
                        .foregroundStyle(isOn ? theme.colors.primary : theme.colors.textSecondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: theme.metrics.space1) {
                        Text(title)
                            .font(theme.typography.body(weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                        Text(body)
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    Spacer()
                    if isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.colors.primary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var leaveCard: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text("Feeling steady?")
                .font(theme.typography.title(18))
                .foregroundStyle(theme.colors.textPrimary)
            Text("If symptoms have settled, you might be ready for the garden side. It's a step forward, not a goodbye.")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
            SecondaryButton(title: "Move to Thrive", systemImage: "arrow.forward.circle") {
                confirmLeave = true
            }
        }
        .padding(.top, theme.metrics.space3)
    }
}
