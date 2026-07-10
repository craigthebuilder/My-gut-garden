//
//  GuildRootView.swift
//  MyGutGarden, Module D's public entry point: the four-district Guild Garden.
//
//  A fog-of-war trail (GuildDistrictMap) of the four districts; tapping an
//  unlocked guild pushes its collectible field-guide card (GuildDetailView).
//  Reads the
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
    private let gardenerName: String

    init(viewModel: GuildGardenViewModel, gardenerName: String = "Sprout") {
        _viewModel = State(initialValue: viewModel)
        self.gardenerName = gardenerName
    }

    /// Convenience for the shell: build the read model from the session.
    init(repository: Repository?, progression: ProgressionState, gardenerName: String = "Sprout") {
        self.init(viewModel: GuildGardenViewModel(repository: repository, progression: progression),
                  gardenerName: gardenerName)
    }

    var body: some View {
        NavigationStack(path: $path) {
            // The whole garden is now an interactive, pannable map (owner,
            // 2026-07-09). The map fills the tab; a tap opens a guild card.
            GuildWorldMapView(districts: viewModel.districts, gardenerName: gardenerName) { order, guild in
                path.append(GuildRoute(districtOrder: order, internalName: guild.internalName))
            }
            .coachTarget("garden")
            .navigationTitle("Garden map")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: GuildRoute.self) { route in
                if let resolved = resolve(route) {
                    GuildDetailView(guild: resolved.guild, districtName: resolved.districtName)
                }
            }
            .overlay { if viewModel.isLoading { ProgressView() } }
            .overlay(alignment: .bottom) {
                if viewModel.districts.isEmpty && !viewModel.isLoading {
                    Text("Your map grows in as you feed your garden.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(theme.metrics.space4)
                }
            }
        }
        .task { await viewModel.load() }
    }

    // The vertical-trail views (header / tier2 banner / world sections) are
    // retired: the garden is the interactive map now (GuildWorldMapView), and
    // the week-one locked state lives in the shell (ShellGardenLocked).

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
        .themed()
}

#Preview("Guild Garden, Tier 2 locked") {
    GuildRootView(viewModel: .preview(
        progression: ProgressionState(isTier2Unlocked: false, unlockedDistrictOrders: [], cumulativeTier2Days: 0)))
        .themed()
}

#Preview("Guild Garden, fully unlocked") {
    GuildRootView(viewModel: .preview(
        progression: ProgressionState(isTier2Unlocked: true, unlockedDistrictOrders: [1, 2, 3, 4], cumulativeTier2Days: 30)))
        .themed()
}
