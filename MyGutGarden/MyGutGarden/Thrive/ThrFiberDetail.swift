//
//  ThrFiberDetail.swift
//  MyGutGarden, Module C: the "Your fiber" surface (SPEC §17).
//
//  Tapping the Today fiber line (locked or unlocked) opens this page: the goal
//  trend, then the owner-requested composition history — the last two weeks of
//  daily fiber split by FERMENTATION SPEED (fast / moderate / gentle, from
//  fibers.fermentability) and by SOLUBILITY (soluble / insoluble / resistant,
//  from fibers.solubility) — plus the adaptation education. This is where
//  "what has my FODMAP-ish load looked like?" gets answered, in
//  fermentability-first language: the word FODMAP appears exactly once below,
//  as the education bridge (SPEC §17 language rule).
//
//  Everything is directional (Σ coarse per-serving estimates × portion tier),
//  never a measured claim (rule #3). Curated copy only (rule #11); 🔒 Fence 2/4.
//

import SwiftUI
import Observation

// MARK: - Loader (14 days of composition, one batched read)

@MainActor
@Observable
final class ThrFiberTrendModel {
    static let windowDays = 14

    /// yyyy-MM-dd, oldest → newest.
    var days: [String] = []
    /// Total directional fiber per day (Σ meal_items.est_fiber_g).
    var totalByDay: [Double] = []
    /// Fermentation-speed series, grams per day: "high" | "moderate" | "low".
    var bySpeed: [String: [Double]] = [:]
    /// Solubility series, grams per day: "soluble" | "insoluble" | "resistant".
    var bySolubility: [String: [Double]] = [:]
    var isLoaded = false

    private struct ItemRow: Decodable, Sendable {
        let mealId: String
        let foodId: String
        let portionTier: String
        let estFiberG: Double?
        let estGrams: Double?
    }
    private struct FiberRow: Decodable, Sendable {
        let id: String
        let fermentability: String?
        let solubility: String?
    }
    private struct JunctionRow: Decodable, Sendable {
        let foodId: String
        let fiberId: String
        let estGramsPerServing: Double?
    }

    func load(appState: AppState) async {
        let calendar = Calendar.current
        let today = ThrDates.startOfToday()
        days = (0..<Self.windowDays).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today).map { ThrDates.dateString($0) }
        }
        var empty: [Double] { Array(repeating: 0, count: days.count) }
        totalByDay = empty
        bySpeed = ["high": empty, "moderate": empty, "low": empty]
        bySolubility = ["soluble": empty, "insoluble": empty, "resistant": empty]

        guard let repo = appState.repository else { isLoaded = true; return }
        let since = ThrDates.timestampString(
            calendar.date(byAdding: .day, value: -(Self.windowDays - 1), to: today) ?? today)
        guard let meals: [MealRow] = try? await repo.select(
            "meals", columns: "id,photo_url,captured_at,confirmed,user_annotation",
            filters: ["captured_at": "gte.\(since)", "confirmed": "eq.true"]
        ), !meals.isEmpty else { isLoaded = true; return }
        let dayIndex = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1, $0) })
        let dayByMeal = Dictionary(meals.map { ($0.id, String($0.capturedAt.prefix(10))) },
                                   uniquingKeysWith: { a, _ in a })
        let mealList = "(" + meals.map(\.id).joined(separator: ",") + ")"
        guard let items: [ItemRow] = try? await repo.select(
            "meal_items", columns: "meal_id,food_id,portion_tier,est_fiber_g,est_grams",
            filters: ["meal_id": "in.\(mealList)"]), !items.isEmpty else { isLoaded = true; return }

        // Per-food composition from the reference tables.
        struct ServingRow: Decodable, Sendable { let id: String; let typicalServingG: Double? }
        async let fibersT: [FiberRow] = (try? await repo.select(
            "fibers", columns: "id,fermentability,solubility")) ?? []
        async let junctionsT: [JunctionRow] = (try? await repo.select(
            "food_fibers", columns: "food_id,fiber_id,est_grams_per_serving")) ?? []
        async let servingsT: [ServingRow] = (try? await repo.select(
            "foods", columns: "id,typical_serving_g")) ?? []
        let (fibers, junctions, servings) = await (fibersT, junctionsT, servingsT)
        let fiberById = Dictionary(fibers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let servingByFood = Dictionary(servings.compactMap { r in r.typicalServingG.map { (r.id, $0) } },
                                       uniquingKeysWith: { a, _ in a })

        // food_id → per-serving grams by speed + solubility bucket.
        var speedByFood: [String: [String: Double]] = [:]
        var solByFood: [String: [String: Double]] = [:]
        for j in junctions {
            guard let fiber = fiberById[j.fiberId], let grams = j.estGramsPerServing else { continue }
            if let speed = fiber.fermentability {
                speedByFood[j.foodId, default: [:]][speed, default: 0] += grams
            }
            if let sol = fiber.solubility {
                solByFood[j.foodId, default: [:]][sol, default: 0] += grams
            }
        }

        for item in items {
            guard let day = dayByMeal[item.mealId].flatMap({ dayIndex[$0] }) else { continue }
            totalByDay[day] += item.estFiberG ?? 0
            let mult = PortionMath.ratio(estGrams: item.estGrams,
                                         typicalServingG: servingByFood[item.foodId],
                                         tier: item.portionTier)
            for (speed, grams) in speedByFood[item.foodId] ?? [:] {
                bySpeed[speed]?[day] += grams * mult
            }
            for (sol, grams) in solByFood[item.foodId] ?? [:] {
                bySolubility[sol]?[day] += grams * mult
            }
        }
        isLoaded = true
    }

    /// Normalizer so composition lines share one scale (max daily total, or 1).
    var chartMax: Double { max(totalByDay.max() ?? 1, 1) }
}

// MARK: - Daily total bars (goal as a dashed line)

struct ThrFiberBarsChart: View {
    @Environment(\.theme) private var theme
    let values: [Double]           // grams per day, oldest → newest
    let goalG: Int?

    var body: some View {
        GeometryReader { geo in
            let top = max(values.max() ?? 1, Double(goalG ?? 0), 1)
            let count = max(values.count, 1)
            let slot = geo.size.width / CGFloat(count)
            let barWidth = max(5, slot * 0.55)
            ZStack(alignment: .bottomLeading) {
                if let goal = goalG {
                    let y = geo.size.height * (1 - CGFloat(Double(goal) / top))
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(theme.colors.accent, style: .init(lineWidth: 1.5, dash: [4, 4]))
                }
                ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                    let h = geo.size.height * CGFloat(value / top)
                    RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous)
                        .fill(theme.colors.primary.opacity(value > 0 ? 0.8 : 0.15))
                        .frame(width: barWidth, height: max(3, h))
                        .position(x: slot * (CGFloat(idx) + 0.5), y: geo.size.height - max(3, h) / 2)
                }
                // Grams scale: peak at the top, and the goal beside its line.
                Text("\(Int(top.rounded())) g")
                    .font(theme.typography.caption(10))
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, 3)
                    .background(theme.colors.surface.opacity(0.85))
                    .position(x: 18, y: 8)
                if let goal = goalG {
                    let y = geo.size.height * (1 - CGFloat(Double(goal) / top))
                    Text("goal \(goal)")
                        .font(theme.typography.caption(10))
                        .foregroundStyle(theme.colors.accent)
                        .padding(.horizontal, 3)
                        .background(theme.colors.surface.opacity(0.85))
                        .position(x: geo.size.width - 26, y: max(8, y - 8))
                }
            }
        }
        .frame(height: 110)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let goalText = goalG.map { ", goal \($0) grams" } ?? ""
        return "Fiber over the last \(values.count) days, averaging \(Int(avg.rounded())) grams directional\(goalText)"
    }
}

// MARK: - The charts (shared: inline on Today's dashboard + the detail page)

/// The fiber charts — today + distance to goal, the 14-day trend, and the
/// composition split by fermentation speed and by type. Owns its own trend
/// model so it can be dropped inline (Today, owner 2026-07-17) or in the
/// detail page. The detail page adds the education cards + the "yourfiber"
/// tour anchor around this; the inline copy stays anchor-free (one per key).
struct ThrFiberCharts: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    /// The Today model (goal + today's consumed), shared by reference.
    let homeModel: ThrHomeModel

    @State private var model = ThrFiberTrendModel()

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            todayCard
            trendCard
            compositionSpeedCard
            compositionSolubilityCard
        }
        .task { await model.load(appState: appState) }
    }

    private var todayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                if let goal = homeModel.fiberGoalG {
                    let consumed = Int(homeModel.fiberConsumedTodayG.rounded())
                    let toGo = max(0, goal - consumed)
                    SectionHeader(title: "Today", trailing: "\(consumed) / \(goal) g")
                    Text(toGo > 0
                         ? "\(toGo) g to your goal today — directional, from what's visible on your plates. The goal rises gently as it keeps sitting well."
                         : "Goal reached today — directional, from what's visible on your plates. The goal rises gently as it keeps sitting well.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    SectionHeader(title: "Your goal is coming")
                    Text("No number in week one — we watch how you actually eat first. Explore 30 plants and it unlocks at a level that's comfortable for you.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var trendCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "The last two weeks")
                if model.isLoaded {
                    ThrFiberBarsChart(values: model.totalByDay, goalG: homeModel.fiberGoalG)
                    if homeModel.fiberGoalG != nil {
                        Text("Bars are each day's directional total; the dashed line is your goal.")
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var compositionSpeedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "By fermentation speed")
                Text("Different speeds reach different stretches of your gut: fast-fermenting fibers are eaten early (and make the most gas), slower ones travel further to feed the crews deeper down. Variety covers the whole length.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.isLoaded {
                    // Owner (2026-07-08): today's fast-fermenting load reads as
                    // a 5-dot band + a word, never a gram number — there is no
                    // gram scale for fermentable load a person would recognize.
                    HStack {
                        Text("Today")
                            .font(theme.typography.caption(weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                        Spacer()
                        DotBand(level: GameConfig.shared.fastFermentBandLevel(dayG: todayFastG),
                                label: GameConfig.shared.fastFermentBandLabel(dayG: todayFastG))
                    }
                    ThrMultiLineChart(series: speedSeries, peakG: model.chartMax)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var compositionSolubilityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "By type")
                Text("Soluble gels and feeds; insoluble sweeps and bulks; resistant starch sneaks past digestion to feed the deep crews.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.isLoaded {
                    ThrMultiLineChart(series: solubilitySeries, peakG: model.chartMax)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func normalized(_ values: [Double]) -> [Double] {
        values.map { $0 / model.chartMax }
    }

    /// Today's directional fast-fermenting grams (internal only — surfaces as
    /// the 5-dot band, never a number).
    private var todayFastG: Double { model.bySpeed["high"]?.last ?? 0 }

    /// "N g today" for a series' most recent day, or nil if there's nothing yet.
    private func todayLabel(_ values: [Double]?) -> String? {
        guard let g = values?.last, g > 0 else { return nil }
        return "\(Int(g.rounded())) g today"
    }

    private var speedSeries: [ThrTrendSeries] {
        [
            ThrTrendSeries(id: "high", label: "Fast-fermenting", color: theme.colors.accent,
                           values: normalized(model.bySpeed["high"] ?? []),
                           trailingValue: todayLabel(model.bySpeed["high"])),
            ThrTrendSeries(id: "moderate", label: "Moderate", color: theme.colors.primary,
                           values: normalized(model.bySpeed["moderate"] ?? []),
                           trailingValue: todayLabel(model.bySpeed["moderate"])),
            ThrTrendSeries(id: "low", label: "Gentle", color: theme.colors.secondary,
                           values: normalized(model.bySpeed["low"] ?? []),
                           trailingValue: todayLabel(model.bySpeed["low"])),
        ]
    }

    private var solubilitySeries: [ThrTrendSeries] {
        [
            ThrTrendSeries(id: "soluble", label: "Soluble", color: theme.colors.primary,
                           values: normalized(model.bySolubility["soluble"] ?? []),
                           trailingValue: todayLabel(model.bySolubility["soluble"])),
            ThrTrendSeries(id: "insoluble", label: "Insoluble", color: theme.colors.secondary,
                           values: normalized(model.bySolubility["insoluble"] ?? []),
                           trailingValue: todayLabel(model.bySolubility["insoluble"])),
            ThrTrendSeries(id: "resistant", label: "Resistant starch", color: theme.colors.accent,
                           values: normalized(model.bySolubility["resistant"] ?? []),
                           trailingValue: todayLabel(model.bySolubility["resistant"])),
        ]
    }

}

// MARK: - The detail page (charts + education + the "yourfiber" tour)

struct ThrFiberDetailView: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    let homeModel: ThrHomeModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                ThrFiberCharts(appState: appState, homeModel: homeModel)
                    .coachTarget("yourfiber")
                educationCards
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Your fiber")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appState.coach.startIfNeeded("yourfiber", appState: appState) }
    }

    // MARK: Education (curated, rule #11; 🔒 Fence 2/4 RD-REVIEW-REQUIRED).
    // The ONE place the word FODMAP appears (SPEC §17 language rule).

    private static let education: [(title: String, body: String, icon: String)] = [
        ("Fast fibers, slow fibers",
         "Fast-fermenting fibers — onions, garlic, beans, chicory — get eaten within hours, near the start of the colon (they're what clinicians call FODMAPs, and they make the most gas). Slower fibers travel further and feed the crews deeper down, toward the end of the colon that's often under-fed. It's not that one grows more — different speeds reach different stretches of your gut, so variety feeds the whole length.",
         "wind"),
        ("Gas is a signal, not a failure",
         "Fermentation IS the process working — gas means your microbes are eating. The question is only how much is comfortable for you. Your gas-comfort setting (in You) tunes how fast we nudge you upward; change it any time.",
         "bubbles.and.sparkles"),
        ("Your gut adapts",
         "Feed a crew steadily and it literally grows capacity — a meal that felt lively a month ago sits quietly once the microbes that eat it multiply. Slow, steady increases are the whole trick, and it's why the goal ramps gently instead of jumping.",
         "arrow.up.right.circle"),
    ]

    private var educationCards: some View {
        ForEach(Self.education, id: \.title) { item in
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
}
