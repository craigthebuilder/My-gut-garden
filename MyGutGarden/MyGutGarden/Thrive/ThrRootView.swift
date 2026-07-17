//
//  ThrRootView.swift
//  MyGutGarden, Module C: the Today surface (SPEC §10, §11a).
//
//  Page order (owner revamp, 2026-07-02):
//    header → allergy banner (LOUD, §9) → YOUR DASHBOARD (plants arc + compact
//    3 P's / rainbow progress + tappable "to grow today" callouts, tap-through
//    to the full detail) → TRY THIS (curated recipe with refresh + optimize
//    icon controls) → DID YOU KNOW → recent meals → explore (check-in, field
//    guide + garden tab routes, rainbow, 3 P's, trends).
//
//  The fiber line renders ONLY once the week-one quest unlocks the goal
//  (SPEC §10 / Fence 5). No guild content lives here (Module D's surface).
//

import SwiftUI

struct ThrRootView: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    /// The just-confirmed meal, if the user arrived here straight from a snap,
    /// drives today's 3 P's / rainbow contribution and the allergy banner.
    var latestMeal: ConfirmedMeal? = nil
    /// Supplied by the shell so Field guide / Garden rows jump straight to
    /// their tabs instead of pushing a copy in this stack.
    var onSwitchTab: ((AppTab) -> Void)? = nil

    @State private var model = ThrHomeModel()
    @State private var educatingColor: ThrRainbowGroup?
    @State private var showDailyCheckin = false
    @State private var showingRecipe: RecipeRow?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.metrics.space5) {
                        header
                            .coachTarget("home")
                            .id("home")
                        if let latestMeal { ThrAllergyBanner(alerts: latestMeal.response.allergyAlerts) }
                        dashboardSection
                            .coachTarget("dashboard")
                            .id("dashboard")
                        fiberSection            // charts inline under the dashboard (owner, 2026-07-17)
                            .coachTarget("fiber")
                            .id("fiber")
                        dailyCheckInButton      // right under the dashboard (owner, 2026-07-10)
                        recipeSection
                            .coachTarget("trythis")
                            .id("trythis")
                        if let fact = model.curiosity {
                            ThrCuriosityCard(fact: fact.factText)
                        }
                        recentMealsSection
                        exploreSection
                    }
                    .padding(theme.metrics.space5)
                }
                // The tour auto-scrolls its spotlight into view — replaying it
                // from the bottom of the page must not strand the highlights
                // off-screen (owner, round 2).
                .onChange(of: appState.coach.current?.targetHint) { _, hint in
                    scrollToCoachTarget(hint, proxy: proxy)
                }
                .onAppear { scrollToCoachTarget(appState.coach.current?.targetHint, proxy: proxy) }
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Garden")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await model.load(appState: appState, latestMeal: latestMeal) }
        // The fiber goal can unlock in the background (launch recompute) AFTER
        // Today's model snapshotted the locked state — reload when it flips so
        // the section shows the goal, not a stale "coming" (owner audit,
        // 2026-07-17). Cheap: the state transitions once, ever.
        .onChange(of: appState.profile?.fiberGoalState) { _, _ in
            Task { await model.load(appState: appState, latestMeal: latestMeal) }
        }
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

    // MARK: - Header (greeting; the fiber line appears only once unlocked, §10 —
    // pre-unlock a LOCKED line shows what's coming, and the intro tour points at it)

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Your fiber (the charts, inline under the dashboard — owner 2026-07-17)

    /// The fiber section: a titled row (tap → "Your fiber" education page) plus
    /// the charts inline. Pre-unlock it still shows the "goal is coming" card and
    /// the two-week composition so the surface isn't empty (SPEC §17). Hidden
    /// only until Today's model has loaded, to avoid a flash of empty cards.
    @ViewBuilder private var fiberSection: some View {
        if model.isLoaded {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func scrollToCoachTarget(_ hint: String?, proxy: ScrollViewProxy) {
        let scrollable: Set<String> = ["home", "fiber", "dashboard", "threeps", "trythis", "checkin"]
        guard let hint, scrollable.contains(hint) else { return }
        let target = (hint == "threeps") ? "dashboard" : hint
        let anchor: UnitPoint = switch target {
        case "home", "fiber": .top
        case "checkin": .bottom
        default: .center
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(target, anchor: anchor)
        }
    }

    // MARK: - Your dashboard (the hero: plants arc + compact progress + callouts)

    private var dashboardSection: some View {
        Card {
            VStack(spacing: theme.metrics.space3) {
                NavigationLink {
                    ThrDashboardDetailView(appState: appState, model: model, latestMeal: latestMeal)
                } label: {
                    HStack(spacing: theme.metrics.space1) {
                        SectionHeader(title: "Your dashboard")
                        ThrStreakChip(count: model.weekly30Streak, unit: "week")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                ThrGoalArcCard(
                    fraction: model.plantFraction,
                    centerValue: "\(model.uniquePlantsThisWeek)",
                    centerUnit: "of \(GameConfig.shared.weeklyPlantTarget)",
                    caption: model.plantsRemaining == 0
                        ? "Every extra still counts"
                        : "\(model.plantsRemaining) to go",
                    accent: theme.colors.primary
                )
                // Compact 3 P's + rainbow progress; each pill taps through to a
                // 14-day trend chart (owner, round 2). The intro tour spotlights
                // this row when it introduces the 3 P's.
                HStack(spacing: theme.metrics.space2) {
                    NavigationLink {
                        ThrThreePsDetailView(model: model, appState: appState)
                    } label: {
                        StatPill(value: "\(model.todayThreePs.count)/3", label: "3 P's today")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        ThrRainbowTrendView(appState: appState, latestMeal: latestMeal)
                    } label: {
                        StatPill(value: "\(model.rainbowAmounts.hitCount)/6", label: "Rainbow today")
                    }
                    .buttonStyle(.plain)
                }
                .coachTarget("threeps")
                ThrDashboardCallouts(appState: appState, model: model, latestMeal: latestMeal) { group in
                    educatingColor = group
                }
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
            ThrRecentMealsSection(appState: appState, meals: model.recentMeals,
                                  questions: model.keyQuestions,
                                  onQuestionAnswered: model.markQuestionAnswered)
        }
    }

    // MARK: - Try this (curated; refresh = new random, optimize = gap-matched)

    @ViewBuilder private var recipeSection: some View {
        if let recipe = model.recipeSuggestion {
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space2) {
                    HStack(spacing: theme.metrics.space3) {
                        SectionHeader(title: "Try this")
                        ThrRecipeControl(systemImage: "arrow.clockwise",
                                         label: "New random recipe") {
                            model.shuffleRecipe()
                        }
                        ThrRecipeControl(systemImage: "scope",
                                         label: "Recipe matched to today's gaps") {
                            model.optimizeRecipe()
                        }
                    }
                    Text(recipe.title)
                        .font(theme.typography.title(18))
                        .foregroundStyle(theme.colors.textPrimary)
                    if let d = recipe.description {
                        Text(d).font(theme.typography.body())
                            .foregroundStyle(theme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if recipe.suggestProtein == true {
                        Label("Add your protein of choice.", systemImage: "plus.circle")
                            .font(theme.typography.caption(weight: .medium))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    if let f = recipe.fiberHighlights, !f.isEmpty {
                        Text(f).font(theme.typography.caption()).foregroundStyle(theme.colors.secondary)
                    }
                    SecondaryButton(title: "See how", systemImage: "list.bullet") { showingRecipe = recipe }
                }
            }
        }
    }

    // MARK: - Explore (check-in + tab routes + the deeper surfaces)

    /// The prominent daily-check-in entry, now directly under the dashboard.
    private var dailyCheckInButton: some View {
        PrimaryButton(title: "Log your daily check-in", systemImage: "square.and.pencil") {
            showDailyCheckin = true
        }
        .coachTarget("checkin")
        .id("checkin")
    }

    private var exploreSection: some View {
        VStack(spacing: theme.metrics.space4) {
            Card {
                VStack(spacing: theme.metrics.space2) {
                    // Tab routes: these go straight to the tab, never a pushed copy.
                    Button {
                        onSwitchTab?(.fieldGuide)
                    } label: {
                        ThrNavRow(icon: "books.vertical.fill", title: "Field guide",
                                  subtitle: "Plants, rainbow, phytochemicals, fermented finds")
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(theme.colors.divider)
                    if appState.progression.isTier2Unlocked {
                        Button {
                            onSwitchTab?(.garden)
                        } label: {
                            ThrNavRow(icon: "map", title: "Garden",
                                      subtitle: "The microbiome worlds you're growing")
                        }
                        .buttonStyle(.plain)
                    } else {
                        ThrNavRow(icon: "map", title: "Garden",
                                  subtitle: "Unlocks after your first full week", locked: true)
                    }
                    Divider().overlay(theme.colors.divider)
                    NavigationLink {
                        ThrRainbowPokedexView(appState: appState, latestMeal: latestMeal)
                    } label: {
                        ThrNavRow(icon: "circle.hexagongrid.fill", title: "Eat the rainbow",
                                  subtitle: "Six color groups, what each does")
                    }
                    Divider().overlay(theme.colors.divider)
                    NavigationLink {
                        ThrThreePsDetailView(model: model, appState: appState)
                    } label: {
                        ThrNavRow(icon: "checkmark.seal", title: "The 3 P's",
                                  subtitle: "Prebiotic, probiotic, polyphenol — today's trio")
                    }
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

/// A compact icon-only control for the Try-this header (explained in the intro
/// tour; icons carry full VoiceOver labels).
struct ThrRecipeControl: View {
    @Environment(\.theme) private var theme
    let systemImage: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.primary)
                .padding(theme.metrics.space2)
                .background(theme.colors.primary.opacity(0.1))
                .clipShape(Circle())
        }
        .accessibilityLabel(label)
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
                if recipe.suggestProtein == true {
                    Label("Add your protein of choice.", systemImage: "plus.circle")
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                }
                if let f = recipe.fiberHighlights, !f.isEmpty {
                    Text(f).font(theme.typography.body())
                        .foregroundStyle(theme.colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let ingredients = recipe.ingredients, !ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: theme.metrics.space2) {
                        Text("You'll need")
                            .font(theme.typography.title(18))
                            .foregroundStyle(theme.colors.textPrimary)
                        ForEach(Array(ingredients.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: theme.metrics.space2) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(theme.colors.secondary)
                                    .padding(.top, 7)
                                Text(item)
                                    .font(theme.typography.body())
                                    .foregroundStyle(theme.colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text("Steps")
                        .font(theme.typography.title(18))
                        .foregroundStyle(theme.colors.textPrimary)
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
