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
        let ws = (try? await summariesT) ?? []
        let pc = (try? await collectionT) ?? []
        let gs = (try? await guildsT) ?? []
        let wc = (try? await colorsT) ?? []

        let hit30Any = ws.contains(where: \.hit30)
        let streak = ThrIngestor.consecutiveWeeklyHits(
            mostRecentFirst: ws.sorted { $0.weekStart > $1.weekStart }.map(\.hit30))
        let plantCount = pc.count
        let everBloomed = gs.filter(\.hasEverBloomed).count
        let unlocked = appState.profile?.fiberGoalState == "unlocked"

        var colorsByWeek: [String: Set<String>] = [:]
        for c in wc { colorsByWeek[c.weekStart, default: []].insert(c.colorId) }
        let rainbowWeek = colorsByWeek.values.contains { $0.count >= 6 }

        badges = [
            YouBadge(id: "goal", title: "Goal unlocked", detail: "Unlock your fiber goal", icon: "target", earned: unlocked),
            YouBadge(id: "first30", title: "First 30", detail: "30 plants in a week", icon: "leaf.fill", earned: hit30Any),
            YouBadge(id: "streak3", title: "Consistent", detail: "A 3-week 30-plant streak", icon: "flame.fill", earned: streak >= 3),
            YouBadge(id: "collector", title: "Collector", detail: "50 plants in your field guide", icon: "books.vertical.fill", earned: plantCount >= 50),
            YouBadge(id: "rainbow", title: "Full spectrum", detail: "All 6 colours in one week", icon: "sun.max.fill", earned: rainbowWeek),
            YouBadge(id: "firstbloom", title: "First bloom", detail: "Bloom a guild", icon: "sparkles", earned: everBloomed >= 1),
            YouBadge(id: "greenthumb", title: "Green thumb", detail: "Bloom three guilds", icon: "leaf.circle.fill", earned: everBloomed >= 3),
        ]
    }
}

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
