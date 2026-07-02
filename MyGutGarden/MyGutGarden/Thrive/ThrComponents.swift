//
//  ThrComponents.swift
//  MyGutGarden, Module C: small Thrive views composed from DesignSystem
//  primitives + Theme tokens. New compositions only, never restyling an
//  existing DesignSystem component (DESIGN.md, CLAUDE.md ownership rules).
//

import SwiftUI

// MARK: - Allergy banner (LOUD, fires before the overview, SPEC §9, rule #1)

/// Fires even mid-celebration on the Thrive surface. `allergyAlerts` carry the
/// `.allergy` FlagTier only (server-computed); softer tiers never reach here.
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
                        Text("Heads up, this contains \(alert.foodName), one of your flagged allergies.")
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

// MARK: - The 3 P's (prebiotic / probiotic / polyphenol), SPEC §11a

/// Relative amount per P from today's coarse portion tiers (rule #3). A hit is
/// any amount; the tile turns fully green with white text only when a lot landed.
struct ThrThreePAmounts: Sendable, Equatable {
    var prebiotic: ThrColorAmount
    var probiotic: ThrColorAmount
    var polyphenol: ThrColorAmount

    init(prebiotic: ThrColorAmount = .none, probiotic: ThrColorAmount = .none, polyphenol: ThrColorAmount = .none) {
        self.prebiotic = prebiotic
        self.probiotic = probiotic
        self.polyphenol = polyphenol
    }
    /// Map a yes/no `ThreePs` to amounts (a hit reads as a serving for display).
    init(presence p: ThreePs) {
        self.init(prebiotic: p.prebiotic ? .serving : .none,
                  probiotic: p.probiotic ? .serving : .none,
                  polyphenol: p.polyphenol ? .serving : .none)
    }

    var prebioticHit: Bool { prebiotic.countsTowardSix }
    var probioticHit: Bool { probiotic.countsTowardSix }
    var polyphenolHit: Bool { polyphenol.countsTowardSix }
    var count: Int { (prebioticHit ? 1 : 0) + (probioticHit ? 1 : 0) + (polyphenolHit ? 1 : 0) }
    var allThree: Bool { count == 3 }
    /// Yes/no shape for nudge copy.
    var hits: ThreePs { ThreePs(prebiotic: prebioticHit, probiotic: probioticHit, polyphenol: polyphenolHit) }
}

struct ThrThreePsRow: View {
    @Environment(\.theme) private var theme
    let amounts: ThrThreePAmounts

    private struct P: Identifiable { let id: String; let title: String; let icon: String; let amount: ThrColorAmount }

    private var items: [P] {
        [
            P(id: "pre", title: "Prebiotic", icon: "leaf.fill", amount: amounts.prebiotic),
            P(id: "pro", title: "Probiotic", icon: "drop.fill", amount: amounts.probiotic),
            P(id: "poly", title: "Polyphenol", icon: "sparkles", amount: amounts.polyphenol),
        ]
    }

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            ForEach(items) { p in
                let hit = p.amount.countsTowardSix
                let full = p.amount.isFull
                VStack(spacing: theme.metrics.space1) {
                    Image(systemName: hit ? "checkmark.circle.fill" : p.icon)
                        .foregroundStyle(full ? theme.colors.surface
                                         : (hit ? theme.colors.success : theme.colors.textSecondary))
                    Text(p.title)
                        .font(theme.typography.caption(weight: .medium))
                        .foregroundStyle(full ? theme.colors.surface
                                         : (hit ? theme.colors.textPrimary : theme.colors.textSecondary))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, theme.metrics.space3)
                // Fill deepens with the amount; fully green only at "lots".
                .background(full ? theme.colors.success
                            : theme.colors.success.opacity(Double(p.amount.ringsFilled) * 0.12))
                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(p.title): \(hit ? "done" : "not yet")")
            }
        }
    }
}

// MARK: - Compact fiber mini-bar (header top-right; the only surfaced number, §10)

/// A small capsule fill + "Xg / Yg", token-driven, with a "directional" caption.
/// Fiber in grams is the ONLY anthropometric-derived number ever shown (rule #6);
/// kcal/deficit are never surfaced.
struct ThrFiberMiniBar: View {
    @Environment(\.theme) private var theme
    let consumedG: Double
    let goalG: Int?
    let fraction: Double

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let goal = goalG {
                Text("\(Int(consumedG.rounded()))g / \(goal)g")
                    .font(theme.typography.data(13, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.colors.divider)
                        Capsule().fill(theme.colors.accent)
                            .frame(width: max(4, geo.size.width * CGFloat(max(0, min(1, fraction)))))
                    }
                }
                .frame(width: 88, height: 6)
                Text("fiber, directional")
                    .font(theme.typography.caption(11))
                    .foregroundStyle(theme.colors.textSecondary)
            } else {
                Text("Fiber goal in setup")
                    .font(theme.typography.caption(11))
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(goalG.map { "Fiber today \(Int(consumedG.rounded())) of \($0) grams, directional" } ?? "Fiber goal pending setup")
    }
}

/// One-line fiber readout for the full-width header (R3 Batch A): label + count +
/// a short inline bar, all on a single line. Fiber in grams is the ONLY
/// anthropometric-derived number ever shown (rule #6).
struct ThrFiberLine: View {
    @Environment(\.theme) private var theme
    let consumedG: Double
    let goalG: Int?
    let fraction: Double

    var body: some View {
        if let goal = goalG {
            HStack(spacing: theme.metrics.space2) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.accent)
                Text("Fiber \(Int(consumedG.rounded())) / \(goal) g")
                    .font(theme.typography.data(14, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.colors.divider).frame(width: 72, height: 6)
                    Capsule().fill(theme.colors.accent)
                        .frame(width: max(4, 72 * CGFloat(max(0, min(1, fraction)))), height: 6)
                }
                Text("directional")
                    .font(theme.typography.caption(11))
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Fiber today \(Int(consumedG.rounded())) of \(goal) grams, directional")
        } else {
            Text("Fiber goal in setup")
                .font(theme.typography.caption(11))
                .foregroundStyle(theme.colors.textSecondary)
        }
    }
}

// MARK: - Radial goal card (the reference's hero arc, fiber goal / 30 plants)

/// Wraps the shared `ProgressArc` with a centered count + caption. Used for both
/// the daily fiber goal (grams, the ONLY surfaced anthropometric number, §10)
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
                    .frame(maxWidth: 116)        // keep the caption inside the arc (R3 Batch A)
                    .padding(.top, theme.metrics.space1)
            }
            .padding(.horizontal, theme.metrics.space4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(centerValue) \(centerUnit). \(caption)")
    }
}

// MARK: - Curiosity fact (variable reward, curated, never generated, rule #9)

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

// MARK: - Streak chip (positive outcomes only, rule #7 / Fence 5)

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
