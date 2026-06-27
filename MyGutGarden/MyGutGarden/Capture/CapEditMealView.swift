//
//  CapEditMealView.swift
//  MyGutGarden, Module B non-blocking meal editor (SPEC §4, Batch C).
//
//  The deferred half of the snap flow: after a meal auto-logs, the user can open
//  this to add / remove ingredients, change RELATIVE amounts (coarse tiers only,
//  rule #3), and answer the hidden-ingredient prompts that were skipped at
//  capture. The photo + note are read-only. Saving replaces meal_items wholesale.
//  Tokens only; no em dashes (rule #5).
//

import SwiftUI

struct CapEditMealView: View {
    @Environment(\.theme) private var theme
    @Bindable var model: CapEditMealModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, theme.metrics.space6)
                } else {
                    VStack(alignment: .leading, spacing: theme.metrics.space5) {
                        photoAndNote
                        ingredients
                        addIngredient
                        hiddenPrompts
                        if let error = model.errorText { errorNote(error) }
                    }
                    .padding(theme.metrics.space5)
                }
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSaving ? "Saving" : "Save") {
                        Task {
                            await model.save()
                            if model.didSave { onClose() }
                        }
                    }
                    .disabled(model.isSaving)
                }
            }
        }
        .task { await model.load() }
    }

    // MARK: Photo + note (read-only)

    private var photoAndNote: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                HStack(spacing: theme.metrics.space3) {
                    Image(systemName: model.photoExpired ? "photo.badge.exclamationmark" : "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.colors.textSecondary)
                    Text(model.photoExpired ? "Photo no longer available" : "Photo saved")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                if let note = model.userAnnotation, !note.isEmpty {
                    Text("Your note: \(note)")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textPrimary)
                }
            }
        }
    }

    // MARK: Ingredients (delete + change relative amount)

    @ViewBuilder
    private var ingredients: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space3) {
            SectionHeader(title: "Ingredients", trailing: "\(model.rows.count)")
            if model.rows.isEmpty {
                Text("No ingredients yet. Add one below.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
            ForEach(model.rows) { row in
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space3) {
                        HStack {
                            Text(row.name)
                                .font(theme.typography.body(weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                            Spacer()
                            Button { model.delete(row) } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(theme.colors.error)
                            }
                            .accessibilityLabel("Remove \(row.name)")
                        }
                        portionPicker(for: row)
                    }
                }
            }
        }
    }

    private func portionPicker(for row: CapEditMealModel.Row) -> some View {
        HStack(spacing: theme.metrics.space2) {
            ForEach([PortionTier.trace, .serving, .lots], id: \.self) { tier in
                let selected = row.portion == tier
                Button { model.setPortion(row, portion: tier) } label: {
                    Text(CapPortion.label(tier))
                        .font(theme.typography.caption(weight: .medium))
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
                .accessibilityLabel("\(CapPortion.label(tier)) of \(row.name)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: Add ingredient

    private var addIngredient: some View {
        CapAddIngredientRow(model: model)
    }

    // MARK: Deferred hidden-ingredient prompts (reappear here, §4)

    @ViewBuilder
    private var hiddenPrompts: some View {
        if !model.hiddenAnswers.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "Worth a check")
                Text("These often hide in dishes like yours. Add any that were there.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                ForEach(model.hiddenAnswers) { answer in
                    Card {
                        VStack(alignment: .leading, spacing: theme.metrics.space3) {
                            Text(answer.prompt.prompt)
                                .font(theme.typography.body())
                                .foregroundStyle(theme.colors.textPrimary)
                            HStack(spacing: theme.metrics.space3) {
                                hiddenChoice("Yes", value: true, answer: answer)
                                hiddenChoice("No", value: false, answer: answer)
                            }
                        }
                    }
                }
            }
        }
    }

    private func hiddenChoice(_ title: String, value: Bool, answer: CapHiddenIngredientAnswer) -> some View {
        let selected = answer.wasPresent == value
        return Button { model.setHiddenAnswer(answer, wasPresent: value) } label: {
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
        .accessibilityLabel("\(title), \(answer.prompt.foodName)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func errorNote(_ text: String) -> some View {
        Text(text)
            .font(theme.typography.caption())
            .foregroundStyle(theme.colors.error)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Add-ingredient search row

private struct CapAddIngredientRow: View {
    @Environment(\.theme) private var theme
    let model: CapEditMealModel

    @State private var term = ""
    @State private var results: [CapFoodSearchResult] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            SectionHeader(title: "Add an ingredient")
            TextField("Search foods", text: $term)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onChange(of: term) { _, newValue in search(newValue) }
            ForEach(results) { result in
                Button { add(result) } label: {
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

    private func add(_ food: CapFoodSearchResult) {
        model.addFood(food)
        results = []
        term = ""
    }
}
