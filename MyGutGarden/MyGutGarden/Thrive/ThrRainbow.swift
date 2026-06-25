//
//  ThrRainbow.swift
//  MyGutGarden — Module C: the "eat the rainbow" surface (SPEC §8, §10, §11a).
//
//  Shows which color groups the user has hit, which are weak (only a trace),
//  and which are missing; tapping a color opens its curated education (meaning +
//  what it does for the gut), loaded from the `colors` table with a curated
//  fallback (CLAUDE.md rule #9 — curated content, never runtime generation).
//
//  ── One documented exception to "never hardcode a color" (DESIGN.md §2/§5):
//  the rainbow's whole point is the six literal hues, which are *content* (the
//  food-color groups), not brand tokens. We render them with SwiftUI's adaptive
//  *named system* colors (no brand hexes), and ALWAYS pair the swatch with a
//  text label + collected/weak/missing wording so meaning is never color-alone.
//  Owner could later promote these to real rainbow tokens in Theme.swift.
//

import SwiftUI

// MARK: - Rainbow groups (raw values match the `color_name` enum, SPEC §5)

enum ThrRainbowGroup: String, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green
    case bluePurple = "blue_purple"
    case whiteBrown = "white_brown"

    var id: String { rawValue }

    /// Display label (sentence-cased; compound groups read naturally).
    var label: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .bluePurple: "Blue & purple"
        case .whiteBrown: "White & brown"
        }
    }

    /// Adaptive system hue for the swatch (see file header — content, not brand).
    var swatch: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .bluePurple: .purple
        case .whiteBrown: .brown
        }
    }
}

// MARK: - Per-color state

enum ThrColorState: Sendable, Equatable {
    case hit       // logged a real serving this week
    case weak      // only a trace — nudge for more
    case missing   // not yet this week — an invitation
}

/// This week's rainbow coverage, keyed by `color_name`. Defaults to all missing
/// (an empty screen that invites action — DESIGN.md "Writing").
struct ThrRainbowStatus: Sendable, Equatable {
    var states: [String: ThrColorState] = [:]

    func state(for group: ThrRainbowGroup) -> ThrColorState {
        states[group.rawValue] ?? .missing
    }

    var hitCount: Int { ThrRainbowGroup.allCases.filter { state(for: $0) == .hit }.count }
    var missing: [ThrRainbowGroup] { ThrRainbowGroup.allCases.filter { state(for: $0) == .missing } }
    var weak: [ThrRainbowGroup] { ThrRainbowGroup.allCases.filter { state(for: $0) == .weak } }

    mutating func mark(_ colorName: String, _ state: ThrColorState) {
        // Don't downgrade an existing hit back to weak.
        if states[colorName] == .hit, state == .weak { return }
        states[colorName] = state
    }
}

// MARK: - Curated education copy (fallback when `colors` rows aren't loaded)

struct ThrColorEducation: Sendable, Equatable {
    let meaning: String        // colors.meaning_copy
    let whatItDoes: String     // colors.what_it_does_copy
}

enum ThrRainbowContent {
    /// Curated, representative fallback mirroring the Phase-0 `colors` seed
    /// (SPEC §5). Truthful + directional; the live `colors` rows override these.
    static let fallback: [String: ThrColorEducation] = [
        "red":         .init(meaning: "Lycopene & anthocyanins", whatItDoes: "Heart and circulation support"),
        "orange":      .init(meaning: "Carotenoids",             whatItDoes: "Eyes, skin, and immune signalling"),
        "yellow":      .init(meaning: "Flavonoids & carotenoids", whatItDoes: "A spread of antioxidants"),
        "green":       .init(meaning: "Chlorophyll & folate",    whatItDoes: "Methylation and detox pathways"),
        "blue_purple": .init(meaning: "Anthocyanins",            whatItDoes: "Feeds the mucus-barrier crews"),
        "white_brown": .init(meaning: "Organosulfur & quercetin", whatItDoes: "Prebiotic fuel and allyl compounds"),
    ]
}

// MARK: - Components

/// A horizontal strip of the six rainbow swatches with state. Optional tap opens
/// education. Reused on the home dashboard, the per-photo view, and the pokédex.
struct ThrRainbowRow: View {
    @Environment(\.theme) private var theme
    let status: ThrRainbowStatus
    var onTap: ((ThrRainbowGroup) -> Void)? = nil

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            ForEach(ThrRainbowGroup.allCases) { group in
                let state = status.state(for: group)
                Button {
                    onTap?(group)
                } label: {
                    swatch(group, state: state)
                }
                .buttonStyle(.plain)
                .disabled(onTap == nil)
                .accessibilityLabel("\(group.label): \(accessibilityState(state))")
                .accessibilityHint(onTap == nil ? "" : "Learn what \(group.label.lowercased()) does")
            }
        }
    }

    private func swatch(_ group: ThrRainbowGroup, state: ThrColorState) -> some View {
        VStack(spacing: theme.metrics.space1) {
            ZStack {
                Circle()
                    .fill(group.swatch.opacity(state == .hit ? 0.9 : 0.18))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle().strokeBorder(
                            group.swatch.opacity(state == .missing ? 0.35 : 0.9),
                            lineWidth: state == .weak ? 2 : 1
                        )
                    )
                // Shape + glyph, never color alone (DESIGN.md §5).
                Image(systemName: glyph(state))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(state == .hit ? theme.colors.surface : group.swatch.opacity(0.8))
            }
            Text(short(group))
                .font(theme.typography.caption(11))
                .foregroundStyle(state == .missing ? theme.colors.textSecondary : theme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private func glyph(_ state: ThrColorState) -> String {
        switch state {
        case .hit: "checkmark"
        case .weak: "plus"
        case .missing: "circle.dotted"
        }
    }

    private func short(_ group: ThrRainbowGroup) -> String {
        switch group {
        case .bluePurple: "Blue"
        case .whiteBrown: "White"
        default: group.label
        }
    }

    private func accessibilityState(_ state: ThrColorState) -> String {
        switch state {
        case .hit: "on your plate this week"
        case .weak: "only a trace so far — add more"
        case .missing: "not yet this week"
        }
    }
}

/// Tap-through education for one rainbow group (curated content, §11a).
struct ThrColorEducationSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let group: ThrRainbowGroup
    let education: ThrColorEducation

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            HStack(spacing: theme.metrics.space3) {
                Circle().fill(group.swatch.opacity(0.85)).frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(group.swatch, lineWidth: 1))
                    .accessibilityHidden(true)
                Text(group.label)
                    .font(theme.typography.display(28))
                    .foregroundStyle(theme.colors.primary)
            }

            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Text("What's in it")
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                Text(education.meaning)
                    .font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Text("What it does for your gut")
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                Text(education.whatItDoes)
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textPrimary)
            }

            Spacer()
            PrimaryButton(title: "Got it", action: { dismiss() })
        }
        .padding(theme.metrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }
}
