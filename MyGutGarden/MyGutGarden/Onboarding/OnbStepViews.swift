//
//  OnbStepViews.swift
//  MyGutGarden, Module A: the per-step intake screens + small shared controls.
//
//  Composes DesignSystem primitives (Card, SectionHeader, Badge, buttons) and
//  reads ONLY Theme tokens, never hardcodes a color/font/spacing/radius.
//  Dynamic Type, VoiceOver, and reduced motion come through the shared
//  components; custom affordances add their own labels.
//
//  Steps:
//    Q1 Goals: single-column full-width layout, 10-goal set.
//    Q2 Body:  unit toggle (Metric/US), US ft/in/lb display, age wheel Picker,
//              2-column label/input layout, PlantConsumptionTier picker.
//    Q3 Baseline: mood (Regulated..Erratic), energy, clarity.
//    Q4 Food flags: category chips toggle; food search; two-way tier picker (§9).
//    Q5 Checks: serious conditions + red flags; disclaimers inform, never block.
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

/// Selectable pill (goals, categories). Full-width by default.
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

/// A 1-5 scale picker (baseline sliders). VoiceOver-adjustable.
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

// MARK: - Step: Goals (Q1)
//
// Phase-2 (Batch B): single-column full-width layout so options fill the page.
// 10 goals: first five relief (+1 Survive), last five optimization (-1 Thrive).

struct OnbGoalsStep: View {
    @Environment(\.theme) private var theme
    @Bindable var vm: OnbViewModel

    var body: some View {
        OnbStepScaffold(title: "What brings you here?",
                        subtitle: "Pick as many as you like. This shapes what we show you first.") {
            // Single-column full-width so each option fills the row.
            VStack(spacing: theme.metrics.space3) {
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

// MARK: - Step: Body basics (Q2)
//
// Phase-2 (Batch B):
//   - Unit toggle (Metric / US). Metric: cm/kg. US: ft in / lb (display only; stored cm/kg).
//   - Removed "Share my age" toggle. Age always entered via Picker(.wheel) 12-100.
//   - Left-label / right-input 2-column layout for Age, Biological sex, Activity level.
//   - PlantConsumptionTier picker added as its own section.

struct OnbBodyStep: View {
    @Environment(\.theme) private var theme
    @Bindable var vm: OnbViewModel

    var body: some View {
        OnbStepScaffold(title: "A couple of basics",
                        subtitle: "We use these once, to set a fiber goal that fits you. No weigh-ins, no calorie targets.") {

            // -- Unit toggle --
            Picker("Units", selection: $vm.unitSystem) {
                ForEach(UnitSystem.allCases, id: \.self) { sys in
                    Text(sys.displayName).tag(sys)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Unit system")

            // -- Height + Weight --
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    heightRow
                    Divider().overlay(theme.colors.divider)
                    weightRow
                }
            }

            // -- Optional: Age / Sex / Activity (2-column layout) --
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    Text("Optional, sharpens the estimate")
                        .font(theme.typography.caption(weight: .semibold))
                        .foregroundStyle(theme.colors.textSecondary)

                    // Age: wheel Picker (12-100). Always visible; default 30 is fine.
                    HStack(alignment: .center, spacing: theme.metrics.space3) {
                        Text("Age")
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textPrimary)
                            .frame(width: 130, alignment: .leading)
                        Picker("Age", selection: $vm.ageValue) {
                            ForEach(12...100, id: \.self) { age in
                                Text("\(age)").tag(age)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 100, height: 110)
                        .clipped()
                        .accessibilityLabel("Age")
                        Text("years")
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textSecondary)
                        Spacer(minLength: 0)
                    }

                    Divider().overlay(theme.colors.divider)

                    // Biological sex: menu Picker
                    twoColumnRow(label: "Biological sex") {
                        Picker("Biological sex", selection: $vm.sex) {
                            ForEach(OnbSex.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(theme.colors.primary)
                    }

                    Divider().overlay(theme.colors.divider)

                    // Activity level: menu Picker
                    twoColumnRow(label: "Activity level") {
                        Picker("Activity level", selection: $vm.activity) {
                            ForEach(OnbActivityLevel.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(theme.colors.primary)
                    }
                }
            }

            // -- Plant-food consumption --
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space3) {
                    Text("Overall plant-food consumption")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("Fruits, vegetables, legumes, nuts, seeds, whole grains.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                    VStack(spacing: theme.metrics.space2) {
                        ForEach(PlantConsumptionTier.allCases, id: \.self) { tier in
                            OnbChip(label: tier.displayName,
                                    isSelected: vm.plantConsumptionLevel == tier) {
                                vm.plantConsumptionLevel = tier
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Height row (metric: cm slider; US: ft/in slider with US labels)

    private var heightRow: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            HStack {
                Text("Height")
                    .font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Text(heightLabel)
                    .font(theme.typography.data())
                    .foregroundStyle(theme.colors.primary)
            }
            Slider(value: $vm.heightCm, in: 120...220,
                   step: vm.unitSystem == .metric ? 1 : 2.54)
                .tint(theme.colors.primary)
                .accessibilityLabel("Height")
                .accessibilityValue(heightLabel)
        }
    }

    private var heightLabel: String {
        switch vm.unitSystem {
        case .metric: "\(Int(vm.heightCm)) cm"
        case .us:     "\(vm.heightFeet)' \(vm.heightRemainingInches)\""
        }
    }

    // MARK: Weight row (metric: kg slider; US: lb slider with US labels)

    private var weightRow: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            HStack {
                Text("Weight")
                    .font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Text(weightLabel)
                    .font(theme.typography.data())
                    .foregroundStyle(theme.colors.primary)
            }
            Slider(value: $vm.weightKg, in: 35...200,
                   step: vm.unitSystem == .metric ? 1 : 0.45)
                .tint(theme.colors.primary)
                .accessibilityLabel("Weight")
                .accessibilityValue(weightLabel)
        }
    }

    private var weightLabel: String {
        switch vm.unitSystem {
        case .metric: "\(Int(vm.weightKg)) kg"
        case .us:     "\(vm.weightLbs) lb"
        }
    }

    // MARK: 2-column helper: fixed 130pt left label, right content fills remaining width

    @ViewBuilder
    private func twoColumnRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: theme.metrics.space3) {
            Text(label)
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textPrimary)
                .frame(width: 130, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Step: Baseline (Q3)
//
//   - Mood scale is labeled "Regulated/Erratic": the UI means 1=Regulated(best)..
//     5=Erratic(worst). The CANONICAL inversion (stored as 6 - uiValue) happens
//     ONLY in OnbViewModel.usersWriteBody(), NOT here; this view binds the raw UI value.
//   - Single-mode: the bowel-consistency baseline was retired (no column).

struct OnbBaselineStep: View {
    @Environment(\.theme) private var theme
    @Bindable var vm: OnbViewModel

    var body: some View {
        OnbStepScaffold(title: "How are things lately?",
                        subtitle: "A quick before-picture, so you can watch it change.") {
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space5) {
                    // MOOD SCALE (Phase-2 Batch B): Regulated(1, left)..Erratic(5, right).
                    // UI value bound here is the RAW display value (1=best in display).
                    // Canonical inversion (6 - uiValue) happens only in usersWriteBody().
                    OnbScalePicker(title: "Mood", lowLabel: "Regulated", highLabel: "Erratic",
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

// MARK: - Step: Food flags (Q4, the three-tier model, SPEC §9)
//
//   - Category chips call toggleCategoryFlag so re-tapping deselects.
//   - Food search uses ilike.%q% (OnbViewModel.searchFoods); tap a hit to add.
//   - Each row carries a two-way tier picker (Sensitivity vs Allergy). Onboarding
//     never offers the engine-only `watching` tier, and the old pure-preference
//     path is dropped: everything here is health-framed.

struct OnbFlagsStep: View {
    @Environment(\.theme) private var theme
    @Bindable var vm: OnbViewModel

    var body: some View {
        OnbStepScaffold(title: "Anything you react to?",
                        subtitle: "Add it, then tell us how. An allergy is flagged loudly, even when hidden; a sensitivity gets a gentle heads-up.") {
            // Category chips. Tapping again deselects.
            VStack(spacing: theme.metrics.space3) {
                ForEach(OnbFlagCategory.curated) { cat in
                    OnbChip(label: cat.label, isSelected: isAdded(category: cat)) {
                        vm.toggleCategoryFlag(cat)
                    }
                }
            }

            // Specific-food search (ilike.%q% via ViewModel.searchFoods).
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
                    if !vm.foodHits.isEmpty {
                        VStack(alignment: .leading, spacing: theme.metrics.space1) {
                            ForEach(vm.foodHits) { hit in
                                Button { vm.addFoodFlag(hit) } label: {
                                    HStack(spacing: theme.metrics.space2) {
                                        Image(systemName: "plus.circle")
                                        Text(hit.canonicalName).font(theme.typography.body())
                                        Spacer()
                                    }
                                    .foregroundStyle(theme.colors.primary)
                                    .padding(.vertical, theme.metrics.space1)
                                }
                            }
                        }
                    } else if vm.foodQuery.count >= 2 {
                        Text("No matches. Try a different spelling.")
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
            }

            // Drafted flags with per-item tier (NEVER collapsed, §9).
            if !vm.foodFlags.isEmpty {
                VStack(alignment: .leading, spacing: theme.metrics.space3) {
                    SectionHeader(title: "Your list")
                    ForEach($vm.foodFlags) { $draft in
                        flagRow($draft)
                    }
                }
            }
        }
    }

    private func isAdded(category cat: OnbFlagCategory) -> Bool {
        vm.foodFlags.contains { $0.scope == .category(key: cat.key, label: cat.label) }
    }

    private func flagRow(_ draft: Binding<OnbDraftFlag>) -> some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                HStack {
                    Text(draft.wrappedValue.displayName)
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    Button {
                        vm.removeFoodFlag(draft.wrappedValue.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .accessibilityLabel("Remove \(draft.wrappedValue.displayName)")
                }
                Picker("How should we treat this?", selection: draft.flagTier) {
                    Text("Sensitivity").tag(FlagTier.sensitivity)
                    Text("Allergy").tag(FlagTier.allergy)
                }
                .pickerStyle(.segmented)
                Text(OnbFlagBehavior.explainer(draft.wrappedValue.flagTier))
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }
}

// MARK: - Step: Checks (Q5, disclaimers, informs, never blocks)
//
//   - "Other autoimmune condition" is the FIRST serious-condition item. It drives
//     disclaimer copy only — single-mode persists no column and proposes no flag.
//   - Celiac proposes a loud gluten `food_flag` on acknowledgment (§9).
//   - Privacy disclaimer caption at the bottom.

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
                    // otherAutoimmune is intentionally FIRST (Phase-2 Batch B).
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

            // Privacy disclaimer (Phase-2 Batch B).
            Text("We will never share your health data with third parties.")
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
