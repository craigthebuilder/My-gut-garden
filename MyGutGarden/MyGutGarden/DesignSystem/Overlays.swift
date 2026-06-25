//
//  Overlays.swift
//  MyGutGarden — celebration + confirmation surfaces.
//
//  CelebrationOverlay is the orchestrated reward moment (guild bloom, rare-find,
//  graduation — the signature juice, Thrive only). ConfirmationModal is the
//  disclaimer / click-to-confirm gate (A celiac/IBD ack + red-flag, mode switch).
//  Both respect reduced motion (DESIGN.md §3, §5).
//

import SwiftUI

/// Full-screen celebratory moment. Confetti/scale when motion is allowed; a
/// calm static acknowledgment when reduced (never "reward restriction").
struct CelebrationOverlay: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let message: String
    var systemImage: String = "sparkles"
    var tint: Color? = nil
    var onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(spacing: theme.metrics.space4) {
                Image(systemName: systemImage)
                    .font(.system(size: 64))
                    .foregroundStyle(tint ?? theme.colors.accent)
                    .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.6))
                Text(title)
                    .font(theme.typography.display(30))
                    .foregroundStyle(theme.colors.primary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "Lovely", action: onDismiss)
                    .fixedSize()
            }
            .padding(theme.metrics.space6)
            .background(theme.colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusLarge, style: .continuous))
            .padding(theme.metrics.space5)
            .opacity(reduceMotion ? 1 : (appeared ? 1 : 0))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
        .accessibilityAddTraits(.isModal)
    }
}

/// Disclaimer + click-to-confirm. Nobody is locked out (SPEC §6): the modal
/// informs, the user acknowledges, then proceeds. `severity` shifts tone.
struct ConfirmationModal: View {
    @Environment(\.theme) private var theme
    let title: String
    let message: String
    var confirmTitle: String = "I understand — continue"
    var cancelTitle: String? = "Not now"
    var severity: Severity = .info
    var onConfirm: () -> Void
    var onCancel: (() -> Void)? = nil

    enum Severity { case info, caution, carePrompt }

    private var tint: Color {
        switch severity {
        case .info: theme.colors.primary
        case .caution: theme.colors.warning
        case .carePrompt: theme.colors.error
        }
    }
    private var symbol: String {
        switch severity {
        case .info: "info.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .carePrompt: "cross.case.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            HStack(spacing: theme.metrics.space2) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(theme.typography.title())
                    .foregroundStyle(theme.colors.textPrimary)
            }
            Text(message)
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
            PrimaryButton(title: confirmTitle, action: onConfirm)
            if let cancelTitle {
                SecondaryButton(title: cancelTitle) { (onCancel ?? {})() }
            }
        }
        .padding(theme.metrics.space5)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusLarge, style: .continuous))
        .padding(theme.metrics.space4)
        .accessibilityElement(children: .contain)
    }
}
