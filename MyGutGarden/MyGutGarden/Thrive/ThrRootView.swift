//
//  ThrRootView.swift
//  MyGutGarden — Module C: the Thrive home surface (SPEC §10, §11a).
//
//  The public entry point for the Thrive mode shell. Surfaces the daily goals
//  (fiber in grams — the only anthropometric number shown, §10; plants toward
//  30 this week; the 3 P's; eat-the-rainbow) plus one curated curiosity fact as
//  a variable reward, and routes into the pokédexes and the "Is it working?"
//  dashboard. Medical-allergy flags from the most recent meal surface here too,
//  LOUD (SPEC §9, rule #1).
//
//  No guild content lives here — the Guild Garden is Module D's surface.
//

import SwiftUI

struct ThrRootView: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    /// The just-confirmed meal, if the user arrived here straight from a snap —
    /// drives today's 3 P's / rainbow contribution and the allergy banner.
    var latestMeal: ConfirmedMeal? = nil

    @State private var model = ThrHomeModel()
    @State private var educatingColor: ThrRainbowGroup?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space5) {
                    header
                    if let latestMeal { ThrAllergyBanner(alerts: latestMeal.response.allergyAlerts) }
                    goalsSection
                    threePsSection
                    rainbowSection
                    if let fact = model.curiosity {
                        ThrCuriosityCard(fact: fact.factText, confidenceTag: fact.confidenceTag)
                    }
                    exploreSection
                }
                .padding(theme.metrics.space5)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Garden")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await model.load(appState: appState, latestMeal: latestMeal) }
        .sheet(item: $educatingColor) { group in
            ThrColorEducationSheet(
                group: group,
                education: model.colorEducation[group.rawValue]
                    ?? ThrRainbowContent.fallback[group.rawValue]
                    ?? ThrColorEducation(meaning: "", whatItDoes: "")
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text("Your garden today")
                .font(theme.typography.display())
                .foregroundStyle(theme.colors.textPrimary)
            Text(model.plantsRemaining == 0
                 ? "30 plants this week — your garden's thriving."
                 : "\(model.plantsRemaining) more plant\(model.plantsRemaining == 1 ? "" : "s") to reach this week's 30.")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Goals (fiber + plants toward 30)

    private var goalsSection: some View {
        VStack(spacing: theme.metrics.space4) {
            Card {
                VStack(spacing: theme.metrics.space3) {
                    SectionHeader(title: "Today's fiber")
                    if let goal = model.fiberGoalG {
                        ThrGoalArcCard(
                            fraction: model.fiberFraction,
                            centerValue: "\(Int(model.fiberConsumedTodayG.rounded()))",
                            centerUnit: "of \(goal) g",
                            caption: model.fiberConsumedTodayG <= 0
                                ? "Snap your first meal to start filling it"
                                : "Directional — leaning generous"
                        )
                    } else {
                        Text("Finish setup to see your personal fiber goal.")
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Card {
                VStack(spacing: theme.metrics.space3) {
                    HStack {
                        SectionHeader(title: "Plants this week")
                        ThrStreakChip(count: model.weekly30Streak, unit: "week")
                    }
                    ThrGoalArcCard(
                        fraction: model.plantFraction,
                        centerValue: "\(model.uniquePlantsThisWeek)",
                        centerUnit: "of \(GameConfig.shared.weeklyPlantTarget)",
                        caption: model.plantsRemaining == 0
                            ? "Target hit — every extra still counts"
                            : "\(model.plantsRemaining) to go before Sunday resets",
                        accent: theme.colors.primary
                    )
                    if model.bestWeekCount > 0 {
                        Text("Best week so far: \(model.bestWeekCount) plants")
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - 3 P's

    private var threePsSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "The 3 P's today", trailing: "\(model.todayThreePs.count)/3")
                ThrThreePsRow(threePs: model.todayThreePs)
                Text(threePsNudge)
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private var threePsNudge: String {
        let p = model.todayThreePs
        if p.allThree { return "Prebiotic, probiotic, and polyphenol — all three today. Beautiful." }
        var missing: [String] = []
        if !p.prebiotic { missing.append("a prebiotic fiber") }
        if !p.probiotic { missing.append("a fermented food") }
        if !p.polyphenol { missing.append("a polyphenol") }
        return "Add \(missing.joined(separator: " or ")) to complete today's 3 P's."
    }

    // MARK: - Rainbow

    private var rainbowSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "Eat the rainbow", trailing: "\(model.rainbow.hitCount)/6")
                ThrRainbowRow(status: model.rainbow) { group in
                    educatingColor = group
                }
                if !model.rainbow.missing.isEmpty {
                    Text("Still to find: \(model.rainbow.missing.map(\.label).joined(separator: ", ")). Tap a color to see what it does.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                } else {
                    Text("Full spectrum this week — tap any color to revisit what it does.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.success)
                }
            }
        }
    }

    // MARK: - Explore (pokédexes + dashboard)

    private var exploreSection: some View {
        Card {
            VStack(spacing: theme.metrics.space2) {
                NavigationLink {
                    ThrPokedexView(appState: appState, latestMeal: latestMeal)
                } label: {
                    ThrNavRow(icon: "books.vertical.fill", title: "Field guide",
                              subtitle: "Plants, rainbow, phytochemicals, fermented finds")
                }
                Divider().overlay(theme.colors.divider)
                NavigationLink {
                    ThrIsItWorkingView(appState: appState)
                } label: {
                    ThrNavRow(icon: "heart.text.square.fill", title: "Is it working?",
                              subtitle: "Mood, energy, and clarity since you started")
                }
            }
        }
    }
}

#if DEBUG
#Preview("Thrive home") {
    ThrRootView(appState: AppState(auth: AuthService()),
                latestMeal: try? ThrPreviewData.confirmedMeal())
        .themed(for: .thrive)
}
#endif
