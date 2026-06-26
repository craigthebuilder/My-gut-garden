//
//  GuildBloomCelebrationView.swift
//  MyGutGarden — THE signature moment (DESIGN.md §1, §3): a guild's nourishment
//  crossing into Blooming. An orchestrated bloom — petals unfurl from the guild's
//  mascot in a warm burst. This is where Module D spends its boldness.
//
//  Thrive-only juice. Respects reduced motion (DESIGN.md §3/§5): when reduced,
//  it presents the fully-bloomed state instantly with no burst. Fence 2: a
//  claim_risk guild still shows the EmergingScienceTag even mid-celebration.
//
//  The coordinator detects the crossing (GuildFeedingOutcome.crossedIntoBlooming)
//  and emits `celebrate(.guildBloom)`; the shell can present this view for it.
//

import SwiftUI

struct GuildBloomCelebrationView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let guildDisplayName: String
    var claimRisk: Bool = false
    var mascotSystemImage: String = "leaf.fill"
    var onDismiss: () -> Void

    @State private var bloomed = false

    private let petalCount = 12
    private let petalRadius: CGFloat = 86

    var body: some View {
        ZStack {
            theme.colors.textPrimary.opacity(0.45).ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: theme.metrics.space5) {
                bloom
                    .frame(width: 240, height: 240)

                VStack(spacing: theme.metrics.space2) {
                    Text("\(guildDisplayName)")
                        .font(theme.typography.display(30))
                        .foregroundStyle(theme.colors.primary)
                        .multilineTextAlignment(.center)
                    Text("is blooming")
                        .font(theme.typography.title(20))
                        .foregroundStyle(theme.colors.textSecondary)
                    if claimRisk { EmergingScienceTag() } // Fence 2 — even mid-celebration
                    Text("Sustained feeding paid off. Keep the rhythm going.")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, theme.metrics.space1)
                }

                PrimaryButton(title: "Lovely", action: onDismiss).fixedSize()
            }
            .padding(theme.metrics.space6)
            .background(theme.colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusLarge, style: .continuous))
            .padding(theme.metrics.space5)
        }
        .onAppear {
            if reduceMotion { bloomed = true }
            else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.62)) { bloomed = true }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("\(guildDisplayName) is blooming. Sustained feeding paid off."
                            + (claimRisk ? " Emerging science, not an established claim." : ""))
    }

    // The petal burst: leaves unfurl from the center mascot.
    private var bloom: some View {
        ZStack {
            // Soft halo
            Circle()
                .fill(theme.colors.accent.opacity(0.16))
                .scaleEffect(bloomed ? 1 : 0.2)

            // Petals
            ForEach(0..<petalCount, id: \.self) { i in
                Image(systemName: "leaf.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(petalTint(i))
                    .offset(y: -petalRadius)
                    .rotationEffect(.degrees(Double(i) / Double(petalCount) * 360))
                    .scaleEffect(bloomed ? 1 : 0.05)
                    .opacity(bloomed ? 1 : 0)
                    .animation(reduceMotion ? nil
                               : .spring(response: 0.7, dampingFraction: 0.6)
                                   .delay(Double(i) * 0.03),
                               value: bloomed)
            }
            .rotationEffect(.degrees(bloomed ? 0 : -40))

            // Center mascot
            ZStack {
                Circle().fill(theme.colors.primary.opacity(0.18))
                Image(systemName: mascotSystemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(theme.colors.primary)
            }
            .frame(width: 96, height: 96)
            .scaleEffect(bloomed ? 1 : 0.5)
        }
        .accessibilityHidden(true)
    }

    private func petalTint(_ i: Int) -> Color {
        // Alternate primary/secondary/accent for a warm, alive ring.
        switch i % 3 {
        case 0: theme.colors.primary
        case 1: theme.colors.secondary
        default: theme.colors.accent
        }
    }
}

#Preview("Bloom — standard") {
    GuildBloomCelebrationView(guildDisplayName: "The Anti-inflammatory Arsenal",
                              claimRisk: false) {}
        .themed(for: .thrive)
}

#Preview("Bloom — claim-risk (Fence 2 tag)") {
    GuildBloomCelebrationView(guildDisplayName: "The Mood Regulators",
                              claimRisk: true) {}
        .themed(for: .thrive)
}
