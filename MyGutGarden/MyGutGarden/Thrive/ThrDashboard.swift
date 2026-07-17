//
//  ThrDashboard.swift
//  MyGutGarden, Module C: the Today dashboard's depth (owner revamp, 2026-07-02).
//
//  The dashboard card on Today shows the plants arc + compact progress; this
//  file holds what hangs off it: the tappable "to grow today" callouts (finish
//  the rainbow, add a fermented food, explore phytochemicals — each routes to
//  the relevant surface), the tap-through detail view with the full 3 P's +
//  rainbow rings, and the small 3 P's explainer page. Curated copy only
//  (rule #11); coarse amounts only (rule #3).
//

import SwiftUI

// MARK: - "To grow today" callouts

/// One actionable gap for today. Color gaps open the color's education sheet
/// (example foods included); the rest route to their surfaces.
struct ThrTodayCallout: Identifiable {
    enum Target {
        case color(ThrRainbowGroup)
        case fermented
        case threePs
        case phytos
    }
    let id: String
    let icon: String
    let title: String
    let target: Target
}

enum ThrDashboardGaps {
    /// Up to `limit` prioritized callouts: missing rainbow colors first (they
    /// carry the phytochemicals), then a missing fermented food, then the
    /// SPECIFIC phytochemical gap (once Tier 2 is open). Empty when today is
    /// covered.
    static func callouts(threePs: ThrThreePAmounts,
                         rainbow: ThrRainbowAmounts,
                         exampleFoods: (ThrRainbowGroup) -> [String],
                         phytoGap: ThrHomeModel.PhytoGap? = nil,
                         tier2Unlocked: Bool,
                         limit: Int = 3) -> [ThrTodayCallout] {
        var out: [ThrTodayCallout] = []
        for group in rainbow.missing.prefix(2) {
            let examples = exampleFoods(group).prefix(2).joined(separator: ", ")
            out.append(ThrTodayCallout(
                id: "color-\(group.rawValue)",
                icon: "paintpalette",
                title: examples.isEmpty
                    ? "Finish the rainbow: add \(group.label.lowercased())"
                    : "Add \(group.label.lowercased()) — try \(examples.lowercased())",
                target: .color(group)
            ))
        }
        if !threePs.probioticHit {
            out.append(ThrTodayCallout(
                id: "fermented",
                icon: "drop.fill",
                title: "No fermented food yet — see your finds",
                target: .fermented
            ))
        } else if !threePs.prebioticHit || !threePs.polyphenolHit {
            out.append(ThrTodayCallout(
                id: "threeps",
                icon: "checkmark.seal",
                title: "Complete today's 3 P's",
                target: .threePs
            ))
        }
        if tier2Unlocked {
            // The actual insight, not a generic nudge (owner, round 2).
            if let gap = phytoGap {
                out.append(ThrTodayCallout(
                    id: "phytos",
                    icon: "atom",
                    title: "No \(gap.compoundName.lowercased()) in a while — \(gap.exampleFood.lowercased()) brings it back",
                    target: .phytos
                ))
            } else {
                out.append(ThrTodayCallout(
                    id: "phytos",
                    icon: "atom",
                    title: "Round out your phytochemicals",
                    target: .phytos
                ))
            }
        }
        return Array(out.prefix(limit))
    }
}

/// The callout rows on the dashboard card. Color callouts open the education
/// sheet (owned by the caller); the others push their surface.
struct ThrDashboardCallouts: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    let model: ThrHomeModel
    var latestMeal: ConfirmedMeal? = nil
    var onColorTap: (ThrRainbowGroup) -> Void

    private var callouts: [ThrTodayCallout] {
        ThrDashboardGaps.callouts(threePs: model.todayThreePs,
                                  rainbow: model.rainbowAmounts,
                                  exampleFoods: model.exampleFoods(for:),
                                  phytoGap: model.phytoGap,
                                  tier2Unlocked: appState.progression.isTier2Unlocked)
    }

    var body: some View {
        if callouts.isEmpty {
            Text("Everything covered today — beautifully varied.")
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.success)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: theme.metrics.space1) {
                Text("To grow today")
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                ForEach(callouts) { callout in
                    calloutRow(callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func calloutRow(_ callout: ThrTodayCallout) -> some View {
        switch callout.target {
        case let .color(group):
            Button { onColorTap(group) } label: { label(callout) }
                .buttonStyle(.plain)
        case .fermented:
            NavigationLink { ThrFermentedFindsScreen(appState: appState, latestMeal: latestMeal) }
                label: { label(callout) }
        case .threePs:
            NavigationLink { ThrThreePsDetailView(model: model) }
                label: { label(callout) }
        case .phytos:
            NavigationLink { ThrPhytochemicalPokedexView(appState: appState) }
                label: { label(callout) }
        }
    }

    private func label(_ callout: ThrTodayCallout) -> some View {
        HStack(spacing: theme.metrics.space2) {
            Image(systemName: callout.icon)
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 22)
            Text(callout.title)
                .font(theme.typography.caption(weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(.vertical, theme.metrics.space1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(callout.title)
    }
}

// MARK: - Dashboard detail (the tap-through: full 3 P's + rainbow + context)

struct ThrDashboardDetailView: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    let model: ThrHomeModel
    var latestMeal: ConfirmedMeal? = nil

    @State private var educatingColor: ThrRainbowGroup?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space3) {
                        SectionHeader(title: "The 3 P's today", trailing: "\(model.todayThreePs.count)/3")
                        ThrThreePsRow(amounts: model.todayThreePs)
                        Text(ThrThreePsCopy.nudge(model.todayThreePs))
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space3) {
                        SectionHeader(title: "Eat the rainbow", trailing: "\(model.rainbowAmounts.hitCount)/6")
                        ThrRainbowRings(amounts: model.rainbowAmounts) { group in
                            educatingColor = group
                        }
                        if !model.rainbowAmounts.missing.isEmpty {
                            Text("Still to find: \(model.rainbowAmounts.missing.map(\.label).joined(separator: ", ")). Tap a color to see its week and example foods.")
                                .font(theme.typography.caption())
                                .foregroundStyle(theme.colors.textSecondary)
                        } else {
                            Text("Full spectrum today, the inner ring fills when you eat a lot of a color.")
                                .font(theme.typography.caption())
                                .foregroundStyle(theme.colors.success)
                        }
                    }
                }
                // Your fiber — the goal + the two-week charts live in the
                // dashboard now, above "To grow today" (owner, 2026-07-17).
                // "Learn more" opens the education page.
                VStack(alignment: .leading, spacing: theme.metrics.space3) {
                    NavigationLink {
                        ThrFiberDetailView(appState: appState, homeModel: model)
                    } label: {
                        HStack(spacing: theme.metrics.space1) {
                            SectionHeader(title: "Your fiber")
                            if model.fiberGoalG == nil {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Text("Learn more")
                                .font(theme.typography.caption(weight: .semibold))
                                .foregroundStyle(theme.colors.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    ThrFiberCharts(appState: appState, homeModel: model)
                }
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space3) {
                        SectionHeader(title: "To grow today")
                        ThrDashboardCallouts(appState: appState, model: model, latestMeal: latestMeal) { group in
                            educatingColor = group
                        }
                    }
                }
                if model.bestWeekCount > 0 || model.weekly30Streak > 0 {
                    Card {
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            SectionHeader(title: "Your weeks")
                            if model.weekly30Streak > 0 {
                                ThrStreakChip(count: model.weekly30Streak, unit: "week")
                            }
                            if model.bestWeekCount > 0 {
                                Text("Best week so far: \(model.bestWeekCount) plants")
                                    .font(theme.typography.caption())
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                        }
                    }
                }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Your dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $educatingColor) { group in
            ThrColorDetailSheet(
                group: group,
                todayAmount: model.rainbowAmounts.amount(for: group),
                weekly: model.weeklyAmounts(for: group),
                exampleFoods: model.exampleFoods(for: group),
                education: model.colorEducation[group.rawValue]
                    ?? ThrRainbowContent.fallback[group.rawValue]
                    ?? ThrColorEducation(meaning: "", whatItDoes: "")
            )
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - The 3 P's detail (explainer + today's state)

enum ThrThreePsCopy {
    /// The gain-framed nudge for today's remaining P's (curated, rule #11).
    static func nudge(_ p: ThrThreePAmounts) -> String {
        if p.allThree { return "Prebiotic, probiotic, and polyphenol, all three today. Beautiful." }
        var missing: [String] = []
        if !p.prebioticHit { missing.append("a prebiotic fiber") }
        if !p.probioticHit { missing.append("a fermented food") }
        if !p.polyphenolHit { missing.append("a polyphenol") }
        return "Add \(missing.joined(separator: " or ")) to complete today's 3 P's."
    }
}

struct ThrThreePsDetailView: View {
    @Environment(\.theme) private var theme
    let model: ThrHomeModel
    var appState: AppState? = nil

    // Curated explainer copy (rule #11). Directional, never a measured claim.
    private static let explainers: [(title: String, body: String, icon: String)] = [
        ("Prebiotic", "Fibers your microbes actually eat — beans, oats, onions, and most whole plants. Variety feeds different crews.", "leaf.fill"),
        ("Probiotic", "Fermented foods with live cultures — yogurt, kefir, kimchi, sauerkraut. A little each day is a lovely habit.", "drop.fill"),
        ("Polyphenol", "The deeply colored plant compounds — berries, olive oil, herbs, cocoa. Your microbes turn them into useful things.", "sparkles"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space3) {
                        SectionHeader(title: "Today", trailing: "\(model.todayThreePs.count)/3")
                        ThrThreePsRow(amounts: model.todayThreePs)
                        Text(ThrThreePsCopy.nudge(model.todayThreePs))
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                if let appState {
                    ThrThreePsTrendCard(appState: appState)
                }
                ForEach(Self.explainers, id: \.title) { item in
                    Card {
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            Label(item.title, systemImage: item.icon)
                                .font(theme.typography.body(weight: .semibold))
                                .foregroundStyle(theme.colors.textPrimary)
                            Text(item.body)
                                .font(theme.typography.body())
                                .foregroundStyle(theme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("The 3 P's")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Fermented Finds route (owns its pokédex model so callouts can push it)

struct ThrFermentedFindsScreen: View {
    let appState: AppState
    var latestMeal: ConfirmedMeal? = nil
    @State private var model = ThrPokedexModel()

    var body: some View {
        ThrFermentedFindsView(model: model)
            .task {
                await model.load(appState: appState, latestMeal: latestMeal)
                await appState.coach.startIfNeeded("fermented", appState: appState)
            }
    }
}
