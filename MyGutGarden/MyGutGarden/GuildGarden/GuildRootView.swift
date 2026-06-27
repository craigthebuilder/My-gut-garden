//
//  GuildRootView.swift
//  MyGutGarden, Module D's public entry point: the four-district Guild Garden.
//
//  A fog-of-war trail (GuildDistrictMap) of the four districts; tapping an
//  unlocked guild pushes its collectible field-guide card (GuildDetailView).
//  Thrive-only (SPEC §8: the Guild Garden never appears in Survive). Reads the
//  bloom state on the fly (decay applied on read) and the unlock state from the
//  ProgressionState read surface, it never writes `guild_state`/`user_districts`.
//

import SwiftUI

/// Hashable navigation value (GuildDisplay isn't Hashable; resolve on arrival).
struct GuildRoute: Hashable {
    let districtOrder: Int
    let internalName: String
}

struct GuildRootView: View {
    @Environment(\.theme) private var theme
    @State private var viewModel: GuildGardenViewModel
    @State private var path: [GuildRoute] = []

    init(viewModel: GuildGardenViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    /// Convenience for the shell: build the read model from the session.
    init(repository: Repository?, progression: ProgressionState) {
        self.init(viewModel: GuildGardenViewModel(repository: repository, progression: progression))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: theme.metrics.space4) {
                    header
                    if !viewModel.isTier2Unlocked { tier2LockedBanner }
                    trail
                }
                .padding(theme.metrics.space5)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Guild Garden")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: GuildRoute.self) { route in
                if let resolved = resolve(route) {
                    GuildDetailView(guild: resolved.guild, districtName: resolved.districtName)
                }
            }
            .overlay { if viewModel.isLoading { ProgressView() } }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text("Field guide")
                .font(theme.typography.caption(weight: .semibold))
                .foregroundStyle(theme.colors.secondary)
            Text("The Microbial Guild Garden")
                .font(theme.typography.display(30))
                .foregroundStyle(theme.colors.primary)
            Text("Feed the invisible crews that keep your gut humming. Sustained intake makes them bloom.")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)

            if viewModel.isTier2Unlocked {
                Badge(text: "\(viewModel.unlockedDistrictCount) of \(viewModel.totalDistrictCount) districts open",
                      tint: theme.colors.primary)
                    .padding(.top, theme.metrics.space1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tier-2 gate (the whole garden is a Tier-2 unlock, SPEC §13)

    private var tier2LockedBanner: some View {
        Card {
            HStack(alignment: .top, spacing: theme.metrics.space3) {
                Image(systemName: "seal.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.colors.secondary)
                VStack(alignment: .leading, spacing: theme.metrics.space1) {
                    Text("Earn your garden first")
                        .font(theme.typography.title(18))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("Finish your first week, hit 30 plants once, or log \(GameConfig.shared.tier2MinLoggedDaysFirstWeek) days, and the Guild Garden opens.")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
    }

    // MARK: The trail

    private var trail: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.districts.enumerated()), id: \.element.id) { index, district in
                if index > 0 { GuildTrailConnector() }
                GuildDistrictMapZone(district: district) { guild in
                    path.append(GuildRoute(districtOrder: district.order, internalName: guild.internalName))
                }
            }
        }
    }

    // MARK: Routing

    private func resolve(_ route: GuildRoute) -> (guild: GuildDisplay, districtName: String)? {
        guard let district = viewModel.districts.first(where: { $0.order == route.districtOrder }),
              let guild = district.guilds.first(where: { $0.internalName == route.internalName })
        else { return nil }
        return (guild, district.name)
    }
}

#Preview("Guild Garden, partial unlock") {
    GuildRootView(viewModel: .preview())
        .themed(for: .thrive)
}

#Preview("Guild Garden, Tier 2 locked") {
    GuildRootView(viewModel: .preview(
        progression: ProgressionState(isTier2Unlocked: false, unlockedDistrictOrders: [], cumulativeTier2Days: 0)))
        .themed(for: .thrive)
}

#Preview("Guild Garden, fully unlocked") {
    GuildRootView(viewModel: .preview(
        progression: ProgressionState(isTier2Unlocked: true, unlockedDistrictOrders: [1, 2, 3, 4], cumulativeTier2Days: 30)))
        .themed(for: .thrive)
}
