//
//  GuildWorldMap.swift
//  MyGutGarden, Module D — the interactive garden WORLD (owner, 2026-07-09:
//  "an interactive map/world where I can move around and see locked/unlocked
//  areas… Fortnite / Clash of Clans style").
//
//  A pannable, pinch-to-zoom canvas. Each district is a REGION placed along a
//  winding trail that climbs from the foundation (World 1) upward; unlocked
//  regions reveal their guild pins with live bloom rings, locked ones sit under
//  fog with a "how to open" hint. Tapping a guild pin opens its field-guide card.
//  Token-drawn (no art required); a hand-painted map can drop in later behind
//  `GardenMapArt` the same way OnboardingHero swaps the onboarding illustration.
//

import SwiftUI

struct GuildWorldMapView: View {
    @Environment(\.theme) private var theme

    let districts: [GuildDistrictDisplay]
    let gardenerName: String
    var onSelect: (Int, GuildDisplay) -> Void

    // Zoom state (pinch); pan is the ScrollView's own job.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    private let canvasWidth: CGFloat = 900
    private var ordered: [GuildDistrictDisplay] { districts.sorted { $0.order < $1.order } }
    private var canvasHeight: CGFloat { CGFloat(max(ordered.count, 1)) * 300 + 240 }

    var body: some View {
        let liveZoom = min(1.6, max(0.55, zoom * pinch))
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            canvas
                .frame(width: canvasWidth, height: canvasHeight)
                .scaleEffect(liveZoom, anchor: .topLeading)
                .frame(width: canvasWidth * liveZoom, height: canvasHeight * liveZoom,
                       alignment: .topLeading)
                .gesture(
                    MagnificationGesture()
                        .updating($pinch) { value, state, _ in state = value }
                        .onEnded { value in zoom = min(1.6, max(0.55, zoom * value)) }
                )
        }
        .background(mapBackground)
    }

    // MARK: The canvas

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            trailPath
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, district in
                GuildMapRegion(district: district,
                               isNextToOpen: isNextToOpen(index),
                               onSelect: { onSelect(district.order, $0) })
                    .frame(width: regionWidth)
                    .position(center(for: index))
            }
            gardenerFlag
        }
    }

    /// The winding trail connecting district regions (drawn UNDER the regions).
    private var trailPath: some View {
        Path { p in
            let pts = ordered.indices.map { center(for: $0) }
            guard let first = pts.first else { return }
            p.move(to: first)
            for i in 1..<pts.count {
                let a = pts[i - 1], b = pts[i]
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                p.addQuadCurve(to: b, control: CGPoint(x: a.x, y: mid.y))
            }
        }
        .stroke(theme.colors.secondary.opacity(0.35),
                style: .init(lineWidth: 8, lineCap: .round, dash: [2, 20]))
        .accessibilityHidden(true)
    }

    private var gardenerFlag: some View {
        VStack(spacing: 4) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.colors.primary)
            Text("\(gardenerName)'s garden")
                .font(theme.typography.caption(weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.horizontal, theme.metrics.space2)
                .padding(.vertical, 4)
                .background(theme.colors.surface.opacity(0.9), in: Capsule())
        }
        .position(x: canvasWidth / 2, y: 70)
        .accessibilityLabel("\(gardenerName)'s garden")
    }

    // MARK: Layout math (serpentine climb)

    private let regionWidth: CGFloat = 300

    private func center(for index: Int) -> CGPoint {
        // Climb from the bottom (foundation) to the top (endgame): the LAST
        // district sits highest, matching the "ascend a trail" mental model.
        let count = ordered.count
        let fromTop = count - 1 - index
        let y = 170 + CGFloat(fromTop) * 300
        let x = canvasWidth * (index.isMultiple(of: 2) ? 0.36 : 0.64)
        return CGPoint(x: x, y: y)
    }

    /// The first still-locked region gets a subtle "you're close" ring.
    private func isNextToOpen(_ index: Int) -> Bool {
        guard !ordered[index].isUnlocked else { return false }
        return ordered.prefix(index).allSatisfy(\.isUnlocked)
    }

    private var mapBackground: some View {
        LinearGradient(colors: [theme.colors.secondary.opacity(0.10), theme.colors.background],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

// MARK: - One district region on the map

struct GuildMapRegion: View {
    @Environment(\.theme) private var theme
    let district: GuildDistrictDisplay
    var isNextToOpen: Bool = false
    var onSelect: (GuildDisplay) -> Void

    private let pins = [GridItem(.adaptive(minimum: 78), spacing: 10)]

    var body: some View {
        VStack(spacing: theme.metrics.space2) {
            regionLabel
            if district.isUnlocked {
                LazyVGrid(columns: pins, spacing: theme.metrics.space2) {
                    ForEach(district.guilds) { guild in
                        GuildMapPin(guild: guild, locked: false) { onSelect(guild) }
                    }
                }
            } else {
                lockedBody
            }
        }
        .padding(theme.metrics.space4)
        .background(regionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isNextToOpen ? 2.5 : 1.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }

    private var regionLabel: some View {
        HStack(spacing: theme.metrics.space2) {
            CollectibleNumberBadge(number: district.order)
            VStack(alignment: .leading, spacing: 0) {
                Text("World \(district.order)")
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.secondary)
                Text(district.isUnlocked ? district.name : "??? ")
                    .font(theme.typography.title(19))
                    .foregroundStyle(district.isUnlocked ? theme.colors.primary : theme.colors.textSecondary)
            }
            Spacer()
            if district.isUnlocked, district.bloomingCount > 0 {
                Label("\(district.bloomingCount)", systemImage: "sparkles")
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
            } else if !district.isUnlocked {
                Image(systemName: "lock.fill").foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private var lockedBody: some View {
        Text(GuildUnlockHint.text(forDistrictOrder: district.order))
            .font(theme.typography.caption())
            .foregroundStyle(theme.colors.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, theme.metrics.space1)
            .accessibilityLabel("Locked. " + GuildUnlockHint.text(forDistrictOrder: district.order))
    }

    private var borderColor: Color {
        if isNextToOpen { return theme.colors.accent }
        return district.isUnlocked ? theme.colors.secondary.opacity(0.5) : theme.colors.divider
    }

    private var regionBackground: some View {
        Group {
            if district.isUnlocked {
                LinearGradient(colors: [theme.colors.surface, theme.colors.secondary.opacity(0.14)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                theme.colors.divider.opacity(0.5) // fog
            }
        }
    }
}
