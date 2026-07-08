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
            // Horizontal padding so a `.fixedSize()` (compact) use never hugs
            // its label — the coach-mark "Next" squish fix (owner, 2026-07-02).
            .padding(.horizontal, theme.metrics.space4)
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
            .padding(.horizontal, theme.metrics.space4)
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

// Owner (2026-07-02): the visible "emerging science" tag was retired app-wide.
// `claim_risk` + `substantiation` remain in the data model as the RD-review
// ledger — see FENCES.md (Fences 1/4) for what still needs sign-off.

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

/// A 5-dot intensity band (owner decision, 2026-07-08) for loads that have no
/// gram scale a person would recognize — above all the fast-fermenting carb
/// band on "Your fiber". Filled count + the word carry the meaning together
/// (never color alone, accessibility floor); grams stay internal.
struct DotBand: View {
    @Environment(\.theme) private var theme
    let level: Int              // 0...max filled dots
    var max: Int = 5
    let label: String           // "quiet" … "a big day"

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            HStack(spacing: 4) {
                ForEach(0..<max, id: \.self) { i in
                    Circle()
                        .fill(i < level ? theme.colors.secondary
                                        : theme.colors.secondary.opacity(0.18))
                        .frame(width: 10, height: 10)
                }
            }
            Text(label)
                .font(theme.typography.caption(weight: .medium))
                .foregroundStyle(theme.colors.textSecondary)
        }
        .accessibilityElement()
        .accessibilityLabel("\(label), level \(level) of \(max)")
    }
}
