//
//  ThrInsightPresenter.swift
//  MyGutGarden, Module C: the Thrive per-photo insight surface (SPEC §11a).
//
//  Conforms to `MealInsightPresenting` (App/Seams.swift): the AppShell injects
//  whichever presenter matches `current_mode`, so Module B (capture) never
//  imports C. Over a `ConfirmedMeal` this renders the celebration view, 
//  plant + new-discovery count, which P's, rainbow contribution, a directional
//  fiber read, and one curiosity fact, and fires a rare-find celebration
//  through `appState.celebrate(.rareFind(...))`.
//
//  Reuses `FoodAttributeJoin.thriveInsights(_:)` for all derivations and surfaces
//  `response.allergyAlerts` LOUD even mid-celebration (SPEC §9, rule #1).
//

import SwiftUI

@MainActor
struct ThrInsightPresenter: MealInsightPresenting {
    let appState: AppState

    init(appState: AppState) { self.appState = appState }

    func insightView(for meal: ConfirmedMeal) -> AnyView {
        AnyView(ThrInsightView(meal: meal, appState: appState))
    }
}

// MARK: - The per-photo view

struct ThrInsightView: View {
    @Environment(\.theme) private var theme
    let meal: ConfirmedMeal
    let appState: AppState

    /// Names already in the user's lifetime collection *before* this meal, used
    /// to compute "new" discoveries. Loaded best-effort; empty offline (so the
    /// demo shows everything as new).
    @State private var knownBefore: Set<String> = []
    @State private var curiosity: ThrCuriosityFactRow?
    @State private var didCelebrate = false

    private var insights: ThrivePhotoInsights { FoodAttributeJoin.thriveInsights(meal.response) }

    /// Surfaced (non-omitted) attributes, `preference_intolerance` already
    /// dropped upstream (§9). Used for rarity + fiber.
    private var attrs: [FoodAttributes] { FoodAttributeJoin.surfacedAttributes(meal.response) }

    private var newDiscoveries: [String] {
        insights.plantNames.filter { !knownBefore.contains($0) }
    }

    /// Coarse, directional fiber estimate (never precise, rule #3). Summed from
    /// the DB-derived per-serving estimates, rounded, and labelled directional.
    private var fiberApproxG: Int {
        let total = attrs.flatMap(\.fibers).compactMap(\.estGramsPerServing).reduce(0, +)
        return Int(total.rounded())
    }

    private var rainbowAdded: ThrRainbowStatus {
        var status = ThrRainbowStatus()
        for c in insights.colorsHit { status.mark(c, .hit) }
        return status
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                ThrAllergyBanner(alerts: meal.response.allergyAlerts)
                headline
                if !newDiscoveries.isEmpty { discoveriesCard }
                threePsCard
                rainbowCard
                fiberCard
                if let curiosity { ThrCuriosityCard(fact: curiosity.factText, confidenceTag: curiosity.confidenceTag) }
                hiddenPrompts
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("This meal")
        .task { await load() }
    }

    // MARK: Sections

    private var headline: some View {
        let plantCount = insights.plantNames.count
        let newCount = newDiscoveries.count
        return VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text(plantCount == 1 ? "1 plant" : "\(plantCount) plants")
                .font(theme.typography.display(34))
                .foregroundStyle(theme.colors.primary)
            if newCount > 0 {
                Text("\(newCount) new: \(newDiscoveries.joined(separator: ", "))")
                    .font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.accent)
            } else if plantCount > 0 {
                Text("All familiar friends today, every plant still feeds your garden.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
            } else {
                Text("No plants spotted yet, add one to start this meal's garden.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var discoveriesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "New to your field guide")
                FlowRows(items: newDiscoveries) { name in
                    let rarity = rarity(for: name)
                    Badge(text: rarity.triggersCelebration ? "\(name) · \(rarity.label)" : name,
                          tint: rarity.accent(theme))
                }
            }
        }
    }

    private var threePsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "The 3 P's", trailing: "\(insights.threePs.count)/3")
                ThrThreePsRow(amounts: ThrThreePAmounts(presence: insights.threePs))
                if insights.threePs.allThree {
                    Text("All three in one meal, prebiotic, probiotic, and polyphenol. Lovely.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.success)
                }
            }
        }
    }

    private var rainbowCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "Added to your rainbow")
                ThrRainbowRow(status: rainbowAdded)
                if insights.curiosityWorthyFermentedCount > 0 {
                    Text("Includes \(insights.curiosityWorthyFermentedCount) fermented find, live cultures on board.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
    }

    private var fiberCard: some View {
        Card {
            HStack(spacing: theme.metrics.space4) {
                VStack(alignment: .leading, spacing: theme.metrics.space1) {
                    Text("≈\(fiberApproxG) g fiber")
                        .font(theme.typography.data(24, weight: .semibold))
                        .foregroundStyle(theme.colors.primary)
                    // Honest about the camera's limits (SPEC §1, §4, rule #3).
                    Text("Directional, from what's visible on the plate, leaning generous.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.colors.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("About \(fiberApproxG) grams of fiber, directional estimate from visible portion.")
    }

    // R6: the generic "Worth a check" hidden-ingredient prompts were removed from the
    // snap result (the user doesn't want curated guesses there). Add a missed
    // ingredient via the photo annotation or the meal editor instead.
    @ViewBuilder private var hiddenPrompts: some View { EmptyView() }

    // MARK: Helpers

    private func rarity(for plantName: String) -> RarityTier {
        attrs.first { $0.plant?.name == plantName }?.plant?.rarityTier ?? .common
    }

    private func load() async {
        await loadKnownBefore()
        await loadCuriosity()
        await writeWeeklyColorAmounts()
        celebrateRareFindIfNeeded()
    }

    /// The Thrive ingest path for the rainbow's weekly history: upsert this meal's
    /// per-color max coarse tier into `weekly_color_amounts`, keeping the HIGHEST
    /// tier per color per week (a later trace can't lower an earlier serving). The
    /// MealIngestion coordinator owns plant/guild writes; the per-color amount is
    /// Thrive-surface state so it lives here (Module C ownership).
    private func writeWeeklyColorAmounts() async {
        guard let repo = appState.repository, let userId = appState.profile?.id else { return }

        // This meal's max tier per color group (coarse only, rule #3).
        var mealMax: [String: PortionTier] = [:]
        for item in meal.response.items where item.silentlyOmitted != true {
            guard let attrs = item.attributes else { continue }
            let tier = item.vision.portionTier
            for color in attrs.colors {
                if let existing = mealMax[color], existing.amountRank >= tier.amountRank { continue }
                mealMax[color] = tier
            }
        }
        guard !mealMax.isEmpty else { return }

        let weekStart = ThrDates.dateString(ThrDates.currentMonday())
        let existing: [WeeklyColorAmountRow] = (try? await repo.select(
            "weekly_color_amounts",
            filters: ["user_id": "eq.\(userId)", "week_start": "eq.\(weekStart)"]
        )) ?? []
        let existingByColor = Dictionary(existing.map { ($0.colorId, $0.maxTier) }, uniquingKeysWith: { a, _ in a })

        for (color, tier) in mealMax {
            // Skip when the stored week tier already dominates this meal's tier.
            if let stored = existingByColor[color],
               (PortionTier(rawValue: stored)?.amountRank ?? 0) >= tier.amountRank { continue }
            try? await repo.upsert("weekly_color_amounts", [
                "user_id": .string(userId),
                "week_start": .string(weekStart),
                "color_id": .string(color),
                "max_tier": .string(tier.rawValue),
            ], onConflict: "user_id,week_start,color_id")
        }
    }

    /// Plants logged *before* this meal's capture time (so a just-persisted row
    /// for this very meal still counts as a new discovery, regardless of whether
    /// the coordinator wrote before or after presenting).
    private func loadKnownBefore() async {
        guard let repo = appState.repository else { return }
        let rows: [UserPlantCollectionRow] = (try? await repo.select("user_plant_collection")) ?? []
        let plantRows: [PlantRow] = (try? await repo.fetchPlants()) ?? []
        let nameById = Dictionary(plantRows.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let cutoff = meal.capturedAt
        knownBefore = Set(rows.compactMap { row -> String? in
            guard let name = nameById[row.plantId] else { return nil }
            if let loggedAt = ThrDates.parseTimestamp(row.firstLoggedAt), loggedAt >= cutoff { return nil }
            return name
        })
    }

    private func loadCuriosity() async {
        guard let repo = appState.repository else { return }
        // Variable reward: a random curated fact (CLAUDE.md rule #9).
        if let facts: [ThrCuriosityFactRow] = try? await repo.select("curiosity_facts", limit: 50),
           let pick = facts.randomElement() {
            curiosity = pick
        }
    }

    /// Celebrate the *rarest* new rare/legendary plant (one overlay, not a burst).
    private func celebrateRareFindIfNeeded() {
        guard !didCelebrate else { return }
        let candidate = newDiscoveries
            .map { ($0, rarity(for: $0)) }
            .filter { $0.1.triggersCelebration }
            .max { $0.1.rank < $1.1.rank }
        if let (name, rarity) = candidate {
            appState.celebrate(.rareFind(plant: name, rarity: rarity))
            didCelebrate = true
        }
    }
}

// MARK: - Tiny wrapping layout for badge chips (no external dependency)

/// Lightweight flow layout so discovery/rarity chips wrap. Uses SwiftUI's
/// native `Layout`, token spacing passed in by the caller's environment.
struct FlowRows<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    @Environment(\.theme) private var theme
    let items: Data
    @ViewBuilder let content: (Data.Element) -> Content

    var body: some View {
        FlowLayout(spacing: theme.metrics.space2) {
            ForEach(Array(items), id: \.self) { content($0) }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
