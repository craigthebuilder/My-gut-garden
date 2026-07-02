//
//  GuildDetailView.swift
//  MyGutGarden, the collectible field-guide card for one guild (the Pokédex
//  "double-click" view from design/references/double-click-into-the-*.jpg).
//
//  Composes the shared `FieldGuideCard` (numbered, eyebrow, mascot slot, ornate
//  parchment) and adds Module D's bloom meter + what-to-feed. 🔒 Fence 2: a
//  claim_risk guild renders `EmergingScienceTag` (via the card) AND surfaces its
//  `substantiation`, so its name never reads as a bare health claim.
//

import SwiftUI

// MARK: - Bloom meter (the §13 state machine, made visible)

/// Four-state nourishment meter. Shows the bloom STATE (gain-framed label), a
/// fill bar, and the well-fed rhythm badge. Deliberately directional, no precise
/// number is surfaced (SPEC §1: never claim precision the model can't deliver).
struct GuildBloomMeter: View {
    @Environment(\.theme) private var theme
    let bloom: GuildBloomDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space3) {
            HStack(alignment: .firstTextBaseline) {
                Text(bloom.state.displayLabel)
                    .font(theme.typography.title(20))
                    .foregroundStyle(bloom.state == .blooming ? theme.colors.accent : theme.colors.primary)
                Spacer()
                if bloom.isWellFed {
                    Badge(text: "Well-fed", tint: theme.colors.success)
                }
            }

            // Fill bar across the four states.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.colors.divider)
                    Capsule()
                        .fill(bloom.state == .blooming ? theme.colors.accent : theme.colors.primary)
                        .frame(width: max(6, geo.size.width * bloom.fraction))
                }
            }
            .frame(height: 12)

            HStack {
                ForEach(GuildBloomState.allCases, id: \.self) { s in
                    Text(s.displayLabel)
                        .font(theme.typography.caption(weight: s == bloom.state ? .semibold : .regular))
                        .foregroundStyle(s == bloom.state ? theme.colors.primary : theme.colors.textSecondary)
                    if s != GuildBloomState.allCases.last { Spacer() }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bloom state: \(bloom.state.displayLabel)"
                            + (bloom.isWellFed ? ", well-fed this week" : ""))
    }
}

// MARK: - Mascot symbol per guild (placeholder until owner art ships)

extension GuildDisplay {
    /// A flavour SF Symbol for the mascot slot, by guild. Owner mascot art (the
    /// reference illustrations) replaces this later via `IllustrationPlaceholder`.
    var mascotSymbol: String {
        switch internalName {
        case "anti_inflammatory_arsenal": "shield.lefthalf.filled"
        case "appetite_crew": "fork.knife"
        case "base_layer": "square.stack.3d.up.fill"
        case "recycling_engine": "arrow.3.trianglepath"
        case "locksmith": "key.fill"
        case "knights_of_the_wall": "shield.fill"
        case "vitamin_lab": "flask.fill"
        case "mood_regulators": "brain.head.profile"
        case "estrogen_regulators": "sparkles"
        case "mitochondria_boosters": "bolt.fill"
        case "tumor_preventors": "leaf.arrow.triangle.circlepath"
        case "stone_breakers": "hammer.fill"
        default: "leaf.fill"
        }
    }
}

// MARK: - Detail screen

struct GuildDetailView: View {
    @Environment(\.theme) private var theme
    let guild: GuildDisplay
    let districtName: String

    @State private var showBloomCelebration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space5) {
                FieldGuideCard(
                    number: guild.number,
                    eyebrow: guild.eyebrow(districtName: districtName),
                    title: guild.displayName,
                    subtitle: nil,
                    bodyText: guild.functionCopy,
                    rarity: nil,
                    emergingScience: guild.claimRisk          // 🔒 Fence 2
                ) {
                    IllustrationPlaceholder(systemImage: guild.mascotSymbol,
                                            tint: theme.colors.primary)
                }

                Card {
                    GuildBloomMeter(bloom: guild.bloom)
                }

                feedsCard

                confidenceCard

                if guild.bloom.state == .blooming { replayBloomButton }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle(guild.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if showBloomCelebration {
                GuildBloomCelebrationView(guildDisplayName: guild.displayName,
                                          claimRisk: guild.claimRisk,
                                          mascotSystemImage: guild.mascotSymbol) {
                    showBloomCelebration = false
                }
            }
        }
    }

    private var feedsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                SectionHeader(title: "Feed it")
                Text(guild.feedsCopy ?? "A varied, plant-forward plate.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Feeding adds up; skipping a few days lets it fade. Rhythm beats big one-offs.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private var confidenceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                HStack(spacing: theme.metrics.space2) {
                    Badge(text: guild.confidenceTag.capitalized)
                    if guild.claimRisk { EmergingScienceTag() } // 🔒 Fence 2
                }
                if guild.claimRisk, let substantiation = guild.substantiation {
                    Text(substantiation)
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
    }

    private var replayBloomButton: some View {
        SecondaryButton(title: "Replay the bloom", systemImage: "sparkles") {
            showBloomCelebration = true
        }
    }
}

#Preview("Guild detail, Blooming") {
    NavigationStack {
        GuildDetailView(guild: GuildGardenViewModel.preview().districts[0].guilds[0],
                        districtName: "The Backbone District")
    }
    .themed()
}

#Preview("Guild detail, claim-risk (Fence 2)") {
    let vm = GuildGardenViewModel.preview()
    let scientists = vm.districts.first { $0.order == 3 }!
    return NavigationStack {
        GuildDetailView(guild: scientists.guilds.first { $0.claimRisk }!,
                        districtName: scientists.name)
    }
    .themed()
}
