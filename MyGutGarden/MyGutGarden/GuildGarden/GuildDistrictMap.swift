//
//  GuildDistrictMap.swift
//  MyGutGarden — the top-down district MAP with fog-of-war (design/references/
//  example-district-map-*.jpg). Four districts ascend a winding trail from the
//  foundation (World 1) to the endgame (World 4). Locked districts are fogged
//  and show "???"; unlocked ones reveal their guild pins with live bloom rings.
//

import SwiftUI

// MARK: - Unlock hints (built from GuildConfig — no magic numbers)

enum GuildUnlockHint {
    static func text(forDistrictOrder order: Int) -> String {
        let g = GuildConfig.shared
        switch order {
        case g.keystoneOrder:
            return "Bloom \(g.backboneBloomsForD2) Backbone guilds to open this district."
        case g.scientistOrder:
            return "Bloom a Keystone and keep logging for \(GameConfig.shared.district3MinCumulativeTier2Days) days to open."
        case g.hiddenGemsOrder:
            return "The endgame — bloom a Scientist to uncover the crews you host."
        default:
            return "Keep feeding your garden to open this district."
        }
    }
}

// MARK: - One guild pin on the map

struct GuildMapPin: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let guild: GuildDisplay
    let locked: Bool
    var onTap: () -> Void

    @State private var pulse = false
    private var isBlooming: Bool { !locked && guild.bloom.state == .blooming }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: theme.metrics.space1) {
                ZStack {
                    Circle()
                        .fill(theme.colors.surface)
                        .overlay(Circle().strokeBorder(ringColor, lineWidth: 3))
                    // bloom progress ring
                    if !locked {
                        Circle()
                            .trim(from: 0, to: guild.bloom.fraction)
                            .stroke(ringColor, style: .init(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Image(systemName: locked ? "questionmark" : guild.mascotSymbol)
                        .font(.system(size: 22))
                        .foregroundStyle(locked ? theme.colors.textSecondary : theme.colors.primary)
                }
                .frame(width: 56, height: 56)
                .scaleEffect(isBlooming && pulse && !reduceMotion ? 1.06 : 1)
                .shadow(color: isBlooming ? theme.colors.accent.opacity(0.4) : .clear, radius: 8)

                Text(locked ? "???" : guild.displayName)
                    .font(theme.typography.caption(weight: .medium))
                    .foregroundStyle(locked ? theme.colors.textSecondary : theme.colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 80)
            }
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .onAppear {
            guard isBlooming, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel(locked ? "Locked guild" :
            "\(guild.displayName), \(guild.bloom.state.displayLabel)")
        .accessibilityHint(locked ? "" : "Opens the field-guide card")
    }

    private var ringColor: Color {
        if locked { return theme.colors.divider }
        return guild.bloom.state == .blooming ? theme.colors.accent : theme.colors.secondary
    }
}

// MARK: - One district region on the trail

struct GuildDistrictMapZone: View {
    @Environment(\.theme) private var theme
    let district: GuildDistrictDisplay
    var onSelect: (GuildDisplay) -> Void

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space3) {
            header

            if district.isUnlocked {
                LazyVGrid(columns: columns, spacing: theme.metrics.space3) {
                    ForEach(district.guilds) { guild in
                        GuildMapPin(guild: guild, locked: false) { onSelect(guild) }
                    }
                }
            } else {
                lockedBody
            }
        }
        .padding(theme.metrics.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(zoneBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.radiusLarge, style: .continuous)
                .strokeBorder(district.isUnlocked ? theme.colors.secondary.opacity(0.5) : theme.colors.divider,
                              lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) { BotanicalFlourish().padding(theme.metrics.space3) }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space1) {
            HStack(spacing: theme.metrics.space2) {
                CollectibleNumberBadge(number: district.order)
                VStack(alignment: .leading, spacing: 0) {
                    Text("World \(district.order)")
                        .font(theme.typography.caption(weight: .semibold))
                        .foregroundStyle(theme.colors.secondary)
                    Text(district.isUnlocked ? district.name : "???")
                        .font(theme.typography.title(20))
                        .foregroundStyle(district.isUnlocked ? theme.colors.primary : theme.colors.textSecondary)
                }
            }
            if district.isUnlocked, district.bloomingCount > 0 {
                Text("\(district.bloomingCount) blooming")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.accent)
            }
        }
    }

    private var lockedBody: some View {
        HStack(spacing: theme.metrics.space3) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(theme.colors.textSecondary)
            Text(GuildUnlockHint.text(forDistrictOrder: district.order))
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, theme.metrics.space2)
        .accessibilityLabel("Locked. " + GuildUnlockHint.text(forDistrictOrder: district.order))
    }

    private var zoneBackground: some View {
        Group {
            if district.isUnlocked {
                LinearGradient(colors: [theme.colors.secondary.opacity(0.20), theme.colors.surface],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                theme.colors.divider.opacity(0.45) // fog
            }
        }
    }
}

// MARK: - The connecting trail segment between districts

struct GuildTrailConnector: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Capsule()
            .strokeBorder(style: .init(lineWidth: 3, lineCap: .round, dash: [2, 8]))
            .foregroundStyle(theme.colors.secondary.opacity(0.6))
            .frame(width: 4, height: 28)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
