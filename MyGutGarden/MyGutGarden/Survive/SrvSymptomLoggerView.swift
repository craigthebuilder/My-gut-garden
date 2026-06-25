//
//  SrvSymptomLoggerView.swift
//  MyGutGarden — Module E. The ~20-second evening symptom check-in
//  (SPEC §11b, §12). Calm, low-stimulation, fast: most nights are a couple of
//  taps. Writes `symptom_logs` via SrvStore.
//
//  Captures: Bristol 1–7 (tap a picture) · bloating/gas/pain/urgency quick
//  severities · mood + brain-fog · gas-odor (sulfur/sour/odorless — the cheap
//  discriminator) · timing · food correlation · one-tap confounder context.
//

import SwiftUI

struct SrvSymptomLoggerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let store: SrvStore
    /// In "light" tracking (off-ramp), only the essentials show (Fence 5).
    var lite: Bool = false

    @State private var draft = SrvSymptomDraft()
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space5) {
                    intro
                    bristolSection
                    severitySection
                    odorSection
                    if !lite { wellbeingSection }
                    if !lite { timingSection }
                    confounderSection
                    if !lite { notesSection }
                    saveButton
                }
                .padding(theme.metrics.space4)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Tonight's check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(theme.colors.primary)
                }
            }
        }
    }

    private var intro: some View {
        Text("A quick read on today. Skip anything that doesn't apply — empty is fine.")
            .font(theme.typography.body())
            .foregroundStyle(theme.colors.textSecondary)
    }

    // MARK: Bristol

    private var bristolSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "Today's form")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.metrics.space2), count: 4),
                          spacing: theme.metrics.space2) {
                    ForEach(SrvBristolType.allCases) { type in
                        bristolTile(type)
                    }
                }
            }
        }
    }

    private func bristolTile(_ type: SrvBristolType) -> some View {
        let selected = draft.bristol == type
        return Button {
            draft.bristol = selected ? nil : type
        } label: {
            VStack(spacing: theme.metrics.space1) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 22))
                Text(type.title)
                    .font(theme.typography.caption())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.metrics.space3)
            .foregroundStyle(selected ? theme.colors.surface : theme.colors.textPrimary)
            .background(selected ? theme.colors.primary : theme.colors.background)
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
        }
        .accessibilityLabel("Type \(type.rawValue), \(type.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Severities

    private var severitySection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                SectionHeader(title: "How it felt")
                SrvSeverityPicker(title: "Bloating", value: $draft.bloating)
                SrvSeverityPicker(title: "Gas", value: $draft.gas)
                SrvSeverityPicker(title: "Pain", value: $draft.pain)
                SrvSeverityPicker(title: "Urgency", value: $draft.urgency)
            }
        }
    }

    // MARK: Odor

    private var odorSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "Gas, if any")
                Text("The smell is a surprisingly useful clue.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                HStack(spacing: theme.metrics.space2) {
                    ForEach(SrvGasOdor.allCases) { odor in
                        SrvChoiceChip(
                            label: odor.label,
                            systemImage: odor.systemImage,
                            isOn: draft.gasOdor == odor
                        ) {
                            draft.gasOdor = draft.gasOdor == odor ? nil : odor
                        }
                    }
                }
            }
        }
    }

    // MARK: Wellbeing (mood + brain-fog)

    private var wellbeingSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                SectionHeader(title: "Mind")
                SrvScalePicker(title: "Mood", value: $draft.mood,
                               lowLabel: "Low", highLabel: "Bright")
                SrvScalePicker(title: "Brain fog", value: $draft.brainFog,
                               lowLabel: "Clear", highLabel: "Foggy")
            }
        }
    }

    // MARK: Timing + correlation

    private var timingSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "When + what")
                FlowChips(SrvMealTiming.allCases.map { ($0.id, $0.label) },
                          selected: draft.timing?.id) { id in
                    let picked = SrvMealTiming(rawValue: id)
                    draft.timing = draft.timing == picked ? nil : picked
                }
                TextField("Anything stand out you ate? (optional)", text: $draft.foodCorrelation)
                    .textFieldStyle(.roundedBorder)
                    .font(theme.typography.body())
            }
        }
    }

    // MARK: Confounders

    private var confounderSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "Anything else going on?")
                Text("These help us not blame food for an off day — they pause your streak instead of breaking it.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.metrics.space2), count: 2),
                          spacing: theme.metrics.space2) {
                    ForEach(SrvConfounder.allCases) { c in
                        SrvChoiceChip(
                            label: c.label,
                            systemImage: c.systemImage,
                            isOn: draft.confounders.contains(c)
                        ) {
                            if draft.confounders.contains(c) { draft.confounders.remove(c) }
                            else { draft.confounders.insert(c) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                SectionHeader(title: "Notes")
                TextField("Anything you want to remember (optional)", text: $draft.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .font(theme.typography.body())
            }
        }
    }

    // MARK: Save

    private var saveButton: some View {
        VStack(spacing: theme.metrics.space2) {
            PrimaryButton(title: isSaving ? "Saving…" : "Save check-in", systemImage: "checkmark") {
                guard !isSaving else { return }
                isSaving = true
                Task {
                    let ok = await store.saveLog(draft)
                    isSaving = false
                    if ok { dismiss() }
                }
            }
            .disabled(isSaving)

            // Live, gentle preview of how today lands on the streak.
            Text(outcomePreview)
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var outcomePreview: String {
        switch SrvStreakEngine.outcome(for: draft.daySymptoms) {
        case .feltGood: "Today reads as a good day — it'll add to your streak."
        case .confounded: "With that context, today pauses your streak rather than breaking it."
        case .hadSymptoms: "Today reads as a rough one — that's useful signal, and tomorrow's a fresh start."
        }
    }
}

// MARK: - Reusable inputs

/// A calm 4-step severity selector (None / Mild / Moderate / Strong).
struct SrvSeverityPicker: View {
    @Environment(\.theme) private var theme
    let title: String
    @Binding var value: SrvSeverity

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text(title)
                .font(theme.typography.body(weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
            HStack(spacing: theme.metrics.space2) {
                ForEach(SrvSeverity.allCases) { level in
                    let selected = value == level
                    Button { value = level } label: {
                        Text(level.label)
                            .font(theme.typography.caption(weight: selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, theme.metrics.space2)
                            .foregroundStyle(selected ? theme.colors.surface : theme.colors.textSecondary)
                            .background(selected ? theme.colors.primary : theme.colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                    }
                    .accessibilityLabel("\(title) \(level.label)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

/// A 1–5 scale (mood, brain-fog) with anchored end labels.
struct SrvScalePicker: View {
    @Environment(\.theme) private var theme
    let title: String
    @Binding var value: Int?
    let lowLabel: String
    let highLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            HStack {
                Text(title)
                    .font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Text("\(lowLabel) → \(highLabel)")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
            HStack(spacing: theme.metrics.space2) {
                ForEach(1...5, id: \.self) { n in
                    let selected = value == n
                    Button { value = selected ? nil : n } label: {
                        Text("\(n)")
                            .font(theme.typography.data(17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, theme.metrics.space2)
                            .foregroundStyle(selected ? theme.colors.surface : theme.colors.textSecondary)
                            .background(selected ? theme.colors.primary : theme.colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                    }
                    .accessibilityLabel("\(title) \(n) of 5")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

/// A pill choice chip (odor, confounders).
struct SrvChoiceChip: View {
    @Environment(\.theme) private var theme
    let label: String
    var systemImage: String? = nil
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.metrics.space1) {
                if let systemImage { Image(systemName: systemImage) }
                Text(label).font(theme.typography.caption(weight: isOn ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.metrics.space2)
            .padding(.horizontal, theme.metrics.space2)
            .foregroundStyle(isOn ? theme.colors.surface : theme.colors.textSecondary)
            .background(isOn ? theme.colors.primary : theme.colors.background)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(theme.colors.divider, lineWidth: isOn ? 0 : 1))
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A simple wrapping row of single-select chips.
struct FlowChips: View {
    @Environment(\.theme) private var theme
    let items: [(id: String, label: String)]
    let selected: String?
    let onTap: (String) -> Void

    init(_ items: [(String, String)], selected: String?, onTap: @escaping (String) -> Void) {
        self.items = items.map { (id: $0.0, label: $0.1) }
        self.selected = selected
        self.onTap = onTap
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.metrics.space2), count: 2),
                  spacing: theme.metrics.space2) {
            ForEach(items, id: \.id) { item in
                SrvChoiceChip(label: item.label, isOn: selected == item.id) { onTap(item.id) }
            }
        }
    }
}
