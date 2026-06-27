//
//  SrvRootView.swift
//  MyGutGarden, Module E PUBLIC ENTRY. The Survive home (SPEC §11b, R3 Batch E).
//
//  Survive is now a time-boxed EPISODE: entering it (after a hard disclaimer) IS
//  starting the low-residue reset, so the reset is the home surface, not a buried
//  card. Today shows: where you are in the arc (phase + relief), this phase's
//  curated suggested meals (Fence 6), the evening check-in, recent meals, the one
//  unified "Foods you're checking" surface, and a persistent clinician disclaimer.
//
//  Register stays calm (DESIGN §1/§3): no celebration, relief-framed progress
//  ("days feeling good", never "days restricted", rule #7), frictionless pause.
//

import SwiftUI

struct SrvRootView: View {
    @State private var store: SrvStore
    @State private var resetModel: SrvResetModel
    @State private var mealPlan = SrvMealPlanModel()
    @State private var foodStore: FoodStatusStore?
    @State private var recentMealRows: [MealRow] = []
    @State private var showLogger = false
    @State private var showOffRamp = false

    init(appState: AppState) {
        let s = SrvStore(appState: appState)
        _store = State(initialValue: s)
        _resetModel = State(initialValue: SrvResetModel(store: s))
    }

    /// Preview/testing seam: inject a pre-populated store directly.
    init(store: SrvStore) {
        _store = State(initialValue: store)
        _resetModel = State(initialValue: SrvResetModel(store: store))
    }

    var body: some View {
        NavigationStack {
            SrvHomeContent(store: store, resetModel: resetModel, mealPlan: mealPlan,
                           foodStore: foodStore, recentMealRows: recentMealRows,
                           showLogger: $showLogger, showOffRamp: $showOffRamp)
                .navigationTitle("My Gut Garden")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showOffRamp = true } label: { Image(systemName: "slider.horizontal.3") }
                            .accessibilityLabel("Adjust or pause tracking")
                    }
                }
        }
        .themed(for: .survive)
        .task {
            await SrvEpisode.ensureStarted(appState: store.appState)
            await store.load()
            await loadRecentMeals()
            await resetModel.load()
            if let repo = store.appState.repository, let reset = resetModel.reset {
                await mealPlan.load(repo: repo, phase: reset.phase,
                                    startedAt: SrvDateParse.timestamp(reset.startedAt))
            }
            if foodStore == nil,
               let repo = store.appState.repository,
               let uid = store.appState.profile?.id {
                let fs = FoodStatusStore(repository: repo, userId: uid, appState: store.appState)
                await fs.load()
                foodStore = fs
            }
        }
        .sheet(isPresented: $showLogger) {
            // The SAME check-in form as Thrive (R4), Survive context: no light option,
            // and on save we refresh the store + run the reset break-detector.
            ThrCheckInFormView(appState: store.appState, mode: .new, context: .surviveLogger,
                               onSaved: {
                                   await store.load()
                                   await SrvResetBreakDetector.run(appState: store.appState)
                               }) { showLogger = false }
                .themed(for: .survive)
        }
        .sheet(isPresented: $showOffRamp) {
            SrvOffRampView(store: store, resetModel: resetModel)
                .themed(for: .survive)
        }
    }

    /// Last 5 days of confirmed Survive meals as MealRows, for the shared
    /// recent-meals rail (same component as Thrive).
    private func loadRecentMeals() async {
        guard let repo = store.appState.repository else { return }
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -5, to: cal.startOfDay(for: Date())) ?? Date()
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        let rows: [MealRow]? = try? await repo.select(
            "meals", columns: "id,mode,photo_url,captured_at,confirmed,user_annotation,photo_expires_at",
            filters: ["captured_at": "gte.\(iso.string(from: since))", "mode": "eq.survive", "confirmed": "eq.true"],
            order: "captured_at.desc", limit: 20)
        recentMealRows = rows ?? []
    }
}

private struct SrvHomeContent: View {
    @Environment(\.theme) private var theme
    @Bindable var store: SrvStore
    @Bindable var resetModel: SrvResetModel
    @Bindable var mealPlan: SrvMealPlanModel
    let foodStore: FoodStatusStore?
    let recentMealRows: [MealRow]
    @Binding var showLogger: Bool
    @Binding var showOffRamp: Bool

    private var loggedDays: Int { store.mergedDailySymptoms().count }
    private var phase: SrvResetPhase { SrvResetPhase(rawValue: resetModel.reset?.phase ?? "reset") ?? .reset }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                greeting
                resetCard
                suggestedMeals
                logCta
                recentMeals
                resetActions
                clinicianCheckpoint
                checkingNav
                patternSection
                clinicianDisclaimer
                SrvRedFlagCard()
                if store.usingSampleData { sampleNote }
            }
            .padding(theme.metrics.space4)
        }
        .background(theme.colors.background.ignoresSafeArea())
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space1) {
            Text("How are you feeling?")
                .font(theme.typography.display(28))
                .foregroundStyle(theme.colors.textPrimary)
            Text("A gentle reset. Symptoms in, insights out, we'll keep it calm.")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Reset status (phase + relief, frictionless pause)

    private var resetCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                HStack {
                    Text(phase.title)
                        .font(theme.typography.title(18))
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    if let day = dayNumber {
                        Text("Day \(day)")
                            .font(theme.typography.caption(weight: .semibold))
                            .foregroundStyle(theme.colors.secondary)
                    }
                }
                Text(phaseBlurb)                                  // RD-REVIEW-REQUIRED (Fence 6)
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if resetModel.reliefDaysThisWeek > 0 {
                    Text(reliefHeadline)
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.primary)
                }
                Text("A gentle low-residue program. Stick with it as best you can, and pause or head back to Thrive anytime, no pressure.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if resetModel.reset?.pausedAt != nil {
                    Text("Paused. Resume it from the top-right menu whenever you're ready.")
                        .font(theme.typography.caption(weight: .medium))
                        .foregroundStyle(theme.colors.secondary)
                }
            }
        }
    }

    /// Which day of the program you're on (a structured, program-style cue now that
    /// Survive is an intentional low-residue reset, R5 #1). Exit/pause stay the
    /// duty-of-care valves; we still never reward or streak the restriction itself.
    private var dayNumber: Int? {
        guard let started = resetModel.reset.flatMap({ SrvDateParse.timestamp($0.startedAt) }) else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: started), to: cal.startOfDay(for: Date())).day ?? 0
        return max(1, days + 1)
    }

    /// RD-REVIEW-REQUIRED (Fence 6): phase guidance copy.
    private var phaseBlurb: String {
        switch phase {
        case .reset: return "Keep meals very gentle and low-residue while things settle."
        case .reintroductionPhase: return "Adding gentle fiber back, one small step at a time."
        case .graduated: return "You're ready for Thrive whenever you are."
        }
    }

    private var reliefHeadline: String {
        let n = resetModel.reliefDaysThisWeek
        return n == 0 ? "Settling in" : "You've had \(n) \(n == 1 ? "day" : "days") feeling better this week"
    }

    // MARK: Suggested meals (curated, fenced)

    @ViewBuilder private var suggestedMeals: some View {
        if !mealPlan.todaySlots.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space3) {
                    HStack {
                        SectionHeader(title: "Suggested meals today")
                        Spacer()
                        Button { withAnimation(.snappy) { mealPlan.refresh() } } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.colors.primary)
                        }
                        .accessibilityLabel("Show different meal ideas")
                    }
                    ForEach(mealPlan.todaySlots) { slot in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(slot.title)
                                .font(theme.typography.caption(weight: .semibold))
                                .foregroundStyle(theme.colors.secondary)
                            Text(slot.meal.title)
                                .font(theme.typography.body(weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                            Text(slot.meal.description)
                                .font(theme.typography.caption())
                                .foregroundStyle(theme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    NavigationLink {
                        SrvWeeklyPlanView(model: mealPlan)
                    } label: {
                        HStack(spacing: theme.metrics.space1) {
                            Image(systemName: "calendar")
                            Text("See the week + grocery list")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(theme.typography.caption(weight: .semibold))
                        .foregroundStyle(theme.colors.primary)
                    }
                    Text("Ideas your dietitian can tune.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
    }

    // MARK: Log CTA

    private var logCta: some View {
        PrimaryButton(title: "Log tonight's check-in", systemImage: "moon.stars") {
            showLogger = true
        }
    }

    // MARK: Recent meals (like Thrive)

    // The SAME recent-meals rail as Thrive (R4): identical photo cards + reopen/edit.
    @ViewBuilder private var recentMeals: some View {
        if !recentMealRows.isEmpty {
            ThrRecentMealsSection(appState: store.appState, meals: recentMealRows)
        }
    }

    // MARK: Reset actions (relief-gated)

    @ViewBuilder private var resetActions: some View {
        if let reset = resetModel.reset, reset.pausedAt == nil {
            if phase == .reset, SrvResetEngine.canAdvance(from: .reset, symptomFreeDays: resetModel.reliefDaysThisWeek) {
                PrimaryButton(title: "I'm feeling better, add foods back", systemImage: "arrow.up.forward") {
                    Task { await resetModel.advanceToReintroduction(); await reloadPlan() }
                }
            }
            if SrvResetEngine.graduationReady(state: reset) {
                PrimaryButton(title: "Move to Thrive", systemImage: "sun.max") {
                    Task { await resetModel.graduate() }
                }
            }
        }
    }

    private func reloadPlan() async {
        guard let repo = store.appState.repository, let reset = resetModel.reset else { return }
        await mealPlan.load(repo: repo, phase: reset.phase, startedAt: SrvDateParse.timestamp(reset.startedAt))
    }

    @ViewBuilder private var clinicianCheckpoint: some View {
        if let reset = resetModel.reset, reset.pausedAt == nil,
           SrvResetEngine.clinicianPromptNeeded(state: reset, now: Date()) {
            Card {
                HStack(alignment: .top, spacing: theme.metrics.space3) {
                    Image(systemName: "stethoscope").foregroundStyle(theme.colors.warning)
                    VStack(alignment: .leading, spacing: theme.metrics.space2) {
                        Text("It's been a couple of weeks and things haven't settled. A good moment to check in with a doctor or dietitian.")
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textPrimary)
                        Button("Got it") { Task { await resetModel.markClinicianPrompted() } }
                            .font(theme.typography.caption(weight: .semibold))
                            .foregroundStyle(theme.colors.primary)
                    }
                }
            }
        }
    }

    // MARK: One unified food surface

    @ViewBuilder private var checkingNav: some View {
        if let foodStore {
            NavigationLink {
                SrvFoodSurfaceView(foodStore: foodStore)
            } label: {
                SrvNavRow(title: "Foods you're checking", subtitle: checkingSubtitle,
                          systemImage: "list.bullet.clipboard")
            }
            .buttonStyle(.plain)
        }
    }

    private var checkingSubtitle: String {
        guard let foodStore else { return "Keep an eye on foods, ease them back in" }
        let checking = foodStore.checking().count
        let paused = foodStore.avoided().count
        if checking == 0 && paused == 0 { return "Keep an eye on foods, ease them back in" }
        return "\(checking) checking \u{00B7} \(paused) on pause"
    }

    // MARK: Pattern

    @ViewBuilder private var patternSection: some View {
        if let card = store.patternCards.first {
            SrvPatternCard(presentation: card)
        } else {
            SrvGatheringSignalCard(loggedDays: loggedDays)
        }
    }

    // MARK: Persistent clinician disclaimer (Fence 6 machinery)

    private var clinicianDisclaimer: some View {
        Card {
            HStack(alignment: .top, spacing: theme.metrics.space3) {
                Image(systemName: "cross.case.fill").foregroundStyle(theme.colors.error)
                Text("This is a personal experiment, not medical advice. If you have any health condition, especially IBD, an autoimmune condition, diabetes, or a history of disordered eating, or if you're pregnant, talk to your doctor first. This isn't right for everyone.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sampleNote: some View {
        Text("Showing sample data, connect an account to track your own.")
            .font(theme.typography.caption())
            .foregroundStyle(theme.colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// A tappable navigation row styled as a calm card.
struct SrvNavRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Card {
            HStack(spacing: theme.metrics.space3) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(theme.colors.primary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(subtitle)
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

// MARK: - Preview

#Preview("Survive home") {
    SrvRootView(store: SrvStore(appState: AppState(auth: AuthService())))
}
