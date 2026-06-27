//
//  Components.swift
//  MyGutGarden, shared DesignSystem primitives (Phase 1 scaffolding).
//
//  Every module composes these instead of re-styling, so the app reads as one
//  product (DESIGN.md). They read ONLY Theme tokens, never hardcode a color,
//  font, spacing, or radius. VoiceOver labels + reduced-motion are baked in.
//  Visual language derived from design/references/* (DESIGN.md §4).
//

import SwiftUI

// MARK: - Surfaces

/// Standard parchment surface card.
struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    var padded = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padded ? theme.metrics.space4 : 0)
            .background(theme.colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous)
                    .strokeBorder(theme.colors.divider, lineWidth: 1)
            )
            .shadow(color: .black.opacity(theme.metrics.shadowOpacity),
                    radius: theme.metrics.shadowRadius, y: 4)
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.metrics.space2) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(theme.typography.body(weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.metrics.space3)
        }
        .background(theme.colors.primary)
        .foregroundStyle(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
    }
}

struct SecondaryButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.metrics.space2) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(theme.typography.body(weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.metrics.space3)
        }
        .foregroundStyle(theme.colors.primary)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous)
                .strokeBorder(theme.colors.primary.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Labels / indicators

struct SectionHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(theme.typography.title(20))
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct Badge: View {
    @Environment(\.theme) private var theme
    let text: String
    var tint: Color? = nil

    var body: some View {
        Text(text)
            .font(theme.typography.caption(weight: .semibold))
            .padding(.horizontal, theme.metrics.space3)
            .padding(.vertical, theme.metrics.space1)
            .background((tint ?? theme.colors.secondary).opacity(0.18))
            .foregroundStyle(tint ?? theme.colors.textSecondary)
            .clipShape(Capsule())
    }
}

struct StatPill: View {
    @Environment(\.theme) private var theme
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(theme.typography.data(20))
                .foregroundStyle(theme.colors.primary)
            Text(label)
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(theme.metrics.space3)
        .background(theme.colors.background)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// Fence 2, render on any guild whose `claim_risk == true` so an associational/
/// emerging claim never reads as established. Never ship the bare name.
struct EmergingScienceTag: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.metrics.space1) {
            Image(systemName: "sparkles")
            Text("emerging science")
        }
        .font(theme.typography.caption(weight: .medium))
        .padding(.horizontal, theme.metrics.space2)
        .padding(.vertical, 2)
        .background(theme.colors.warning.opacity(0.18))
        .foregroundStyle(theme.colors.warning)
        .clipShape(Capsule())
        .accessibilityLabel("Emerging science, not an established claim")
    }
}

/// FODMAP safety (Survive). Color + SHAPE + LABEL so it is never color-alone
/// (DESIGN.md §5 accessibility); legible but gentle, never a shame signal.
struct SafetyChip: View {
    @Environment(\.theme) private var theme
    let safety: FodmapSafety

    private var color: Color {
        switch safety {
        case .green: theme.colors.safetyGreen
        case .yellow: theme.colors.safetyYellow
        case .red: theme.colors.safetyRed
        }
    }
    private var symbol: String {
        switch safety {
        case .green: "checkmark.circle.fill"
        case .yellow: "exclamationmark.circle.fill"
        case .red: "minus.circle.fill"
        }
    }
    private var label: String {
        switch safety {
        case .green: "Safe serving"
        case .yellow: "Caution"
        case .red: "Likely trigger"
        }
    }

    var body: some View {
        HStack(spacing: theme.metrics.space1) {
            Image(systemName: symbol)
            Text(label)
        }
        .font(theme.typography.caption(weight: .medium))
        .padding(.horizontal, theme.metrics.space2)
        .padding(.vertical, 3)
        .background(color.opacity(0.16))
        .foregroundStyle(color)
        .clipShape(Capsule())
        .accessibilityLabel("FODMAP: \(label)")
    }
}

/// Radial progress (the dashboard arc from the reference; e.g. fiber goal).
struct ProgressArc: View {
    @Environment(\.theme) private var theme
    let fraction: Double         // 0...1
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(theme.colors.divider, style: .init(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: 0.75 * max(0, min(1, fraction)))
                .stroke(theme.colors.accent, style: .init(lineWidth: lineWidth, lineCap: .round))
        }
        .rotationEffect(.degrees(135))
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent of goal")
    }
}

/// Corner botanical flourish (placeholder for the owner's ornament art).
struct BotanicalFlourish: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: 14))
            .foregroundStyle(theme.colors.secondary.opacity(0.5))
            .accessibilityHidden(true)
    }
}
