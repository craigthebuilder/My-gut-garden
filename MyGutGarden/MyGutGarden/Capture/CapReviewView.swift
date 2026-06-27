//
//  CapReviewView.swift
//  MyGutGarden, Module B review & confirm screen (SPEC §4 step 4/6, §9, §11).
//
//  The honesty layer of the snap flow: the user confirms what the camera saw,
//  answers the always-ask hidden-ingredient prompts, and corrects anything the
//  database couldn't match, before a single row is logged. Medical-allergy
//  alerts fire LOUD here regardless of mode (§9). Portion stays a coarse tier,
//  never a measured gram (rule #3).
//

import SwiftUI

struct CapReviewScreen: View {
    @Environment(\.theme) private var theme
    let model: CapCaptureModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space5) {
                title
                allergyBanner
                recognizedItems
                hiddenPrompts
                manualConfirm
                confirmBar
                if let error = model.errorText { errorNote(error) }
            }
            .padding(theme.metrics.space5)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text("Does this look right?")
                .font(theme.typography.display(28))
                .foregroundStyle(theme.colors.textPrimary)
            Text("Confirm what's here, then log it. Portions are rough tiers, not measurements.")
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Allergy alerts, LOUD across both modes (§9)

    @ViewBuilder
    private var allergyBanner: some View {
        if !model.allergyAlerts.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                ForEach(model.allergyAlerts, id: \.foodName) { alert in
                    HStack(spacing: theme.metrics.space2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Heads up, this looks like it contains \(alert.foodName), one of your flagged allergies.")
                            .font(theme.typography.body(weight: .semibold))
                    }
                    .foregroundStyle(theme.colors.error)
                }
            }
            .padding(theme.metrics.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.error.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Recognized items

    @ViewBuilder
    private var recognizedItems: some View {
        let items = surfacedItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "In this meal", trailing: "\(items.count)")
                ForEach(items, id: \.attributes?.foodId) { item in
                    if let attrs = item.attributes {
                        CapRecognizedRow(name: attrs.canonicalName,
                                         portion: item.vision.portionTier,
                                         safety: model.mode == .survive ? attrs.fodmap?.safety : nil)
                    }
                }
            }
        }
    }

    /// Matched + surfaced items (preference_intolerance matches are quietly
    /// omitted, §9). Mirrors the persisted vision set.
    private var surfacedItems: [ResolvedItem] {
        (model.response?.items ?? []).filter { $0.silentlyOmitted != true && $0.attributes != nil }
    }

    // MARK: Hidden-ingredient prompts, always-ask yes/no (§4 step 6, §11)

    @ViewBuilder
    private var hiddenPrompts: some View {
        if !model.hiddenAnswers.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "Worth a check")
                ForEach(model.hiddenAnswers) { answer in
                    CapHiddenPromptRow(answer: answer) { wasPresent in
                        model.setHiddenAnswer(answer, wasPresent: wasPresent)
                    }
                }
            }
        }
    }

    // MARK: Manual confirm, unmatched guesses (§4 step 4)

    @ViewBuilder
    private var manualConfirm: some View {
        if !model.unmatchedItems.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "Help name these")
                Text("We couldn't place these. Search for the real food, or leave it if you're not sure.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                ForEach(model.unmatchedItems) { item in
                    CapManualConfirmRow(item: item, model: model)
                }
            }
        }
    }

    // MARK: Confirm

    private var confirmBar: some View {
        VStack(spacing: theme.metrics.space2) {
            PrimaryButton(title: model.isSaving ? "Logging…" : "Log meal", systemImage: "checkmark.circle.fill") {
                Task { await model.confirm() }
            }
            .disabled(!model.canConfirm || model.isSaving)
            .opacity(model.canConfirm && !model.isSaving ? 1 : 0.5)

            if !model.canConfirm {
                Text("Answer the checks above to log this meal.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private func errorNote(_ text: String) -> some View {
        Text(text)
            .font(theme.typography.caption())
            .foregroundStyle(theme.colors.error)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rows

private struct CapRecognizedRow: View {
    @Environment(\.theme) private var theme
    let name: String
    let portion: PortionTier
    var safety: FodmapSafety?

    var body: some View {
        Card {
            HStack(spacing: theme.metrics.space3) {
                VStack(alignment: .leading, spacing: theme.metrics.space1) {
                    Text(name)
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Badge(text: CapPortion.label(portion))
                }
                Spacer()
                if let safety { SafetyChip(safety: safety) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(CapPortion.label(portion))")
    }
}

private struct CapHiddenPromptRow: View {
    @Environment(\.theme) private var theme
    let answer: CapHiddenIngredientAnswer
    var onAnswer: (Bool) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                Text(answer.prompt.prompt)
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textPrimary)
                HStack(spacing: theme.metrics.space3) {
                    choice("Yes", value: true, selected: answer.wasPresent == true)
                    choice("No", value: false, selected: answer.wasPresent == false)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func choice(_ title: String, value: Bool, selected: Bool) -> some View {
        Button { onAnswer(value) } label: {
            Text(title)
                .font(theme.typography.body(weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, theme.metrics.space2)
        }
        .foregroundStyle(selected ? theme.colors.surface : theme.colors.primary)
        .background(selected ? theme.colors.primary : theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous)
                .strokeBorder(theme.colors.primary.opacity(0.4), lineWidth: 1)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(title), \(answer.prompt.foodName)")
    }
}

private struct CapManualConfirmRow: View {
    @Environment(\.theme) private var theme
    let item: CapUnmatchedItem
    let model: CapCaptureModel

    @State private var term = ""
    @State private var results: [CapFoodSearchResult] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                HStack {
                    Text(item.visionName)
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    if let food = item.resolvedFood {
                        Badge(text: food.canonicalName, tint: theme.colors.primary)
                    }
                }

                if item.resolvedFood == nil {
                    TextField("Search foods", text: $term)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onChange(of: term) { _, newValue in search(newValue) }

                    ForEach(results) { result in
                        Button { resolve(result) } label: {
                            HStack {
                                Text(result.canonicalName)
                                    .font(theme.typography.body())
                                    .foregroundStyle(theme.colors.textPrimary)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(theme.colors.primary)
                            }
                            .padding(.vertical, theme.metrics.space1)
                        }
                        .accessibilityLabel("Add \(result.canonicalName)")
                    }
                } else {
                    SecondaryButton(title: "Change") { model.clearUnmatched(item) }
                }
            }
        }
    }

    private func search(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = []; return }
        searchTask = Task {
            let found = await model.searchFoods(trimmed)
            if !Task.isCancelled { results = found }
        }
    }

    private func resolve(_ food: CapFoodSearchResult) {
        model.resolveUnmatched(item, with: food)
        results = []
        term = ""
    }
}

// MARK: - Portion labels (coarse tiers only, rule #3)

enum CapPortion {
    static func label(_ tier: PortionTier) -> String {
        switch tier {
        case .trace: "Trace"
        case .serving: "A serving"
        case .lots: "Lots"
        }
    }
}
