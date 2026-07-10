//
//  ThrTrends.swift
//  MyGutGarden, Module C: how the 3 P's and the rainbow move over time
//  (owner request, 2026-07-02 round 2).
//
//  The dashboard's 3 P's / Rainbow pills tap through to a 14-day overlaid line
//  chart: three shades of green for the P's, the six rainbow hues for the
//  colors. Values are the day's coarse amount (none/trace/serving/lots → 0…1,
//  "normalized for volume") — directional, never grams (rule #3). Drawn with
//  the same token-driven Path approach as ThrTrendChart (no Charts dependency).
//

import SwiftUI
import Observation

// MARK: - Daily series loader (last 14 days, coarse amounts)

@MainActor
@Observable
final class ThrDailyTrendModel {
    static let windowDays = 14

    /// yyyy-MM-dd, oldest → newest, exactly `windowDays` entries.
    var days: [String] = []
    /// Series key → one 0…1 value per day (max coarse amount that day / 3).
    var threePs: [String: [Double]] = [:]        // "prebiotic" | "probiotic" | "polyphenol"
    var rainbow: [String: [Double]] = [:]        // color_id → values
    var isLoaded = false

    private struct ItemRow: Decodable, Sendable {
        let mealId: String
        let foodId: String
        let portionTier: String
    }
    private struct IdRow: Decodable, Sendable { let id: String }
    private struct FoodIdRow: Decodable, Sendable { let foodId: String }

    func load(appState: AppState) async {
        let calendar = Calendar.current
        let today = ThrDates.startOfToday()
        days = (0..<Self.windowDays).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today).map { ThrDates.dateString($0) }
        }
        var empty: [Double] { Array(repeating: 0, count: days.count) }
        threePs = ["prebiotic": empty, "probiotic": empty, "polyphenol": empty]
        rainbow = Dictionary(uniqueKeysWithValues: ThrRainbowGroup.allCases.map { ($0.rawValue, empty) })

        guard let repo = appState.repository else { isLoaded = true; return }
        let since = ThrDates.timestampString(
            calendar.date(byAdding: .day, value: -(Self.windowDays - 1), to: today) ?? today)
        guard let meals: [MealRow] = try? await repo.select(
            "meals", columns: "id,photo_url,captured_at,confirmed,user_annotation",
            filters: ["captured_at": "gte.\(since)", "confirmed": "eq.true"]
        ), !meals.isEmpty else { isLoaded = true; return }
        let dayByMeal = Dictionary(meals.map { ($0.id, String($0.capturedAt.prefix(10))) },
                                   uniquingKeysWith: { a, _ in a })
        let mealList = "(" + meals.map(\.id).joined(separator: ",") + ")"
        guard let items: [ItemRow] = try? await repo.select(
            "meal_items", columns: "meal_id,food_id,portion_tier",
            filters: ["meal_id": "in.\(mealList)"]), !items.isEmpty else { isLoaded = true; return }

        // Classification sets for every food involved (same rules as the Today
        // model: prebiotic = fiber or guild feed; probiotic = LIVE cultures
        // (has_live_cultures, NOT mere fermentation — owner 2026-07-09);
        // polyphenol = polyphenol-class compound or blue/purple).
        let foodIds = Set(items.map(\.foodId))
        let list = "(" + foodIds.joined(separator: ",") + ")"
        async let fibersT: [FoodIdRow] = (try? await repo.select("food_fibers", columns: "food_id", filters: ["food_id": "in.\(list)"])) ?? []
        async let guildsT: [FoodIdRow] = (try? await repo.select("food_guild_feeds", columns: "food_id", filters: ["food_id": "in.\(list)"])) ?? []
        async let fermentsT: [IdRow] = (try? await repo.select("foods", columns: "id", filters: ["id": "in.\(list)", "has_live_cultures": "eq.true"])) ?? []
        async let polyIdsT: [IdRow] = (try? await repo.select("phytochemicals", columns: "id", filters: ["class": "eq.polyphenol"])) ?? []
        async let foodPhytosT: [ThrFoodPhytoRow] = (try? await repo.select("food_phytochemicals", columns: "food_id,phytochemical_id", filters: ["food_id": "in.\(list)"])) ?? []
        async let colorsT: [ThrFoodColorRow] = (try? await repo.select("food_colors", columns: "food_id,color_id", filters: ["food_id": "in.\(list)"])) ?? []
        let (fibers, guilds, ferments, polyIds, foodPhytos, colors) =
            await (fibersT, guildsT, fermentsT, polyIdsT, foodPhytosT, colorsT)

        let prebioticFoods = Set(fibers.map(\.foodId)).union(guilds.map(\.foodId))
        let probioticFoods = Set(ferments.map(\.id))
        let polySet = Set(polyIds.map(\.id))
        var colorsByFood: [String: [String]] = [:]
        for c in colors { colorsByFood[c.foodId, default: []].append(c.colorId) }
        let polyphenolFoods = Set(foodPhytos.filter { polySet.contains($0.phytochemicalId) }.map(\.foodId))
            .union(colors.filter { $0.colorId == "blue_purple" }.map(\.foodId))

        let dayIndex = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1, $0) })
        func bump(_ dict: inout [String: [Double]], key: String, day: Int, amount: ThrColorAmount) {
            let value = Double(amount.ringsFilled) / 3.0
            if var series = dict[key], series[day] < value { series[day] = value; dict[key] = series }
        }
        for item in items {
            guard let day = dayByMeal[item.mealId].flatMap({ dayIndex[$0] }),
                  let tier = PortionTier(rawValue: item.portionTier) else { continue }
            let amount = ThrColorAmount(tier: tier)
            if prebioticFoods.contains(item.foodId)  { bump(&threePs, key: "prebiotic", day: day, amount: amount) }
            if probioticFoods.contains(item.foodId)  { bump(&threePs, key: "probiotic", day: day, amount: amount) }
            if polyphenolFoods.contains(item.foodId) { bump(&threePs, key: "polyphenol", day: day, amount: amount) }
            for color in colorsByFood[item.foodId] ?? [] {
                bump(&rainbow, key: color, day: day, amount: amount)
            }
        }
        isLoaded = true
    }
}

// MARK: - Overlaid multi-line chart (token-driven; no Charts dependency)

struct ThrTrendSeries: Identifiable {
    let id: String
    let label: String
    let color: Color
    /// 0…1 per day, oldest → newest.
    let values: [Double]
}

struct ThrMultiLineChart: View {
    @Environment(\.theme) private var theme
    let series: [ThrTrendSeries]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            GeometryReader { geo in
                ZStack {
                    // Quarter grid lines for scale.
                    ForEach(1..<4) { line in
                        let y = geo.size.height * CGFloat(line) / 4
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(theme.colors.divider.opacity(0.6), style: .init(lineWidth: 1, dash: [3, 5]))
                    }
                    ForEach(series) { s in
                        line(for: s.values, in: geo.size)
                            .stroke(s.color, style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(height: 150)
            // Legend: label + swatch, never color alone (DESIGN.md §5).
            FlowRows(items: series.map(\.id)) { id in
                if let s = series.first(where: { $0.id == id }) {
                    HStack(spacing: theme.metrics.space1) {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text(s.label)
                            .font(theme.typography.caption(11))
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                    .padding(.horizontal, theme.metrics.space2)
                    .padding(.vertical, 2)
                    .background(s.color.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func line(for values: [Double], in size: CGSize) -> Path {
        Path { p in
            guard values.count > 1 else { return }
            let stepX = size.width / CGFloat(values.count - 1)
            for (idx, value) in values.enumerated() {
                let point = CGPoint(x: stepX * CGFloat(idx),
                                    y: size.height * (1 - CGFloat(min(max(value, 0), 1))))
                if idx == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
        }
    }

    private var accessibilitySummary: String {
        series.map { s in
            let avg = s.values.isEmpty ? 0 : s.values.reduce(0, +) / Double(s.values.count)
            return "\(s.label) averaging \(Int((avg * 100).rounded())) percent"
        }.joined(separator: ". ")
    }
}

// MARK: - Rainbow trend screen (dashboard Rainbow pill taps through here)

struct ThrRainbowTrendView: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    var latestMeal: ConfirmedMeal? = nil

    @State private var model = ThrDailyTrendModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space3) {
                        SectionHeader(title: "The last two weeks")
                        Text("Each line is a color group; higher means more of it that day (coarse amounts, directional).")
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.isLoaded {
                            ThrMultiLineChart(series: rainbowSeries)
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                }
                NavigationLink {
                    ThrRainbowPokedexView(appState: appState, latestMeal: latestMeal)
                } label: {
                    ThrNavRow(icon: "circle.hexagongrid.fill", title: "The rainbow field guide",
                              subtitle: "Each color's week, example foods, and what it does")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, theme.metrics.space2)
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Rainbow trend")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(appState: appState) }
    }

    private var rainbowSeries: [ThrTrendSeries] {
        ThrRainbowGroup.allCases.map { group in
            ThrTrendSeries(id: group.rawValue, label: group.label, color: group.swatch,
                           values: model.rainbow[group.rawValue] ?? [])
        }
    }
}

// MARK: - The 3 P's trend card (embedded in ThrThreePsDetailView)

struct ThrThreePsTrendCard: View {
    @Environment(\.theme) private var theme
    let appState: AppState

    @State private var model = ThrDailyTrendModel()

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "The last two weeks")
                Text("Higher means more of that P that day (coarse amounts, directional).")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                if model.isLoaded {
                    ThrMultiLineChart(series: threePsSeries)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .task { await model.load(appState: appState) }
    }

    // Three shades of the theme's green family (owner spec).
    private var threePsSeries: [ThrTrendSeries] {
        [
            ThrTrendSeries(id: "prebiotic", label: "Prebiotic",
                           color: theme.colors.primary,
                           values: model.threePs["prebiotic"] ?? []),
            ThrTrendSeries(id: "probiotic", label: "Probiotic",
                           color: theme.colors.primary.opacity(0.62),
                           values: model.threePs["probiotic"] ?? []),
            ThrTrendSeries(id: "polyphenol", label: "Polyphenol",
                           color: theme.colors.primary.opacity(0.34),
                           values: model.threePs["polyphenol"] ?? []),
        ]
    }
}
