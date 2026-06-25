//
//  SrvPokedexView.swift
//  MyGutGarden — Module E. The Survive food pokédexes (SPEC §11b, §8).
//
//  Foods, never bacteria. Four lenses:
//    • Safe — greyed-IN as cleared (the visible win of a passed reintro),
//    • Triggers — greyed-OUT, with the severity you observed,
//    • Reintro progress — tested / passed / failed / pending,
//    • Symptom-vs-food timeline — your recent evenings at a glance.
//  Greying matches §9's shared treatment; the calm Survive tone keeps it
//  blameless (a trigger is a "resting" food, not a failure).
//

import SwiftUI

struct SrvPokedexView: View {
    @Environment(\.theme) private var theme
    @Bindable var store: SrvStore
    @State private var lens: Lens = .safe

    enum Lens: String, CaseIterable, Identifiable {
        case safe = "Safe"
        case triggers = "Resting"
        case reintro = "Reintro"
        case timeline = "Timeline"
        var id: String { rawValue }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: theme.metrics.space3), count: 3)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                Picker("Lens", selection: $lens) {
                    ForEach(Lens.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch lens {
                case .safe: safeGrid
                case .triggers: triggerGrid
                case .reintro: reintroSummary
                case .timeline: timeline
                }
            }
            .padding(theme.metrics.space4)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Foods")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Safe

    private var safeGrid: some View {
        let foods = store.safeFoods
        return Group {
            if foods.isEmpty {
                SrvEmptyHint(text: "Clear a reintro group and the foods it gates show up here.")
            } else {
                LazyVGrid(columns: columns, spacing: theme.metrics.space3) {
                    ForEach(foods) { food in
                        CollectibleTile(name: food.name, rarity: .common, collected: true) {
                            IllustrationPlaceholder(systemImage: "leaf.fill", tint: theme.colors.safetyGreen)
                        }
                    }
                }
            }
        }
    }

    // MARK: Triggers (resting)

    private var triggerGrid: some View {
        let foods = store.triggerFoods
        return Group {
            if foods.isEmpty {
                SrvEmptyHint(text: "Nothing resting right now.")
            } else {
                LazyVGrid(columns: columns, spacing: theme.metrics.space3) {
                    ForEach(foods) { food in
                        VStack(spacing: theme.metrics.space1) {
                            CollectibleTile(name: food.name, rarity: .common, collected: false) {
                                IllustrationPlaceholder(systemImage: "leaf", tint: theme.colors.textSecondary)
                            }
                            if let severity = food.observedSeverity, severity != .none {
                                Text(severity.label)
                                    .font(theme.typography.caption())
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Reintro progress

    private var reintroSummary: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space3) {
            ForEach(SrvFodmapGroup.allCases) { group in
                let status = store.challenges.first { $0.group == group }?.status ?? .pending
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.displayName)
                                .font(theme.typography.body(weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                            Text("e.g. \(group.exampleFood)")
                                .font(theme.typography.caption())
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                        Spacer()
                        Label(status.label, systemImage: status.systemImage)
                            .font(theme.typography.caption(weight: .medium))
                            .foregroundStyle(status == .passed ? theme.colors.safetyGreen : theme.colors.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        let days = SrvStore.dailySymptoms(from: store.logs).reversed().map { $0 }
        return Group {
            if days.isEmpty {
                SrvEmptyHint(text: "Your evening check-ins will line up here.")
            } else {
                VStack(spacing: theme.metrics.space2) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, entry in
                        SrvTimelineRow(date: entry.date, symptoms: entry.symptoms)
                    }
                }
            }
        }
    }
}

struct SrvTimelineRow: View {
    @Environment(\.theme) private var theme
    let date: Date
    let symptoms: SrvDaySymptoms

    private var outcome: SrvDayOutcome { SrvStreakEngine.outcome(for: symptoms) }

    private var dotColor: Color {
        switch outcome {
        case .feltGood: theme.colors.safetyGreen
        case .confounded: theme.colors.safetyYellow
        case .hadSymptoms: theme.colors.safetyRed
        }
    }

    private var summary: String {
        switch outcome {
        case .feltGood: "Felt good"
        case .confounded: "Off day, with context"
        case .hadSymptoms: "\(symptoms.worstSeverity.label) symptoms"
        }
    }

    var body: some View {
        Card {
            HStack(spacing: theme.metrics.space3) {
                Circle().fill(dotColor).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(summary)
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Spacer()
                if !symptoms.confounders.isEmpty {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(theme.colors.textSecondary)
                        .accessibilityLabel("Streak paused for context")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).month().day())): \(summary)")
    }
}

struct SrvEmptyHint: View {
    @Environment(\.theme) private var theme
    let text: String
    var body: some View {
        Card {
            Text(text)
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
