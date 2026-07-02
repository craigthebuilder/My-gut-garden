//
//  ThrRootView.swift
//  MyGutGarden, Module C: the Thrive home surface (SPEC §10, §11a).
//
//  The public entry point for the Thrive mode shell. Surfaces today's garden:
//  plants toward 30 this week (the hero), a compact fiber mini-bar (the only
//  anthropometric number shown, §10 / rule #6), the relative-fill 3 P's, the
//  three-ring "eat the rainbow", a Recent-Meals rail, one curated curiosity fact,
//  and routes into the field guide, the daily check-in, and trends. Allergy-tier
//  food flags from the most recent meal surface here too, LOUD (§9, rule #1).
//
//  No guild content lives here, the Guild Garden is Module D's surface.
//

import SwiftUI

struct ThrRootView: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    /// The just-confirmed meal, if the user arrived here straight from a snap,
    /// drives today's 3 P's / rainbow contribution and the allergy banner.
    var latestMeal: ConfirmedMeal? = nil

    @State private var model = ThrHomeModel()
    @State private var educatingColor: ThrRainbowGroup?
    @State private var showDailyCheckin = false
    @State private var showingRecipe: RecipeRow?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space5) {
                    header
                    if let latestMeal { ThrAllergyBanner(alerts: latestMeal.response.allergyAlerts) }
                    plantsSection
                    recentMealsSection
                    threePsSection
                    rainbowSection
                    if let fact = model.curiosity {
                        ThrCuriosityCard(fact: fact.factText, confidenceTag: fact.confidenceTag)
                    }
                    recipeSection
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
        .sheet(isPresented: $showDailyCheckin) {
            // ONE check-in: the same multi-entry form the Check-in tab uses (Batch C).
            ThrCheckInFormView(appState: appState, mode: .new) { showDailyCheckin = false }
        }
        .sheet(item: $showingRecipe) { recipe in
            ThrRecipeSheet(recipe: recipe).presentationDetents([.medium, .large])
        }
        // Refresh from the DB whenever Today reappears (e.g. after a snap in another
        // tab), so plants-this-week and field-guide counts aren't stuck on cold-load
        // state (R3 Batch A).
        .onAppear { Task { await model.load(appState: appState, latestMeal: latestMeal) } }
    }

    // MARK: - Header (full-width greeting, then the fiber readout on one line below)

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text("Your garden today")
                .font(theme.typography.display())
                .foregroundStyle(theme.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(model.plantsRemaining == 0
                 ? "30 plants this week, your garden's thriving."
                 : "\(model.plantsRemaining) more plant\(model.plantsRemaining == 1 ? "" : "s") to reach this week's 30.")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            ThrFiberLine(consumedG: model.fiberConsumedTodayG,
                         goalG: model.fiberGoalG,
                         fraction: model.fiberFraction)
                .padding(.top, theme.metrics.space1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Plants toward 30 (the hero arc)

    private var plantsSection: some View {
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
                        ? "Every extra still counts"
                        : "\(model.plantsRemaining) to go",
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

    // MARK: - Recent meals (last 5 days; tap to reopen stats + confirm/deny)

    @ViewBuilder private var recentMealsSection: some View {
        if !model.recentMeals.isEmpty {
            ThrRecentMealsSection(appState: appState, meals: model.recentMeals)
        }
    }

    // MARK: - 3 P's (relative fill)

    private var threePsSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "The 3 P's today", trailing: "\(model.todayThreePs.count)/3")
                ThrThreePsRow(amounts: model.todayThreePs)
                Text(threePsNudge)
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private var threePsNudge: String {
        let p = model.todayThreePs.hits
        if model.todayThreePs.allThree { return "Prebiotic, probiotic, and polyphenol, all three today. Beautiful." }
        var missing: [String] = []
        if !p.prebiotic { missing.append("a prebiotic fiber") }
        if !p.probiotic { missing.append("a fermented food") }
        if !p.polyphenol { missing.append("a polyphenol") }
        return "Add \(missing.joined(separator: " or ")) to complete today's 3 P's."
    }

    // MARK: - Rainbow (three rings, any amount counts toward X/6)

    private var rainbowSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                // The title routes into the Field Guide's Rainbow (same data, deeper),
                // so "Eat the rainbow" and the field guide never disagree (R3 Batch B).
                NavigationLink {
                    ThrRainbowPokedexView(appState: appState, latestMeal: latestMeal)
                } label: {
                    HStack(spacing: theme.metrics.space1) {
                        SectionHeader(title: "Eat the rainbow", trailing: "\(model.rainbowAmounts.hitCount)/6")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                ThrRainbowRings(amounts: model.rainbowAmounts) { group in
                    educatingColor = group
                }
                if !model.rainbowAmounts.missing.isEmpty {
                    Text("Still to find: \(model.rainbowAmounts.missing.map(\.label).joined(separator: ", ")). Tap a color to see its week and example foods.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                } else {
                    Text("Full spectrum today, the inner ring fills when you eat a lot of a color. Tap any to revisit it.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.success)
                }
            }
        }
    }

    // MARK: - Try this (a curated recipe, gap-driven from the rainbow)

    @ViewBuilder private var recipeSection: some View {
        if let recipe = model.recipeSuggestion {
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space2) {
                    SectionHeader(title: "Try this")
                    Text(recipe.title)
                        .font(theme.typography.title(18))
                        .foregroundStyle(theme.colors.textPrimary)
                    if let d = recipe.description {
                        Text(d).font(theme.typography.body())
                            .foregroundStyle(theme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let f = recipe.fiberHighlights, !f.isEmpty {
                        HStack(spacing: theme.metrics.space1) {
                            Text(f).font(theme.typography.caption()).foregroundStyle(theme.colors.secondary)
                            if recipe.claimRisk {
                                Text("[emerging science]")
                                    .font(theme.typography.caption(weight: .semibold))
                                    .foregroundStyle(theme.colors.secondary)
                            }
                        }
                    }
                    SecondaryButton(title: "See how", systemImage: "list.bullet") { showingRecipe = recipe }
                }
            }
        }
    }

    // MARK: - Explore (check-in + field guide + trends)

    private var exploreSection: some View {
        VStack(spacing: theme.metrics.space4) {
            PrimaryButton(title: "Log your daily check-in", systemImage: "square.and.pencil") {
                showDailyCheckin = true
            }
            Card {
                VStack(spacing: theme.metrics.space2) {
                    NavigationLink {
                        ThrPokedexView(appState: appState, latestMeal: latestMeal)
                    } label: {
                        ThrNavRow(icon: "books.vertical.fill", title: "Field guide",
                                  subtitle: "Plants, rainbow, phytochemicals, fermented finds")
                    }
                    // TODO(Phase 1E): Your foods (food_flags) moves here.
                    Divider().overlay(theme.colors.divider)
                    NavigationLink {
                        ThrIsItWorkingView(appState: appState)
                    } label: {
                        ThrNavRow(icon: "chart.line.uptrend.xyaxis", title: "Your trends",
                                  subtitle: "Mood, energy, and clarity since you started")
                    }
                }
            }
        }
    }
}

// MARK: - Recipe detail

struct ThrRecipeSheet: View {
    @Environment(\.theme) private var theme
    let recipe: RecipeRow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                Text(recipe.title)
                    .font(theme.typography.display(28))
                    .foregroundStyle(theme.colors.primary)
                if let m = recipe.prepMinutes {
                    Text("\(m) min")
                        .font(theme.typography.caption(weight: .semibold))
                        .foregroundStyle(theme.colors.textSecondary)
                }
                if let d = recipe.description {
                    Text(d).font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let f = recipe.fiberHighlights, !f.isEmpty {
                    Text(f).font(theme.typography.body())
                        .foregroundStyle(theme.colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if recipe.claimRisk {
                        Text("[emerging science]")
                            .font(theme.typography.caption(weight: .semibold))
                            .foregroundStyle(theme.colors.secondary)
                    }
                }
                if !recipe.steps.isEmpty {
                    VStack(alignment: .leading, spacing: theme.metrics.space2) {
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: theme.metrics.space2) {
                                Text("\(i + 1).")
                                    .font(theme.typography.body(weight: .semibold))
                                    .foregroundStyle(theme.colors.primary)
                                Text(step)
                                    .font(theme.typography.body())
                                    .foregroundStyle(theme.colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(theme.metrics.space5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.colors.background.ignoresSafeArea())
    }
}

#if DEBUG
#Preview("Thrive home") {
    ThrRootView(appState: AppState(auth: AuthService()),
                latestMeal: try? ThrPreviewData.confirmedMeal())
        .themed()
}
#endif
