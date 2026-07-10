//
//  OnbStoryView.swift
//  MyGutGarden — the 3-frame "so-what" story (owner, 2026-07-09).
//
//  Plays ONCE, after onboarding and before the setup tour. It gives the app its
//  reason to exist in three swipes: why a variety of plants matters → the honest
//  catch (fiber load, diversity, sensitivities) → meet <gardener>, who navigates
//  it for you. The setup tour then operationalizes THIS arc without repeating it.
//
//  ── OWNER-EDITABLE COPY ───────────────────────────────────────────────────
//  All copy lives in `OnbStoryCopy` below. Claim posture (owner decision,
//  2026-07-09): "accurate & shippable" — facts corrected (microbes ≈ human cells,
//  NOT 10:1; longevity hotspots framed as association), health language hedged
//  ("linked to", "research associates"). 🔒 FENCE 4: light RD read before launch,
//  but written to stand as unqualified wellness copy.
//

import SwiftUI

struct OnbStoryView: View {
    @Environment(\.theme) private var theme
    let gardenerName: String
    let onFinish: () -> Void

    @State private var page = 0

    private var frames: [OnbStoryCopy.Frame] { OnbStoryCopy.frames(gardener: gardenerName) }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(frames.enumerated()), id: \.offset) { i, frame in
                    OnbStoryFrame(frame: frame).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            controls
        }
        .background(theme.colors.background.ignoresSafeArea())
    }

    private var controls: some View {
        VStack(spacing: theme.metrics.space4) {
            HStack(spacing: theme.metrics.space2) {
                ForEach(0..<frames.count, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? theme.colors.primary : theme.colors.primary.opacity(0.2))
                        .frame(width: i == page ? 22 : 7, height: 7)
                        .animation(.easeInOut, value: page)
                }
            }
            .accessibilityHidden(true)

            PrimaryButton(title: page == frames.count - 1 ? "Let's grow" : "Next",
                          systemImage: page == frames.count - 1 ? "leaf.fill" : "arrow.right") {
                if page < frames.count - 1 { page += 1 } else { onFinish() }
            }

            if page < frames.count - 1 {
                Button("Skip intro") { onFinish() }
                    .font(theme.typography.caption(weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .padding(theme.metrics.space5)
    }
}

// MARK: - One frame

private struct OnbStoryFrame: View {
    @Environment(\.theme) private var theme
    let frame: OnbStoryCopy.Frame

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                Spacer(minLength: theme.metrics.space6)
                Image(systemName: frame.symbol)
                    .font(.system(size: 60))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.colors.primary)
                    .accessibilityHidden(true)
                Text(frame.eyebrow.uppercased())
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.secondary)
                Text(frame.title)
                    .font(theme.typography.display(30))
                    .foregroundStyle(theme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(frame.body)
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.metrics.space5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(frame.title). \(frame.body)")
    }
}

// MARK: - Copy (owner-editable; accurate & wellness-safe — Fence 4 light RD read)

enum OnbStoryCopy {
    struct Frame {
        let symbol: String
        let eyebrow: String
        let title: String
        let body: String
    }

    static func frames(gardener: String) -> [Frame] {
        [
            Frame(
                symbol: "globe.americas.fill",
                eyebrow: "Why plants",
                title: "You're feeding a hidden world",
                body: """
                Most of what makes plants good for you is never absorbed — it travels to your gut, \
                home to trillions of microbes (roughly as many cells as the rest of you). Feed them a \
                wide range of plants and they make compounds, like short-chain fatty acids, that research \
                links to lower inflammation and healthier aging. Different plants feed different microbes, \
                so variety is the whole game — a thread running through the world's longevity hotspots, \
                from Okinawa to Sardinia.
                """
            ),
            Frame(
                symbol: "exclamationmark.bubble.fill",
                eyebrow: "The catch",
                title: "Not so fast, though",
                body: """
                Here's the honest part. Pile on all that fiber too quickly and your gut pushes back — gas, \
                bloating, low energy — the opposite of the goal. Not every plant feeds your microbes, and a \
                few non-plant foods (like yogurt) do. Your gut is its own ecosystem: you might not yet have \
                the microbes for a certain food, which can mean discomfort until they catch up. And some \
                foods you're simply sensitive or allergic to. It's a lot to navigate alone.
                """
            ),
            Frame(
                symbol: "leaf.circle.fill",
                eyebrow: "How we help",
                title: "Meet \(gardener), your gut gardener",
                body: """
                That's where \(gardener) comes in. Snap your meals, note how you feel, and \(gardener) \
                quietly handles the complexity — nudging your fiber up only as fast as your gut is happy \
                with, gently flagging a food that seems to disagree, and celebrating every new plant you \
                grow. You eat freely; \(gardener) keeps it smart and comfortable. Let's grow.
                """
            ),
        ]
    }
}

#if DEBUG
#Preview("Intro story") {
    OnbStoryView(gardenerName: "Sprout", onFinish: {}).themed()
}
#endif
