//
//  ThrRainbow.swift
//  MyGutGarden, Module C: the "eat the rainbow" surface (SPEC §8, §10, §11a).
//
//  Shows which color groups the user has hit, which are weak (only a trace),
//  and which are missing; tapping a color opens its curated education (meaning +
//  what it does for the gut), loaded from the `colors` table with a curated
//  fallback (CLAUDE.md rule #9, curated content, never runtime generation).
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

    /// Adaptive system hue for the swatch (see file header, content, not brand).
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
    case weak      // only a trace, nudge for more
    case missing   // not yet this week, an invitation
}

/// This week's rainbow coverage, keyed by `color_name`. Defaults to all missing
/// (an empty screen that invites action, DESIGN.md "Writing").
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

// MARK: - Relative amount per color (Batch D: three-ring "eat the rainbow")
//
// The home surface shows how MUCH of each color the user ate today, not just a
// yes/no. `countsTowardSix` is true for any amount (so X/6 fills generously); a
// ring only FULLY fills at `lots`. Coarse tiers only (rule #3), never grams.

enum ThrColorAmount: Int, Sendable, Comparable, Equatable {
    case none = 0, trace = 1, serving = 2, lots = 3

    static func < (lhs: ThrColorAmount, rhs: ThrColorAmount) -> Bool { lhs.rawValue < rhs.rawValue }

    init(tier: PortionTier?) {
        switch tier {
        case .trace:   self = .trace
        case .serving: self = .serving
        case .lots:    self = .lots
        case nil:      self = .none
        }
    }

    /// Any amount at all counts toward the 6 colors.
    var countsTowardSix: Bool { self >= .trace }
    /// Fully filled (all three rings) only when a lot landed today.
    var isFull: Bool { self == .lots }
    /// Concentric rings filled: outer at trace+, middle at serving+, inner at lots.
    var ringsFilled: Int { rawValue }

    var caption: String {
        switch self {
        case .none:    "not yet today"
        case .trace:   "a trace today"
        case .serving: "a serving today"
        case .lots:    "lots today"
        }
    }
}

extension PortionTier {
    /// Coarse ordering for "keep the highest tier" merges (trace < serving < lots).
    var amountRank: Int { ThrColorAmount(tier: self).rawValue }
}

/// Today's relative rainbow coverage, keyed by `color_name`. `mark` only ever
/// upgrades, never downgrades (a later trace can't erase an earlier serving).
struct ThrRainbowAmounts: Sendable, Equatable {
    var amounts: [String: ThrColorAmount] = [:]

    func amount(for group: ThrRainbowGroup) -> ThrColorAmount { amounts[group.rawValue] ?? .none }

    var hitCount: Int { ThrRainbowGroup.allCases.filter { amount(for: $0).countsTowardSix }.count }
    var missing: [ThrRainbowGroup] { ThrRainbowGroup.allCases.filter { !amount(for: $0).countsTowardSix } }

    mutating func mark(_ colorName: String, _ amount: ThrColorAmount) {
        if let current = amounts[colorName], current >= amount { return }
        amounts[colorName] = amount
    }
    mutating func mark(_ colorName: String, tier: PortionTier) {
        mark(colorName, ThrColorAmount(tier: tier))
    }
}

// MARK: - Curated education copy (fallback when `colors` rows aren't loaded)

struct ThrColorEducation: Sendable, Equatable {
    let meaning: String        // colors.meaning_copy
    let whatItDoes: String     // colors.what_it_does_copy
    var deficiency: String = "" // colors.deficiency_copy (R3 Batch B, RD-REVIEW)
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
        case .weak: "only a trace so far, add more"
        case .missing: "not yet this week"
        }
    }
}

// MARK: - Three-ring rainbow (Batch D home surface)

/// A horizontal strip of six colors, each drawn as three concentric 270° arcs:
/// outer fills at a trace, middle at a serving, inner only at "lots". Any amount
/// counts toward X/6; the ring fully closes only when a lot landed today. Tap a
/// color to open its weekly history + example foods.
struct ThrRainbowRings: View {
    @Environment(\.theme) private var theme
    let amounts: ThrRainbowAmounts
    var onTap: ((ThrRainbowGroup) -> Void)? = nil

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            ForEach(ThrRainbowGroup.allCases) { group in
                let amount = amounts.amount(for: group)
                Button { onTap?(group) } label: {
                    VStack(spacing: theme.metrics.space1) {
                        ThrColorRingMark(group: group, amount: amount)
                            .frame(width: 44, height: 44)
                        Text(short(group))
                            .font(theme.typography.caption(11))
                            .foregroundStyle(amount.countsTowardSix ? theme.colors.textPrimary : theme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(onTap == nil)
                .accessibilityLabel("\(group.label): \(amount.caption)")
                .accessibilityHint(onTap == nil ? "" : "See \(group.label.lowercased()) this week and example foods")
            }
        }
    }

    private func short(_ group: ThrRainbowGroup) -> String {
        switch group {
        case .bluePurple: "Blue"
        case .whiteBrown: "White"
        default: group.label
        }
    }
}

/// One color's three concentric rings + a center glyph (checkmark only when full).
struct ThrColorRingMark: View {
    @Environment(\.theme) private var theme
    let group: ThrRainbowGroup
    let amount: ThrColorAmount

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    // ring 0 = outer (trace+), 1 = middle (serving+), 2 = inner (lots).
                    // Unfilled rings render as a faint OUTLINE in the color's own
                    // hue, so full capacity is always visible and "how much is
                    // filled" reads at a glance (owner, 2026-07-02 round 2).
                    let filled = amount.ringsFilled >= (ring + 1)
                    let inset = CGFloat(ring) * (side * 0.16)
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(group.swatch.opacity(filled ? 0.95 : 0.22),
                                style: .init(lineWidth: max(2, side * 0.08), lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .padding(inset)
                }
                Image(systemName: amount.isFull ? "checkmark" : (amount.countsTowardSix ? "leaf.fill" : "circle.dotted"))
                    .font(.system(size: side * 0.22, weight: .bold))
                    .foregroundStyle(amount.countsTowardSix ? group.swatch : theme.colors.textSecondary.opacity(0.6))
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}

/// A small weekly bar chart of one color's max amount per week (reset weekly),
/// read from `weekly_color_amounts`. Bars are coarse tiers, never a precise count.
struct ThrColorWeeklyChart: View {
    @Environment(\.theme) private var theme
    let group: ThrRainbowGroup
    /// Oldest → newest, one entry per week.
    let weekly: [ThrColorAmount]

    private let maxRings = 3.0

    var body: some View {
        if weekly.allSatisfy({ $0 == .none }) {
            Text("No \(group.label.lowercased()) logged yet. Tap a plant of this color into a meal to start the chart.")
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            GeometryReader { geo in
                let count = max(weekly.count, 1)
                let slot = geo.size.width / CGFloat(count)
                let barWidth = max(6, slot * 0.5)
                ZStack(alignment: .bottomLeading) {
                    ForEach(Array(weekly.enumerated()), id: \.offset) { idx, amount in
                        let h = geo.size.height * CGFloat(Double(amount.ringsFilled) / maxRings)
                        // Full-capacity outline behind every bar so "how much of
                        // the bar is filled" reads at a glance (owner, round 2).
                        RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous)
                            .strokeBorder(group.swatch.opacity(0.3), lineWidth: 1)
                            .frame(width: barWidth, height: geo.size.height)
                            .position(x: slot * (CGFloat(idx) + 0.5), y: geo.size.height / 2)
                        RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous)
                            .fill(amount == .none ? theme.colors.divider : group.swatch.opacity(0.85))
                            .frame(width: barWidth, height: max(3, h))
                            .position(x: slot * (CGFloat(idx) + 0.5), y: geo.size.height - h / 2)
                    }
                }
            }
            .frame(height: 80)
            .accessibilityElement()
            .accessibilityLabel("\(group.label) over the last \(weekly.count) weeks, coarse amounts")
        }
    }
}

/// Tap-in for one rainbow color (Batch D): this week's amount, a weekly history
/// chart, curated example foods, and what the color does. Curated content only.
struct ThrColorDetailSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let group: ThrRainbowGroup
    let todayAmount: ThrColorAmount
    let weekly: [ThrColorAmount]
    let exampleFoods: [String]
    let education: ThrColorEducation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                HStack(spacing: theme.metrics.space3) {
                    ThrColorRingMark(group: group, amount: todayAmount)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.label)
                            .font(theme.typography.display(26))
                            .foregroundStyle(theme.colors.primary)
                        Text(todayAmount.caption.capitalizedFirst)
                            .font(theme.typography.caption(weight: .semibold))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space2) {
                        SectionHeader(title: "This color, week by week")
                        ThrColorWeeklyChart(group: group, weekly: weekly)
                        Text("Each bar is one week's high point. Resets every week, so there's always room to fill it again.")
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !exampleFoods.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            SectionHeader(title: "Try these")
                            FlowRows(items: exampleFoods) { food in
                                Badge(text: food, tint: group.swatch)
                            }
                        }
                    }
                }

                if !education.whatItDoes.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            SectionHeader(title: "What it does for your gut")
                            if !education.meaning.isEmpty {
                                Text(education.meaning)
                                    .font(theme.typography.body(weight: .medium))
                                    .foregroundStyle(theme.colors.textPrimary)
                            }
                            Text(education.whatItDoes)
                                .font(theme.typography.body())
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                }

                if !education.deficiency.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            SectionHeader(title: "If you go short")
                            Text(education.deficiency)
                                .font(theme.typography.body())
                                .foregroundStyle(theme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                PrimaryButton(title: "Got it", action: { dismiss() })
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }
}

private extension String {
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
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
