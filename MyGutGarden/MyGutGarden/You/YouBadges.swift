//
//  YouBadges.swift
//  MyGutGarden — badges (SPEC §13). Positive outcomes only (rule #7): they attach
//  to fiber goal, plant variety, the rainbow, and feeding guilds — NEVER to
//  restriction. Derived on read from existing progression (no separate store, no
//  "days restricted" anything), so they're always honest.
//

import SwiftUI
import Observation

struct YouBadge: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let earned: Bool
}

@MainActor
@Observable
final class YouBadgesModel {
    var badges: [YouBadge] = []
    var isLoading = false

    func load(_ appState: AppState) async {
        guard let repo = appState.repository else { return }
        isLoading = true
        defer { isLoading = false }
        async let summariesT: [WeeklySummaryRow] = repo.select("weekly_summaries")
        async let collectionT: [UserPlantCollectionRow] = repo.select("user_plant_collection")
        async let guildsT: [GuildStateRow] = repo.select("guild_state")
        async let colorsT: [WeeklyColorAmountRow] = repo.select("weekly_color_amounts")
        async let plantsT: [PlantRow] = repo.fetchPlants()
        async let fermentedT: [FermentedFoodRow] = repo.select(
            "foods", columns: "id,is_fermented", filters: ["is_fermented": "eq.true"])
        async let itemsT: [MealItemFoodRow] = repo.select("meal_items", columns: "food_id")
        let ws = (try? await summariesT) ?? []
        let pc = (try? await collectionT) ?? []
        let gs = (try? await guildsT) ?? []
        let wc = (try? await colorsT) ?? []
        let allPlants = (try? await plantsT) ?? []
        let fermentedFoodIds = Set(((try? await fermentedT) ?? []).map(\.id))
        let loggedFoodIds = Set(((try? await itemsT) ?? []).map(\.foodId))

        let hit30Any = ws.contains(where: \.hit30)
        let streak = ThrIngestor.consecutiveWeeklyHits(
            mostRecentFirst: ws.sorted { $0.weekStart > $1.weekStart }.map(\.hit30))
        let plantCount = pc.count
        let ownedIds = Set(pc.map(\.plantId))
        let everBloomed = gs.filter(\.hasEverBloomed).count
        let unlocked = appState.profile?.fiberGoalState == "unlocked"
        let bestWeek = ws.map(\.uniquePlantCount).max() ?? 0

        // Legendary + fermented collection progress (derived, honest, rule #7).
        let legendaryEaten = allPlants.filter { $0.rarityTier == .legendary && ownedIds.contains($0.id) }.count
        let fermentedEaten = loggedFoodIds.intersection(fermentedFoodIds).count

        var colorsByWeek: [String: Set<String>] = [:]
        for c in wc { colorsByWeek[c.weekStart, default: []].insert(c.colorId) }
        let rainbowWeek = colorsByWeek.values.contains { $0.count >= 6 }
        let rainbowWeeks = colorsByWeek.values.filter { $0.count >= 6 }.count

        badges = [
            // Fiber goal (positive, never restriction — rule #7).
            YouBadge(id: "goal", title: "Goal unlocked", detail: "Unlock your fiber goal", icon: "target", earned: unlocked),
            // Plant variety — the core loop.
            YouBadge(id: "first30", title: "First 30", detail: "30 different plants in a week", icon: "leaf.fill", earned: hit30Any),
            YouBadge(id: "streak3", title: "Consistent", detail: "A 3-week 30-plant streak", icon: "flame.fill", earned: streak >= 3),
            YouBadge(id: "streak8", title: "Rooted", detail: "An 8-week 30-plant streak", icon: "flame.circle.fill", earned: streak >= 8),
            YouBadge(id: "bigweek", title: "Overflowing", detail: "40 different plants in one week", icon: "sparkles", earned: bestWeek >= 40),
            // Lifetime collection.
            YouBadge(id: "collector", title: "Collector", detail: "50 plants in your field guide", icon: "books.vertical.fill", earned: plantCount >= 50),
            YouBadge(id: "botanist", title: "Botanist", detail: "100 plants in your field guide", icon: "book.closed.fill", earned: plantCount >= 100),
            YouBadge(id: "legendary", title: "Treasure hunter", detail: "Eat a legendary plant", icon: "crown.fill", earned: legendaryEaten >= 1),
            // Rainbow.
            YouBadge(id: "rainbow", title: "Full spectrum", detail: "All 6 colours in one week", icon: "sun.max.fill", earned: rainbowWeek),
            YouBadge(id: "rainbow4", title: "Prism", detail: "Full spectrum in 4 weeks", icon: "rainbow", earned: rainbowWeeks >= 4),
            // Fermented finds (the probiotic P).
            YouBadge(id: "ferment1", title: "Culture club", detail: "Log a fermented food", icon: "drop.fill", earned: fermentedEaten >= 1),
            YouBadge(id: "ferment5", title: "Live and well", detail: "Five different fermented foods", icon: "drop.circle.fill", earned: fermentedEaten >= 5),
            // Guilds.
            YouBadge(id: "firstbloom", title: "First bloom", detail: "Bloom a guild", icon: "leaf.arrow.triangle.circlepath", earned: everBloomed >= 1),
            YouBadge(id: "greenthumb", title: "Green thumb", detail: "Bloom three guilds", icon: "leaf.circle.fill", earned: everBloomed >= 3),
            YouBadge(id: "gardener", title: "Master gardener", detail: "Bloom six guilds", icon: "tree.fill", earned: everBloomed >= 6),
        ]
    }
}

/// Tiny decode rows for the derived fermented/collection badges.
private struct FermentedFoodRow: Decodable, Sendable { let id: String }
private struct MealItemFoodRow: Decodable, Sendable { let foodId: String }

struct YouBadgesView: View {
    @Environment(\.theme) private var theme
    let appState: AppState

    @State private var model = YouBadgesModel()

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                let earned = model.badges.filter(\.earned).count
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    Text("\(earned) of \(model.badges.count) earned")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    LazyVGrid(columns: columns, spacing: theme.metrics.space3) {
                        ForEach(model.badges) { badge in badgeTile(badge) }
                    }
                }
                .padding(theme.metrics.space4)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Badges")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await model.load(appState) }
    }

    private func badgeTile(_ badge: YouBadge) -> some View {
        Card {
            VStack(spacing: theme.metrics.space2) {
                Image(systemName: badge.earned ? badge.icon : "lock.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(badge.earned ? theme.colors.accent : theme.colors.textSecondary)
                Text(badge.title)
                    .font(theme.typography.body(weight: .semibold))
                    .foregroundStyle(badge.earned ? theme.colors.textPrimary : theme.colors.textSecondary)
                Text(badge.detail)
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .opacity(badge.earned ? 1 : 0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge.title), \(badge.earned ? "earned" : "locked"). \(badge.detail)")
    }
}
