//
//  FieldGuide.swift
//  MyGutGarden, the collectible field-guide card system (the signature element).
//
//  Modeled on design/references/double-click-into-the-*-example.jpg (guild cards)
//  and the trading-card framing in rare-accent-outline.jpg. Reused by D (guild
//  detail) and C (Plant/Phytochemical pokédex, rare-find reveal). Mascot art is
//  owner-supplied later; an illustration slot defaults to a tinted placeholder.
//

import SwiftUI

/// Rarity → accent treatment (outline/holo intensity scales celebration, §13).
extension RarityTier {
    func accent(_ theme: any Theme) -> Color {
        switch self {
        case .common: theme.colors.secondary
        case .uncommon: theme.colors.primary
        case .rare: theme.colors.accent
        case .legendary: theme.colors.warning
        }
    }
    var label: String { rawValue.capitalized }
}

/// Numbered roundel badge (the "3"/"9" corner mark on the reference cards).
struct CollectibleNumberBadge: View {
    @Environment(\.theme) private var theme
    let number: Int
    var rarity: RarityTier = .common

    var body: some View {
        Text("\(number)")
            .font(theme.typography.display(20))
            .foregroundStyle(theme.colors.surface)
            .frame(width: 38, height: 38)
            .background(Circle().fill(rarity.accent(theme)))
            .overlay(Circle().strokeBorder(theme.colors.surface, lineWidth: 2))
            .accessibilityLabel("Number \(number), \(rarity.label)")
    }
}

/// Placeholder illustration slot (owner drops mascot art here later).
struct IllustrationPlaceholder: View {
    @Environment(\.theme) private var theme
    var systemImage = "leaf.fill"
    var tint: Color? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous)
                .fill((tint ?? theme.colors.secondary).opacity(0.18))
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle((tint ?? theme.colors.secondary).opacity(0.7))
        }
        .accessibilityHidden(true)
    }
}

/// The detail collectible card, guild detail, rare-plant reveal, pokédex entry.
struct FieldGuideCard<Illustration: View>: View {
    @Environment(\.theme) private var theme
    var number: Int? = nil
    var eyebrow: String? = nil          // e.g. "World 1, The Backbone District"
    let title: String
    var subtitle: String? = nil
    var bodyText: String? = nil
    var rarity: RarityTier? = nil
    var emergingScience = false         // Fence 2, set for claim_risk guilds
    @ViewBuilder var illustration: () -> Illustration

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space3) {
            HStack(alignment: .top) {
                if let number { CollectibleNumberBadge(number: number, rarity: rarity ?? .common) }
                Spacer()
                BotanicalFlourish()
            }

            illustration()
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))

            if let eyebrow {
                Text(eyebrow)
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.secondary)
            }
            Text(title)
                .font(theme.typography.display(28))
                .foregroundStyle(theme.colors.primary)

            if emergingScience { EmergingScienceTag() }
            if let rarity { Badge(text: rarity.label, tint: rarity.accent(theme)) }

            if let subtitle {
                Text(subtitle)
                    .font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
            }
            if let bodyText {
                Text(bodyText)
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
            }

            HStack { Spacer(); BotanicalFlourish() }
        }
        .padding(theme.metrics.space4)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.radiusLarge, style: .continuous)
                .strokeBorder((rarity?.accent(theme) ?? theme.colors.divider),
                              lineWidth: rarity == nil ? 1 : 2)
        )
        .shadow(color: .black.opacity(theme.metrics.shadowOpacity),
                radius: theme.metrics.shadowRadius, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Compact grid tile for pokédex collections (locked tiles grey out, §9 greying).
struct CollectibleTile<Illustration: View>: View {
    @Environment(\.theme) private var theme
    let name: String
    var rarity: RarityTier = .common
    var collected = true
    @ViewBuilder var illustration: () -> Illustration

    var body: some View {
        VStack(spacing: theme.metrics.space2) {
            illustration()
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                .grayscale(collected ? 0 : 1)
                .opacity(collected ? 1 : 0.45)
            Text(name)
                .font(theme.typography.caption(weight: .medium))
                .foregroundStyle(collected ? theme.colors.textPrimary : theme.colors.textSecondary)
                .lineLimit(1)
        }
        .padding(theme.metrics.space2)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous)
                .strokeBorder(collected ? rarity.accent(theme).opacity(0.6) : theme.colors.divider, lineWidth: 1)
        )
        .accessibilityLabel("\(name), \(rarity.label), \(collected ? "collected" : "not yet collected")")
    }
}
