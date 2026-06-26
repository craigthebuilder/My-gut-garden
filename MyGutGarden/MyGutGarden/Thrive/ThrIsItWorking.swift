//
//  ThrIsItWorking.swift
//  MyGutGarden — Module C: the "Is it working?" dashboard (SPEC §11a, §12).
//
//  The retention engine for users with no symptoms to chase: mood / energy /
//  clarity tracked against the onboarding baseline (`users.baseline_*`), plus a
//  one-tap daily mood check that writes `thrive_checkins`. Thrive keeps the
//  tracking burden to a single tap (§12) and frames everything as gain, never
//  restriction (rule #7). Includes a blameless "take a break" off-ramp (Fence 5).
//

import SwiftUI
import Observation

// MARK: - Model

@MainActor
@Observable
final class ThrCheckinModel {
    var baselineMood: Int?
    var baselineEnergy: Int?
    var baselineClarity: Int?

    /// Ascending by date for the trend charts.
    var history: [ThriveCheckinRow] = []

    // Today's working values (any subset may be set; saved together).
    var todayMood: Int?
    var todayEnergy: Int?
    var todayClarity: Int?

    var isLoaded = false
    var isSaving = false
    private var userId: String?

    func load(appState: AppState) async {
        var profile = appState.profile
        if profile == nil, let repo = appState.repository {
            profile = (try? await repo.fetchProfile()) ?? nil
        }
        baselineMood = profile?.baselineMood
        baselineEnergy = profile?.baselineEnergy
        baselineClarity = profile?.baselineClarity
        userId = profile?.id

        if let repo = appState.repository,
           let rows: [ThriveCheckinRow] = try? await repo.select("thrive_checkins", order: "log_date.asc", limit: 90) {
            history = rows
            if let today = rows.last, today.logDate == ThrDates.dateString() {
                todayMood = today.mood
                todayEnergy = today.energy
                todayClarity = today.clarity
            }
        }
        isLoaded = true
    }

    var loggedToday: Bool { todayMood != nil || todayEnergy != nil || todayClarity != nil }

    /// One-tap mood: set + persist immediately (the §12 minimal-burden path).
    func tapMood(_ value: Int, appState: AppState) async {
        todayMood = value
        await save(appState: appState)
    }

    func tapEnergy(_ value: Int, appState: AppState) async {
        todayEnergy = value
        await save(appState: appState)
    }

    func tapClarity(_ value: Int, appState: AppState) async {
        todayClarity = value
        await save(appState: appState)
    }

    /// Upsert today's row on (user_id, log_date). All three values are sent so a
    /// partial update never clobbers an earlier tap.
    private func save(appState: AppState) async {
        guard let repo = appState.repository, let userId else {
            // Offline: keep the optimistic local value so the UI still responds.
            mirrorIntoHistory()
            return
        }
        isSaving = true
        defer { isSaving = false }
        let today = ThrDates.dateString()
        try? await repo.upsert("thrive_checkins", [
            "user_id": .string(userId),
            "log_date": .string(today),
            "mood": todayMood.map(PGValue.int) ?? .null,
            "energy": todayEnergy.map(PGValue.int) ?? .null,
            "clarity": todayClarity.map(PGValue.int) ?? .null,
        ], onConflict: "user_id,log_date")
        mirrorIntoHistory()
    }

    /// Keep the in-memory trend in sync with today's taps without a refetch.
    private func mirrorIntoHistory() {
        let today = ThrDates.dateString()
        let row = ThriveCheckinRow(logDate: today, mood: todayMood, energy: todayEnergy, clarity: todayClarity)
        if let idx = history.firstIndex(where: { $0.logDate == today }) {
            history[idx] = row
        } else {
            history.append(row)
        }
    }
}

// MARK: - Dashboard

struct ThrIsItWorkingView: View {
    @Environment(\.theme) private var theme
    let appState: AppState

    @State private var model = ThrCheckinModel()
    @State private var showBreakNote = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                intro
                todayCheckCard
                if model.history.isEmpty {
                    ThrEmptyState(icon: "heart.text.square.fill",
                                  title: "Your before-and-after starts today",
                                  message: "Tap how you feel each day. Over a couple of weeks this shows whether the garden's paying off.")
                } else {
                    trendCard("Mood", metric: .mood, baseline: model.baselineMood)
                    trendCard("Energy", metric: .energy, baseline: model.baselineEnergy)
                    trendCard("Clarity", metric: .clarity, baseline: model.baselineClarity)
                }
                offRamp
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Is it working?")
        .task { await model.load(appState: appState) }
    }

    private var intro: some View {
        Text("How you feel, tracked against where you started. No pressure — one tap a day is plenty.")
            .font(theme.typography.body())
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: One-tap check

    private var todayCheckCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: model.loggedToday ? "Logged today — thanks" : "How are you today?")
                ThrScalePicker(label: "Mood", selection: model.todayMood) { value in
                    Task { await model.tapMood(value, appState: appState) }
                }
                ThrScalePicker(label: "Energy", selection: model.todayEnergy) { value in
                    Task { await model.tapEnergy(value, appState: appState) }
                }
                ThrScalePicker(label: "Clarity", selection: model.todayClarity) { value in
                    Task { await model.tapClarity(value, appState: appState) }
                }
            }
        }
    }

    // MARK: Trends

    private func trendCard(_ title: String, metric: ThrMetric, baseline: Int?) -> some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                HStack {
                    SectionHeader(title: title)
                    if let delta = deltaText(metric: metric, baseline: baseline) {
                        Badge(text: delta, tint: theme.colors.success)
                    }
                }
                ThrTrendChart(
                    values: model.history.suffix(14).map { metric.value(from: $0) },
                    baseline: baseline
                )
                if let baseline {
                    Text("Baseline at start: \(baseline)/5")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
    }

    private func deltaText(metric: ThrMetric, baseline: Int?) -> String? {
        guard let baseline else { return nil }
        let recent = model.history.suffix(7).compactMap { metric.value(from: $0) }
        guard !recent.isEmpty else { return nil }
        let avg = Double(recent.reduce(0, +)) / Double(recent.count)
        let diff = avg - Double(baseline)
        guard diff >= 0.5 else { return nil }       // gain-framed: only celebrate upticks
        return "up since you started"
    }

    // MARK: Off-ramp (Fence 5 — blameless break from tracking)

    private var offRamp: some View {
        VStack(spacing: theme.metrics.space2) {
            Button { showBreakNote.toggle() } label: {
                Text("Tracking feeling like a chore?")
                    .font(theme.typography.caption(weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                    .underline()
            }
            .buttonStyle(.plain)
            if showBreakNote {
                Text("Totally fine to take a break. Your garden and lifetime collection stay exactly as they are — come back whenever you like.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, theme.metrics.space3)
        .animation(.default, value: showBreakNote)
    }
}

// MARK: - Metric selector

enum ThrMetric {
    case mood, energy, clarity
    func value(from row: ThriveCheckinRow) -> Int? {
        switch self {
        case .mood: row.mood
        case .energy: row.energy
        case .clarity: row.clarity
        }
    }
}

// MARK: - One-tap 1…5 scale

struct ThrScalePicker: View {
    @Environment(\.theme) private var theme
    let label: String
    let selection: Int?
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            Text(label)
                .font(theme.typography.caption(weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 64, alignment: .leading)
            ForEach(1...5, id: \.self) { value in
                Button { onTap(value) } label: {
                    Text("\(value)")
                        .font(theme.typography.data(16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.metrics.space2)
                        .background(selection == value ? theme.colors.primary : theme.colors.background)
                        .foregroundStyle(selection == value ? theme.colors.surface : theme.colors.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label) \(value) of 5")
                .accessibilityAddTraits(selection == value ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Lightweight themed trend chart (no Charts dependency; token-driven)

struct ThrTrendChart: View {
    @Environment(\.theme) private var theme
    let values: [Int?]          // 1…5 (nil = no entry that day)
    let baseline: Int?

    private let scaleMax = 5.0

    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let slot = geo.size.width / CGFloat(count)
            let barWidth = max(4, slot * 0.5)
            ZStack(alignment: .bottomLeading) {
                if let baseline {
                    let y = geo.size.height * (1 - CGFloat(Double(baseline) / scaleMax))
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(theme.colors.divider, style: .init(lineWidth: 1, dash: [4, 4]))
                }
                ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                    if let value {
                        let h = geo.size.height * CGFloat(Double(value) / scaleMax)
                        let above = baseline.map { value >= $0 } ?? true
                        RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous)
                            .fill(above ? theme.colors.primary : theme.colors.secondary)
                            .frame(width: barWidth, height: max(2, h))
                            .position(x: slot * (CGFloat(idx) + 0.5), y: geo.size.height - h / 2)
                    }
                }
            }
        }
        .frame(height: 96)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let entries = values.compactMap { $0 }
        guard !entries.isEmpty else { return "No entries yet" }
        let avg = Double(entries.reduce(0, +)) / Double(entries.count)
        let base = baseline.map { ", baseline \($0)" } ?? ""
        return "Recent average \(String(format: "%.1f", avg)) out of 5\(base)"
    }
}

#if DEBUG
#Preview("Is it working?") {
    NavigationStack {
        ThrIsItWorkingView(appState: AppState(auth: AuthService()))
    }
    .themed(for: .thrive)
}
#endif
