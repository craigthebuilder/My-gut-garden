//
//  ThrComponents.swift
//  MyGutGarden — Module C: small Thrive views composed from DesignSystem
//  primitives + Theme tokens. New compositions only — never restyling an
//  existing DesignSystem component (DESIGN.md, CLAUDE.md ownership rules).
//

import SwiftUI

// MARK: - Medical-allergy banner (LOUD across both modes — SPEC §9, rule #1)

/// Fires even mid-celebration on the Thrive surface. `medical_allergy` only —
/// `preference_intolerance` is silently omitted upstream and never reaches here.
struct ThrAllergyBanner: View {
    @Environment(\.theme) private var theme
    let alerts: [AllergyAlert]

    var body: some View {
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                ForEach(alerts, id: \.foodName) { alert in
                    HStack(alignment: .top, spacing: theme.metrics.space2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.colors.error)
                        Text("Heads up — this contains \(alert.foodName), one of your flagged allergies.")
                            .font(theme.typography.body(weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.metrics.space4)
            .background(theme.colors.error.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous)
                    .strokeBorder(theme.colors.error.opacity(0.5), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

// MARK: - The 3 P's (prebiotic / probiotic / polyphenol) — SPEC §11a

struct ThrThreePsRow: View {
    @Environment(\.theme) private var theme
    let threePs: ThreePs

    private struct P: Identifiable { let id: String; let title: String; let icon: String; let hit: Bool }

    private var items: [P] {
        [
            P(id: "pre", title: "Prebiotic", icon: "leaf.fill", hit: threePs.prebiotic),
            P(id: "pro", title: "Probiotic", icon: "drop.fill", hit: threePs.probiotic),
            P(id: "poly", title: "Polyphenol", icon: "sparkles", hit: threePs.polyphenol),
        ]
    }

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            ForEach(items) { p in
                VStack(spacing: theme.metrics.space1) {
                    Image(systemName: p.hit ? "checkmark.circle.fill" : p.icon)
                        .foregroundStyle(p.hit ? theme.colors.success : theme.colors.textSecondary)
                    Text(p.title)
                        .font(theme.typography.caption(weight: .medium))
                        .foregroundStyle(p.hit ? theme.colors.textPrimary : theme.colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, theme.metrics.space3)
                .background(p.hit ? theme.colors.success.opacity(0.12) : theme.colors.background)
                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(p.title): \(p.hit ? "done" : "not yet")")
            }
        }
    }
}

// MARK: - Radial goal card (the reference's hero arc — fiber goal / 30 plants)

/// Wraps the shared `ProgressArc` with a centered count + caption. Used for both
/// the daily fiber goal (grams — the ONLY surfaced anthropometric number, §10)
/// and weekly plant variety toward 30.
struct ThrGoalArcCard: View {
    @Environment(\.theme) private var theme
    let fraction: Double
    let centerValue: String
    let centerUnit: String
    let caption: String
    var accent: Color? = nil

    var body: some View {
        ZStack {
            ProgressArc(fraction: fraction, lineWidth: 14)
                .frame(width: 180, height: 180)
            VStack(spacing: theme.metrics.space1) {
                Text(centerValue)
                    .font(theme.typography.data(34, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text(centerUnit)
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(accent ?? theme.colors.accent)
                Text(caption)
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, theme.metrics.space1)
            }
            .padding(.horizontal, theme.metrics.space4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(centerValue) \(centerUnit). \(caption)")
    }
}

// MARK: - Curiosity fact (variable reward — curated, never generated — rule #9)

struct ThrCuriosityCard: View {
    @Environment(\.theme) private var theme
    let fact: String
    var confidenceTag: String? = nil

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                HStack(spacing: theme.metrics.space2) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .foregroundStyle(theme.colors.accent)
                    Text("Did you know?")
                        .font(theme.typography.caption(weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                    Spacer()
                    if let confidenceTag, confidenceTag != "solid" {
                        Badge(text: confidenceTag, tint: theme.colors.secondary)
                    }
                }
                Text(fact)
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Did you know? \(fact)")
    }
}

// MARK: - Navigation row (links from the home dashboard to the deeper surfaces)

struct ThrNavRow: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    var subtitle: String? = nil
    var locked = false

    var body: some View {
        HStack(spacing: theme.metrics.space3) {
            Image(systemName: locked ? "lock.fill" : icon)
                .foregroundStyle(locked ? theme.colors.textSecondary : theme.colors.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(.vertical, theme.metrics.space2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(locked ? "\(title), locked. \(subtitle ?? "")" : title)
    }
}

// MARK: - Streak chip (positive outcomes only — rule #7 / Fence 5)

struct ThrStreakChip: View {
    @Environment(\.theme) private var theme
    let count: Int
    let unit: String   // e.g. "week", "day"

    var body: some View {
        if count > 0 {
            HStack(spacing: theme.metrics.space1) {
                Image(systemName: "flame.fill").foregroundStyle(theme.colors.accent)
                Text("\(count) \(unit)\(count == 1 ? "" : "s") in a row")
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
            }
            .padding(.horizontal, theme.metrics.space3)
            .padding(.vertical, theme.metrics.space1)
            .background(theme.colors.accent.opacity(0.14))
            .clipShape(Capsule())
            .accessibilityLabel("Streak: \(count) \(unit)\(count == 1 ? "" : "s") in a row")
        }
    }
}
