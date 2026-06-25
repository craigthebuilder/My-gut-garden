//
//  SrvRootView.swift
//  MyGutGarden — Module E PUBLIC ENTRY. The calm Survive home (SPEC §11b).
//
//  Survive's register is steady and reassuring (DESIGN.md §1, §3): cool, quiet,
//  lots of whitespace, gentle motion, no celebratory bursts. This screen brings
//  the surface together — the symptom-free streak (framed "days feeling good",
//  never "days restricted" — rule #7), the evening logger, the read-only
//  pattern insight, reintro progress, the food pokédexes, and the blameless
//  off-ramp (Fence 5).
//
//  The AppShell injects the Survive theme by mode; this view also applies
//  `.themed(for: .survive)` so it renders correctly in isolation and previews.
//

import SwiftUI

struct SrvRootView: View {
    @State private var store: SrvStore
    @State private var showLogger = false
    @State private var showOffRamp = false

    init(appState: AppState) {
        _store = State(initialValue: SrvStore(appState: appState))
    }

    /// Preview/testing seam: inject a pre-populated store directly.
    init(store: SrvStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        NavigationStack {
            SrvHomeContent(store: store, showLogger: $showLogger, showOffRamp: $showOffRamp)
                .navigationTitle("My Gut Garden")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showOffRamp = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel("Adjust or pause tracking")
                    }
                }
        }
        .themed(for: .survive)
        .task { await store.load() }
        .sheet(isPresented: $showLogger) {
            SrvSymptomLoggerView(store: store, lite: store.trackingPreference == .lite)
                .themed(for: .survive)
        }
        .sheet(isPresented: $showOffRamp) {
            SrvOffRampView(store: store)
                .themed(for: .survive)
        }
    }
}

private struct SrvHomeContent: View {
    @Environment(\.theme) private var theme
    @Bindable var store: SrvStore
    @Binding var showLogger: Bool
    @Binding var showOffRamp: Bool

    private var loggedDays: Int { SrvStore.dailySymptoms(from: store.logs).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                greeting
                streakCard
                logCta
                if store.trackingPreference == .paused { pausedNote }
                activeChallengeCard
                patternSection
                navCards
                SrvRedFlagCard()
                if store.usingSampleData { sampleNote }
            }
            .padding(theme.metrics.space4)
        }
        .background(theme.colors.background.ignoresSafeArea())
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space1) {
            Text("How are you feeling?")
                .font(theme.typography.display(28))
                .foregroundStyle(theme.colors.textPrimary)
            Text("Symptoms in, insights out. We'll keep it calm.")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    // MARK: Streak (relief-framed — never restriction)

    private var streakCard: some View {
        Card {
            HStack(spacing: theme.metrics.space4) {
                VStack(alignment: .leading, spacing: theme.metrics.space1) {
                    Text(streakHeadline)
                        .font(theme.typography.display(30))
                        .foregroundStyle(theme.colors.primary)
                    Text(streakSubtitle)
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Spacer()
                Image(systemName: "sun.max")
                    .font(.system(size: 34))
                    .foregroundStyle(theme.colors.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(streakHeadline + ". " + streakSubtitle)
    }

    private var streakHeadline: String {
        store.streak.current == 0 ? "Let's find your good days"
            : "\(store.streak.current) \(store.streak.current == 1 ? "day" : "days") feeling good"
    }

    private var streakSubtitle: String {
        if store.streak.current == 0 {
            return "Log an evening or two and your streak begins. Off days with context just pause it."
        }
        if store.streak.longest > store.streak.current {
            return "Your best stretch so far is \(store.streak.longest) days. Context days pause the count, never break it."
        }
        return "This is your best stretch yet. Keep going gently."
    }

    // MARK: Log CTA

    private var logCta: some View {
        PrimaryButton(title: "Log tonight's check-in", systemImage: "moon.stars") {
            showLogger = true
        }
    }

    private var pausedNote: some View {
        Card {
            HStack(spacing: theme.metrics.space2) {
                Image(systemName: "pause.circle").foregroundStyle(theme.colors.secondary)
                Text("Tracking is paused. Everything's saved — log whenever you're ready.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    // MARK: Active challenge

    @ViewBuilder private var activeChallengeCard: some View {
        if let active = store.challenges.first(where: { $0.status == .testing }) {
            NavigationLink {
                SrvReintroView(store: store)
            } label: {
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space2) {
                        Label("Testing \(active.group.shortName)", systemImage: "target")
                            .font(theme.typography.body(weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                        ProgressView(value: SrvReintroEngine.progress(active, now: Date()))
                            .tint(theme.colors.primary)
                        Text("We'll flag this in your meals so it's easy to log.")
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Pattern

    @ViewBuilder private var patternSection: some View {
        if let card = store.patternCards.first {
            SrvPatternCard(presentation: card)
        } else {
            SrvGatheringSignalCard(loggedDays: loggedDays)
        }
    }

    // MARK: Navigation cards

    private var navCards: some View {
        VStack(spacing: theme.metrics.space3) {
            NavigationLink {
                SrvReintroView(store: store)
            } label: {
                SrvNavRow(title: "Reintroductions", subtitle: reintroSubtitle, systemImage: "arrow.up.forward.circle")
            }
            .buttonStyle(.plain)

            NavigationLink {
                SrvPokedexView(store: store)
            } label: {
                SrvNavRow(title: "Your foods", subtitle: foodsSubtitle, systemImage: "square.grid.2x2")
            }
            .buttonStyle(.plain)
        }
    }

    private var reintroSubtitle: String {
        let cleared = store.clearedGroups.count
        return cleared == 0 ? "Test fiber groups back, one at a time"
            : "\(cleared) cleared so far — keep leveling up"
    }

    private var foodsSubtitle: String {
        "\(store.safeFoods.count) safe · \(store.triggerFoods.count) resting · timeline"
    }

    private var sampleNote: some View {
        Text("Showing sample data — connect an account to track your own.")
            .font(theme.typography.caption())
            .foregroundStyle(theme.colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// A tappable navigation row styled as a calm card.
struct SrvNavRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Card {
            HStack(spacing: theme.metrics.space3) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(theme.colors.primary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(subtitle)
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

// MARK: - Preview

#Preview("Survive home") {
    SrvRootView(store: SrvStore(appState: AppState(auth: AuthService())))
}
