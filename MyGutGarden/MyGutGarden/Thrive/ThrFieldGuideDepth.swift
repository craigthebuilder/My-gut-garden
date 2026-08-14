//
//  ThrFieldGuideDepth.swift
//  MyGutGarden, Module C (R3 Batch B): the deepened Rainbow + Phytochemical field
//  guide.
//
//  • Rainbow: the SAME today amounts as the home surface (so the two never
//    disagree), per-color deficiency copy, and a gap insight ("missing red this
//    week, try pomegranate") you can refresh for a different food.
//  • Phytochemicals: a category -> compound -> detail hierarchy (phytosterols ->
//    beta-sitosterol -> what it does), class-level deficiency, and a gap insight
//    ("no lycopene logged in a while, try tomato") you can refresh.
//
//  All education copy is curated/seed (rule #9) and RD-review-fenced (Fence 8).
//  Gap suggestions are drawn from the curated junctions (food_colors,
//  food_phytochemicals), never generated at runtime.
//

import SwiftUI
import Observation

private let mealColumns = "id,photo_url,captured_at,confirmed,user_annotation"

// MARK: - Rainbow detail model

struct ThrColorGap: Identifiable, Sendable {
    let id = UUID()
    let group: ThrRainbowGroup
    let food: String
    let missing: Bool
}

@MainActor
@Observable
final class ThrRainbowDetailModel {
    var amounts = ThrRainbowAmounts()
    var weekly: [WeeklyColorAmountRow] = []
    var education: [String: ThrColorEducation] = ThrRainbowContent.fallback
    var exampleFoods: [String: [String]] = [:]
    var isLoaded = false

    private var gapCandidates: [ThrColorGap] = []
    private var gapCursor = 0

    var gapSuggestion: ThrColorGap? {
        guard !gapCandidates.isEmpty else { return nil }
        return gapCandidates[gapCursor % gapCandidates.count]
    }
    func refreshGap() { if !gapCandidates.isEmpty { gapCursor += 1 } }

    func amount(for g: ThrRainbowGroup) -> ThrColorAmount { amounts.amount(for: g) }
    var hitCount: Int { amounts.hitCount }

    func weeklyAmounts(for group: ThrRainbowGroup, weeks: Int = 8) -> [ThrColorAmount] {
        let filtered = weekly.filter { $0.colorId == group.rawValue }
        let sorted = filtered.sorted { $0.weekStart < $1.weekStart }
        let recent = Array(sorted.suffix(weeks))
        return recent.map { ThrColorAmount(tier: PortionTier(rawValue: $0.maxTier)) }
    }
    func examples(for group: ThrRainbowGroup) -> [String] { exampleFoods[group.rawValue] ?? [] }

    func load(appState: AppState, latestMeal: ConfirmedMeal?) async {
        if let meal = latestMeal {
            for item in meal.response.items {
                guard let attrs = item.attributes else { continue }
                for color in attrs.colors { amounts.mark(color, ThrColorAmount(tier: item.vision.portionTier)) }
            }
        }
        guard let repo = appState.repository else { isLoaded = true; return }
        await loadColors(repo)
        await loadTodayAmounts(repo)
        await loadWeekly(repo, userId: appState.profile?.id)
        computeGapCandidates()
        isLoaded = true
    }

    private func loadColors(_ repo: Repository) async {
        guard let rows: [ThrColorRow] = try? await repo.select("colors") else { return }
        for row in rows {
            education[row.id] = ThrColorEducation(
                meaning: row.meaningCopy ?? education[row.id]?.meaning ?? "",
                whatItDoes: row.whatItDoesCopy ?? education[row.id]?.whatItDoes ?? "",
                deficiency: row.deficiencyCopy ?? education[row.id]?.deficiency ?? "")
            if let examples = row.exampleFoods, !examples.isEmpty { exampleFoods[row.id] = examples }
        }
    }

    private func loadTodayAmounts(_ repo: Repository) async {
        let since = ThrDates.timestampString(ThrDates.startOfToday())
        guard let meals: [MealRow] = try? await repo.select(
            "meals", columns: mealColumns,
            filters: ["captured_at": "gte.\(since)", "confirmed": "eq.true"]
        ), !meals.isEmpty else { return }
        let mealList = "(" + meals.map(\.id).joined(separator: ",") + ")"
        guard let items: [ThrMealItemTierRow] = try? await repo.select(
            "meal_items", columns: "food_id,portion_tier,est_fiber_g", filters: ["meal_id": "in.\(mealList)"]
        ), !items.isEmpty else { return }
        var tierByFood: [String: PortionTier] = [:]
        for it in items {
            guard let t = PortionTier(rawValue: it.portionTier) else { continue }
            if let e = tierByFood[it.foodId], e.amountRank >= t.amountRank { continue }
            tierByFood[it.foodId] = t
        }
        let foodList = "(" + tierByFood.keys.joined(separator: ",") + ")"
        guard let colors: [ThrFoodColorRow] = try? await repo.select(
            "food_colors", columns: "food_id,color_id", filters: ["food_id": "in.\(foodList)"]
        ) else { return }
        for fc in colors { if let t = tierByFood[fc.foodId] { amounts.mark(fc.colorId, tier: t) } }
    }

    private func loadWeekly(_ repo: Repository, userId: String?) async {
        guard let userId else { return }
        if let rows: [WeeklyColorAmountRow] = try? await repo.select(
            "weekly_color_amounts", filters: ["user_id": "eq.\(userId)"], order: "week_start.desc", limit: 60
        ) { weekly = rows }
    }

    private func computeGapCandidates() {
        var cands: [ThrColorGap] = []
        for group in ThrRainbowGroup.allCases {
            let amt = amounts.amount(for: group)
            guard amt < .serving else { continue }     // missing or only a trace
            for food in (exampleFoods[group.rawValue] ?? []) {
                cands.append(ThrColorGap(group: group, food: food, missing: !amt.countsTowardSix))
            }
        }
        gapCandidates = cands.shuffled()
        gapCursor = 0
    }
}

// MARK: - Rainbow field-guide view (rich)

struct ThrRainbowPokedexView: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    var latestMeal: ConfirmedMeal? = nil

    @State private var model = ThrRainbowDetailModel()
    @State private var detailColor: ThrRainbowGroup?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space3) {
                        SectionHeader(title: "This week's spectrum", trailing: "\(model.hitCount)/6")
                        ThrRainbowRings(amounts: model.amounts) { detailColor = $0 }
                    }
                }
                .coachTarget("rainbow")
                if let gap = model.gapSuggestion { gapCard(gap) }
                ForEach(ThrRainbowGroup.allCases) { group in
                    let edu = model.education[group.rawValue] ?? ThrColorEducation(meaning: "", whatItDoes: "")
                    Button { detailColor = group } label: { colorRow(group, edu) }
                        .buttonStyle(.plain)
                }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Rainbow")
        .task {
            await model.load(appState: appState, latestMeal: latestMeal)
            await appState.coach.startIfNeeded("rainbow", appState: appState)
        }
        .sheet(item: $detailColor) { group in
            ThrColorDetailSheet(
                group: group,
                todayAmount: model.amount(for: group),
                weekly: model.weeklyAmounts(for: group),
                exampleFoods: model.examples(for: group),
                education: model.education[group.rawValue] ?? ThrColorEducation(meaning: "", whatItDoes: ""))
                .presentationDetents([.medium, .large])
        }
    }

    private func gapCard(_ gap: ThrColorGap) -> some View {
        Card {
            HStack(alignment: .top, spacing: theme.metrics.space3) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(gap.group.swatch)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gap.missing
                         ? "Missing \(gap.group.label.lowercased()) this week."
                         : "Light on \(gap.group.label.lowercased()) this week.")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("Try \(gap.food).")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Spacer()
                Button { withAnimation(.snappy) { model.refreshGap() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.colors.primary)
                }
                .accessibilityLabel("Suggest a different food")
            }
        }
    }

    private func colorRow(_ group: ThrRainbowGroup, _ edu: ThrColorEducation) -> some View {
        Card {
            HStack(spacing: theme.metrics.space3) {
                Circle().fill(group.swatch.opacity(model.amount(for: group).countsTowardSix ? 0.85 : 0.2))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(group.swatch, lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.label)
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(edu.whatItDoes)
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }
}

// MARK: - Phytochemical depth model

struct ThrPhytoGap: Identifiable, Sendable {
    let id = UUID()
    let phyto: ThrPhytochemicalRow
    let food: String
}

@MainActor
@Observable
final class ThrPhytoDepthModel {
    /// The three coverage windows (owner spec, round 2): this week, the last
    /// two weeks, the last month.
    enum CoverageWindow: Int, CaseIterable, Identifiable {
        case week = 7, fortnight = 14, month = 30
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week: "Eaten this week"
            case .fortnight: "Eaten last 2 weeks"
            case .month: "Eaten this month"
            }
        }
    }

    /// How far back the recency lookup reaches ("last eaten X days ago").
    static let recencyLookbackDays = 90

    var classes: [ThrPhytoClassRow] = []
    var compounds: [ThrPhytochemicalRow] = []
    var recentPhytoIds: Set<String> = []      // eaten within the gap window
    /// Compound ids eaten within each coverage window.
    var eatenByWindow: [CoverageWindow: Set<String>] = [:]
    /// Most recent day (yyyy-MM-dd) each compound crossed the plate, within the
    /// 90-day lookback (owner request, round 3: "last eaten X days ago").
    private(set) var lastEatenDayByPhyto: [String: String] = [:]
    /// Curated example foods per compound id ("where to find it").
    private(set) var foodNamesByPhyto: [String: [String]] = [:]
    var isLoaded = false

    private var gapCandidates: [ThrPhytoGap] = []
    private var gapCursor = 0

    var gapSuggestion: ThrPhytoGap? {
        guard !gapCandidates.isEmpty else { return nil }
        return gapCandidates[gapCursor % gapCandidates.count]
    }
    func refreshGap() { if !gapCandidates.isEmpty { gapCursor += 1 } }

    func compoundList(in klass: ThrPhytoClassRow) -> [ThrPhytochemicalRow] {
        compounds.filter { $0.phytoClass == klass.id }.sorted { $0.name < $1.name }
    }

    func coverage(_ window: CoverageWindow) -> Double {
        guard !compounds.isEmpty else { return 0 }
        return Double((eatenByWindow[window] ?? []).count) / Double(compounds.count)
    }

    /// Compounds NOT eaten within the window, in the database-list format.
    func missing(in window: CoverageWindow) -> [ThrPhytochemicalRow] {
        let eaten = eatenByWindow[window] ?? []
        return compounds.filter { !eaten.contains($0.id) }.sorted { $0.name < $1.name }
    }

    func exampleFoods(for compoundId: String, limit: Int = 4) -> [String] {
        Array((foodNamesByPhyto[compoundId] ?? []).prefix(limit))
    }

    func klass(for compound: ThrPhytochemicalRow) -> ThrPhytoClassRow? {
        classes.first { $0.id == compound.phytoClass }
    }

    /// "Eaten today" / "Last eaten 12 days ago" / "Not in your last 90 days".
    func recencyLabel(for compoundId: String) -> String {
        guard let day = lastEatenDayByPhyto[compoundId],
              let date = ThrDates.parseDay(day) else {
            return "Not in your last \(Self.recencyLookbackDays) days"
        }
        let days = Calendar.current.dateComponents(
            [.day], from: date, to: ThrDates.startOfToday()).day ?? 0
        switch days {
        case ..<1: return "Eaten today"
        case 1: return "Last eaten yesterday"
        default: return "Last eaten \(days) days ago"
        }
    }

    func load(appState: AppState) async {
        guard let repo = appState.repository else { isLoaded = true; return }
        async let cl: [ThrPhytoClassRow]      = (try? await repo.select("phyto_classes", order: "title")) ?? []
        async let ph: [ThrPhytochemicalRow]   = (try? await repo.select("phytochemicals", order: "name")) ?? []
        async let fp: [ThrFoodPhytoRow]        = (try? await repo.select("food_phytochemicals")) ?? []
        async let fn: [ThrFoodNameRow]         = (try? await repo.select("foods", columns: "id,canonical_name")) ?? []
        let (classes, compounds, foodPhytos, foods) = await (cl, ph, fp, fn)
        self.classes = classes
        self.compounds = compounds

        let nameByFood = Dictionary(foods.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { a, _ in a })
        var foodsByPhyto: [String: [String]] = [:]
        for r in foodPhytos { foodsByPhyto[r.phytochemicalId, default: []].append(r.foodId) }
        foodNamesByPhyto = foodsByPhyto.mapValues { ids in
            ids.compactMap { nameByFood[$0] }.sorted()
        }

        await computeRecent(repo, userId: appState.profile?.id, foodPhytos: foodPhytos)
        computeGapCandidates(foodsByPhyto: foodsByPhyto, nameByFood: nameByFood)
        isLoaded = true
    }

    /// Phytochemicals consumed per coverage window (7/14/30 days) PLUS the most
    /// recent day each compound crossed the plate (90-day lookback), via the
    /// user's meals -> meal_items -> food_phytochemicals. The month window
    /// doubles as the gap window.
    private func computeRecent(_ repo: Repository, userId: String?, foodPhytos: [ThrFoodPhytoRow]) async {
        let since = ThrDates.timestampString(
            Calendar.current.date(byAdding: .day, value: -Self.recencyLookbackDays,
                                  to: ThrDates.startOfToday()) ?? ThrDates.startOfToday())
        guard let meals: [MealRow] = try? await repo.select(
            "meals", columns: mealColumns, filters: ["captured_at": "gte.\(since)", "confirmed": "eq.true"]
        ), !meals.isEmpty else { return }
        let mealList = "(" + meals.map(\.id).joined(separator: ",") + ")"
        struct ItemRow: Decodable { let mealId: String; let foodId: String }
        guard let items: [ItemRow] = try? await repo.select(
            "meal_items", columns: "meal_id,food_id", filters: ["meal_id": "in.\(mealList)"]
        ) else { return }

        let dayByMeal = Dictionary(meals.map { ($0.id, ThrDates.localDayString($0.capturedAt)) },
                                   uniquingKeysWith: { a, _ in a })
        var phytosByFood: [String: [String]] = [:]
        for r in foodPhytos { phytosByFood[r.foodId, default: []].append(r.phytochemicalId) }

        // Most recent day per compound ("last eaten X days ago").
        var lastEaten: [String: String] = [:]
        for item in items {
            guard let day = dayByMeal[item.mealId] else { continue }
            for phyto in phytosByFood[item.foodId] ?? [] {
                if let existing = lastEaten[phyto], existing >= day { continue }
                lastEaten[phyto] = day
            }
        }
        lastEatenDayByPhyto = lastEaten

        let calendar = Calendar.current
        for window in CoverageWindow.allCases {
            guard let cutoff = calendar.date(byAdding: .day, value: -window.rawValue,
                                             to: ThrDates.startOfToday()) else { continue }
            let cutoffDay = ThrDates.dateString(cutoff)
            eatenByWindow[window] = Set(lastEaten.filter { $0.value >= cutoffDay }.keys)
        }
        recentPhytoIds = eatenByWindow[.month] ?? []
    }

    private func computeGapCandidates(foodsByPhyto: [String: [String]], nameByFood: [String: String]) {
        var cands: [ThrPhytoGap] = []
        for phyto in compounds where !recentPhytoIds.contains(phyto.id) {
            let foodName = (foodsByPhyto[phyto.id] ?? []).compactMap { nameByFood[$0] }.first
            if let foodName { cands.append(ThrPhytoGap(phyto: phyto, food: foodName)) }
        }
        gapCandidates = cands.shuffled()
        gapCursor = 0
    }
}

/// One `food_phytochemicals` junction row.
struct ThrFoodPhytoRow: Decodable, Sendable {
    let foodId: String
    let phytochemicalId: String
}

// MARK: - Phytochemical field-guide views (category -> compound -> detail)

struct ThrPhytochemicalPokedexView: View {
    @Environment(\.theme) private var theme
    let appState: AppState

    @State private var model = ThrPhytoDepthModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                if model.classes.isEmpty {
                    ThrEmptyState(icon: "atom",
                                  title: "No compounds catalogued yet",
                                  message: "As you log colorful plants, the phytochemicals they carry land here.")
                } else {
                    if let gap = model.gapSuggestion { gapCard(gap) }
                    coverageCard
                        .coachTarget("phytochemicals")
                    Text("Tap a category to see its compounds, then tap a compound to learn what it does.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                    ForEach(model.classes) { klass in
                        NavigationLink {
                            ThrPhytoClassDetailView(klass: klass, model: model)
                        } label: { classRow(klass) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Phytochemicals")
        .task {
            await model.load(appState: appState)
            await appState.coach.startIfNeeded("phytochemicals", appState: appState)
        }
    }

    // MARK: Coverage bars (owner spec, round 2): % of all compounds eaten per
    // window; tap a bar to see exactly which compounds you HAVEN'T had.

    private var coverageCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "Your coverage")
                Text("How much of the catalogue you've eaten. Tap a bar to see what's still out there.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(ThrPhytoDepthModel.CoverageWindow.allCases) { window in
                    NavigationLink {
                        ThrPhytoMissingListView(window: window, model: model)
                    } label: {
                        coverageRow(window)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func coverageRow(_ window: ThrPhytoDepthModel.CoverageWindow) -> some View {
        let fraction = model.coverage(window)
        let eaten = (model.eatenByWindow[window] ?? []).count
        return VStack(alignment: .leading, spacing: theme.metrics.space1) {
            HStack {
                Text(window.label)
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Text("\(eaten) of \(model.compounds.count)")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().strokeBorder(theme.colors.secondary.opacity(0.35), lineWidth: 1)
                    Capsule().fill(theme.colors.secondary.opacity(0.85))
                        .frame(width: max(4, geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 10)
        }
        .padding(.vertical, theme.metrics.space1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.label): \(eaten) of \(model.compounds.count) compounds. Tap for what's missing.")
    }

    private func gapCard(_ gap: ThrPhytoGap) -> some View {
        Card {
            HStack(alignment: .top, spacing: theme.metrics.space3) {
                Image(systemName: "lightbulb.fill").foregroundStyle(theme.colors.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No \(gap.phyto.name.replacingOccurrences(of: "_", with: " ")) logged in a while.")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("Try \(gap.food).")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Spacer()
                Button { withAnimation(.snappy) { model.refreshGap() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.colors.primary)
                }
                .accessibilityLabel("Suggest a different food")
            }
        }
    }

    private func classRow(_ klass: ThrPhytoClassRow) -> some View {
        Card {
            HStack(spacing: theme.metrics.space3) {
                Image(systemName: "atom").foregroundStyle(theme.colors.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(klass.title)
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(klass.description)
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }
}

struct ThrPhytoClassDetailView: View {
    @Environment(\.theme) private var theme
    let klass: ThrPhytoClassRow
    let model: ThrPhytoDepthModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space2) {
                        SectionHeader(title: "What this group is")
                        Text(klass.description)
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let def = klass.deficiencyCopy, !def.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            SectionHeader(title: "If you go short")
                            Text(def)
                                .font(theme.typography.body())
                                .foregroundStyle(theme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("Compounds in this group")
                    .font(theme.typography.title(20))
                    .foregroundStyle(theme.colors.textPrimary)
                ForEach(model.compoundList(in: klass), id: \.id) { compound in
                    NavigationLink {
                        ThrPhytoCompoundDetailView(compound: compound, klass: klass,
                                                   recent: model.recentPhytoIds.contains(compound.id),
                                                   exampleFoods: model.exampleFoods(for: compound.id),
                                                   recencyLabel: model.recencyLabel(for: compound.id))
                    } label: { compoundRow(compound) }
                        .buttonStyle(.plain)
                }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle(klass.title)
    }

    private func compoundRow(_ compound: ThrPhytochemicalRow) -> some View {
        Card {
            HStack(spacing: theme.metrics.space3) {
                Image(systemName: model.recentPhytoIds.contains(compound.id) ? "checkmark.seal.fill" : "atom")
                    .foregroundStyle(model.recentPhytoIds.contains(compound.id) ? theme.colors.success : theme.colors.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(compound.name.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(model.recencyLabel(for: compound.id))
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }
}

struct ThrPhytoCompoundDetailView: View {
    @Environment(\.theme) private var theme
    let compound: ThrPhytochemicalRow
    let klass: ThrPhytoClassRow
    let recent: Bool
    /// Curated foods that carry this compound ("what to eat to get more of it",
    /// owner request, round 2). From the food_phytochemicals junction.
    var exampleFoods: [String] = []
    /// "Last eaten X days ago" (owner request, round 3). nil hides the line.
    var recencyLabel: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                HStack(spacing: theme.metrics.space3) {
                    Image(systemName: "atom")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.colors.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(compound.name.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(theme.typography.display(26))
                            .foregroundStyle(theme.colors.primary)
                        Text(klass.title)
                            .font(theme.typography.caption(weight: .semibold))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                if let recencyLabel {
                    Text(recencyLabel)
                        .font(theme.typography.caption(weight: .semibold))
                        .foregroundStyle(recent ? theme.colors.success : theme.colors.textSecondary)
                } else if recent {
                    Text("You've logged this recently.")
                        .font(theme.typography.caption(weight: .semibold))
                        .foregroundStyle(theme.colors.success)
                }
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space2) {
                        SectionHeader(title: "What it does")
                        Text(compound.whatItDoes ?? klass.description)
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !exampleFoods.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            SectionHeader(title: "Find it in")
                            FlowRows(items: exampleFoods) { food in
                                Badge(text: food, tint: theme.colors.secondary)
                            }
                        }
                    }
                }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle(compound.name.replacingOccurrences(of: "_", with: " ").capitalized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Missing-compound list (tap-through from a coverage bar)

struct ThrPhytoMissingListView: View {
    @Environment(\.theme) private var theme
    let window: ThrPhytoDepthModel.CoverageWindow
    let model: ThrPhytoDepthModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                let missing = model.missing(in: window)
                if missing.isEmpty {
                    ThrEmptyState(icon: "checkmark.seal.fill",
                                  title: "Full coverage",
                                  message: "Every catalogued compound crossed your plate in this window. Remarkable eating.")
                } else {
                    Text("Compounds that haven't crossed your plate in this window — each one lists the foods that carry it.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(missing, id: \.id) { compound in
                        if let klass = model.klass(for: compound) {
                            NavigationLink {
                                ThrPhytoCompoundDetailView(
                                    compound: compound, klass: klass,
                                    recent: model.recentPhytoIds.contains(compound.id),
                                    exampleFoods: model.exampleFoods(for: compound.id),
                                    recencyLabel: model.recencyLabel(for: compound.id))
                            } label: { missingRow(compound) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle(window.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func missingRow(_ compound: ThrPhytochemicalRow) -> some View {
        Card {
            HStack(spacing: theme.metrics.space3) {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(theme.colors.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(compound.name.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(model.recencyLabel(for: compound.id))
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                    let foods = model.exampleFoods(for: compound.id, limit: 3)
                    if !foods.isEmpty {
                        Text("In \(foods.joined(separator: ", ").lowercased())")
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }
}
