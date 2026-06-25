//
//  OnbStepViews.swift
//  MyGutGarden — Module A: the per-step intake screens + small shared controls.
//
//  Composes DesignSystem primitives (Card, SectionHeader, Badge, buttons) and
//  reads ONLY Theme tokens — never hardcodes a color/font/spacing/radius.
//  Dynamic Type, VoiceOver, and reduced motion come through the shared
//  components; custom affordances add their own labels.
//

import SwiftUI

// MARK: - Shared small controls (Onb-prefixed; module-internal)

/// A consistent header for each step.
struct OnbStepScaffold<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Text(title)
                    .font(theme.typography.display(28))
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Selectable pill (goals, categories).
struct OnbChip: View {
    @Environment(\.theme) private var theme
    let label: String
    var systemImage: String? = nil
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.metrics.space2) {
                if let systemImage { Image(systemName: systemImage) }
                Text(label).font(theme.typography.body(weight: .medium))
            }
            .padding(.horizontal, theme.metrics.space4)
            .padding(.vertical, theme.metrics.space3)
            .frame(maxWidth: .infinity)
            .background(isSelected ? theme.colors.primary : theme.colors.surface)
            .foregroundStyle(isSelected ? theme.colors.surface : theme.colors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : theme.colors.divider, lineWidth: 1)
            )
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A 1–5 scale picker (baseline mood/energy/clarity). VoiceOver-adjustable.
struct OnbScalePicker: View {
    @Environment(\.theme) private var theme
    let title: String
    let lowLabel: String
    let highLabel: String
    @Binding var value: Int

    private let range = 1...5

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text(title)
                .font(theme.typography.body(weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
            HStack(spacing: theme.metrics.space2) {
                ForEach(range, id: \.self) { i in
                    Button { value = i } label: {
                        Circle()
                            .fill(i <= value ? theme.colors.primary : theme.colors.background)
                            .overlay(Circle().strokeBorder(theme.colors.divider, lineWidth: 1))
                            .frame(height: 30)
                    }
                    .accessibilityHidden(true)
                }
            }
            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .font(theme.typography.caption())
            .foregroundStyle(theme.colors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value) of 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(5, value + 1)
            case .decrement: value = max(1, value - 1)
            @unknown default: break
            }
        }
    }
}

/// A check row used by red-flags + serious-conditions (informs, never blocks).
struct OnbCheckRow: View {
    @Environment(\.theme) private var theme
    let label: String
    let isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.metrics.space3) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? theme.colors.primary : theme.colors.textSecondary)
                Text(label)
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.vertical, theme.metrics.space1)
        }
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - Step: Goals

struct OnbGoalsStep: View {
    @Environment(\.theme) private var theme
    @Bindable var vm: OnbViewModel

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        OnbStepScaffold(title: "What brings you here?",
                        subtitle: "Pick as many as you like. This shapes what we show you first.") {
            LazyVGrid(columns: columns, spacing: theme.metrics.space3) {
                ForEach(OnbGoal.allCases) { goal in
                    OnbChip(label: goal.label, systemImage: goal.systemImage,
                            isSelected: vm.goals.contains(goal)) {
                        vm.toggleGoal(goal)
                    }
                }
            }
        }
    }
}

// MARK: - Step: Body basics (SPEC §10 — never a weight-loss frame)

struct OnbBodyStep: View {
    @Environment(\.theme) private var theme
    @Bindable var vm: OnbViewModel

    var body: some View {
        OnbStepScaffold(title: "A couple of basics",
                        subtitle: "We use these once, to set a fiber goal that fits you. No weigh-ins, no calorie targets.") {
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    sliderRow(title: "Height", value: $vm.heightCm, range: 120...220, unit: "cm")
                    Divider().overlay(theme.colors.divider)
                    sliderRow(title: "Weight", value: $vm.weightKg, range: 35...200, unit: "kg")
                }
            }

            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    Text("Optional — sharpens the estimate")
                        .font(theme.typography.caption(weight: .semibold))
                        .foregroundStyle(theme.colors.textSecondary)

                    Toggle(isOn: $vm.shareAge) {
                        Text("Share my age").font(theme.typography.body())
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                    .tint(theme.colors.primary)
                    if vm.shareAge {
                        Stepper(value: $vm.ageValue, in: 12...100) {
                            Text("\(vm.ageValue) years").font(theme.typography.body())
                                .foregroundStyle(theme.colors.textPrimary)
                        }
                    }

                    Picker("Sex", selection: $vm.sex) {
                        ForEach(OnbSex.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.colors.primary)

                    Picker("Activity", selection: $vm.activity) {
                        ForEach(OnbActivityLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.colors.primary)
                }
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            HStack {
                Text(title).font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(theme.typography.data())
                    .foregroundStyle(theme.colors.primary)
            }
            Slider(value: value, in: range, step: 1)
                .tint(theme.colors.primary)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value.wrappedValue)) \(unit)")
        }
    }
}

// MARK: - Step: Baseline

struct OnbBaselineStep: View {
    @Environment(\.theme) private var theme
    @Bindable var vm: OnbViewModel

    var body: some View {
        OnbStepScaffold(title: "How are things lately?",
                        subtitle: "A quick before-picture, so you can watch it change.") {
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space5) {
                    OnbScalePicker(title: "Mood", lowLabel: "Low", highLabel: "Bright",
                                   value: $vm.baseline.mood)
                    OnbScalePicker(title: "Energy", lowLabel: "Drained", highLabel: "Lively",
                                   value: $vm.baseline.energy)
                    OnbScalePicker(title: "Clarity", lowLabel: "Foggy", highLabel: "Sharp",
                                   value: $vm.baseline.clarity)
                }
            }
        }
    }
}

// MARK: - Step: Exclusions (the two-faced model, SPEC §9)

struct OnbExclusionsStep: View {
    @Environment(\.theme) private var theme
    @Bindable var vm: OnbViewModel

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        OnbStepScaffold(title: "Anything you leave out?",
                        subtitle: "Add what you avoid, then tell us why. An allergy gets flagged loudly; a preference is just quietly left off.") {
            // Category chips.
            LazyVGrid(columns: columns, spacing: theme.metrics.space3) {
                ForEach(OnbExclusionCategory.curated) { cat in
                    OnbChip(label: cat.label, isSelected: isAdded(category: cat)) {
                        if !isAdded(category: cat) { vm.addCategoryExclusion(cat) }
                    }
                }
            }

            // Specific-food search.
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space3) {
                    Text("Or search a specific food")
                        .font(theme.typography.caption(weight: .semibold))
                        .foregroundStyle(theme.colors.textSecondary)
                    TextField("e.g. lentils", text: $vm.foodQuery)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await vm.searchFoods() } }
                        .onChange(of: vm.foodQuery) { _, _ in Task { await vm.searchFoods() } }
                    ForEach(vm.foodHits) { hit in
                        Button { vm.addFoodExclusion(hit) } label: {
                            HStack(spacing: theme.metrics.space2) {
                                Image(systemName: "plus.circle")
                                Text(hit.canonicalName).font(theme.typography.body())
                                Spacer()
                            }
                            .foregroundStyle(theme.colors.primary)
                        }
                    }
                }
            }

            // Drafted exclusions with per-item type (NEVER collapsed, §9).
            if !vm.exclusions.isEmpty {
                VStack(alignment: .leading, spacing: theme.metrics.space3) {
                    SectionHeader(title: "Your list")
                    ForEach($vm.exclusions) { $draft in
                        exclusionRow($draft)
                    }
                }
            }
        }
    }

    private func isAdded(category cat: OnbExclusionCategory) -> Bool {
        vm.exclusions.contains { $0.scope == .category(key: cat.key, label: cat.label) }
    }

    private func exclusionRow(_ draft: Binding<OnbDraftExclusion>) -> some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                HStack {
                    Text(draft.wrappedValue.displayName)
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    Button {
                        vm.removeExclusion(draft.wrappedValue.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .accessibilityLabel("Remove \(draft.wrappedValue.displayName)")
                }
                Picker("Why", selection: draft.exclusionType) {
                    Text("Preference").tag(ExclusionType.preferenceIntolerance)
                    Text("Allergy").tag(ExclusionType.medicalAllergy)
                }
                .pickerStyle(.segmented)
                Text(OnbExclusionBehavior.explainer(draft.wrappedValue.exclusionType))
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }
}

// MARK: - Step: Checks (disclaimers — informs, never blocks)

struct OnbChecksStep: View {
    @Environment(\.theme) private var theme
    @Bindable var vm: OnbViewModel

    var body: some View {
        OnbStepScaffold(title: "A few quick checks",
                        subtitle: "Only so we can look after you well. Nothing here stops you using the app.") {
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space3) {
                    Text("Has a doctor diagnosed you with any of these?")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    ForEach(OnbSeriousCondition.all) { cond in
                        OnbCheckRow(label: cond.label,
                                    isOn: vm.seriousConditions.contains(cond.key)) {
                            vm.toggleSeriousCondition(cond)
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space3) {
                    Text("Noticed any of these recently?")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    ForEach(OnbRedFlag.all) { flag in
                        OnbCheckRow(label: flag.label,
                                    isOn: vm.redFlags.contains(flag.key)) {
                            vm.toggleRedFlag(flag)
                        }
                    }
                }
            }
        }
    }
}
