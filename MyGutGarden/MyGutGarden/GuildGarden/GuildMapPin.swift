//
//  GuildMapPin.swift
//  MyGutGarden — the guild pin + unlock-hint building blocks used by the
//  interactive garden map (GuildWorldMap.swift). A pin is one guild on the map:
//  a bloom-ring around its mascot, locked pins fogged as "???". (Formerly
//  GuildDistrictMap.swift, which also held the retired vertical-trail zone.)
//

import SwiftUI

// MARK: - Unlock hints (built from GuildConfig, no magic numbers)

enum GuildUnlockHint {
    static func text(forDistrictOrder order: Int) -> String {
        let g = GuildConfig.shared
        switch order {
        case g.keystoneOrder:
            return "Bloom \(g.backboneBloomsForD2) Backbone guilds to open this district."
        case g.scientistOrder:
            return "Bloom a Keystone and keep logging for \(GameConfig.shared.district3MinCumulativeTier2Days) days to open."
        case g.hiddenGemsOrder:
            return "The endgame, bloom a Scientist to uncover the crews you host."
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
