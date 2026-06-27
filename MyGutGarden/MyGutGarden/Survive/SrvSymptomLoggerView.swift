//
//  SrvSymptomLoggerView.swift
//  MyGutGarden, Module E. The evening multi-entry check-in (SPEC §11b, §12),
//  rebuilt on the SPINE `CheckInKit` so it shares draft + write logic with the
//  Thrive test tab. Calm, low-stimulation, fast: most nights are a couple of taps.
//
//  Each section lets you log SEVERAL entries, each with an optional time you can
//  either type or tie to a recent photo. Mood is presented regulated→erratic; the
//  CANONICAL high=better inversion (6 - uiValue) lives ONLY in CheckInKit, never
//  here. New rows land in the sub-entry tables, never a fresh `symptom_logs` row.
//

import SwiftUI

struct SrvSymptomLoggerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let store: SrvStore
    /// "Light" check-in (off-ramp, Fence 5): drops Pain + Urgency to keep it tiny.
    var lite: Bool = false

    @State private var draft = CheckInDraft(context: .surviveLogger)
    @State private var isSaving = false
    @State private var gasOdorTarget: UUID?      // the gas entry whose odor popup is open

    /// Symptom types shown in "How it felt" (Pain + Urgency drop out when lite).
    private var symptomTypes: [SrvLoggerSymptom] {
        lite ? [.bloating, .gas] : SrvLoggerSymptom.allCases
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space5) {
                    intro
                    stoolSection
                    feltSection
                    moodSection
                    notesSection
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
            .sheet(item: gasOdorBinding) { entryId in
                SrvGasOdorPopup { odor in
                    setGasOdor(odor, for: entryId.id)
                    gasOdorTarget = nil
                }
                .themed(for: .survive)
                .presentationDetents([.height(260)])
            }
        }
    }

    private var intro: some View {
        Text("A quick read on today. Add as much or as little as you like, empty is fine.")
            .font(theme.typography.body())
            .foregroundStyle(theme.colors.textSecondary)
    }

    // MARK: Stool

    private var stoolSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                addHeader("Today's form") { draft.stools.append(StoolEntryDraft(bss: nil, occurredAt: nil, linkedMealId: nil)) }
                if draft.stools.isEmpty {
                    emptyHint("Tap + to note a Bristol type.")
                }
                ForEach(draft.stools) { entry in
                    VStack(alignment: .leading, spacing: theme.metrics.space2) {
                        SrvBristolGrid(selected: entry.bss) { value in
                            mutateStool(entry.id) { $0.bss = $0.bss == value ? nil : value }
                        }
                        HStack {
                            timeControl(occurredAt: entry.occurredAt, linkedMealId: entry.linkedMealId) { at, meal in
                                mutateStool(entry.id) { $0.occurredAt = at; $0.linkedMealId = meal }
                            }
                            Spacer()
                            removeButton { draft.stools.removeAll { $0.id == entry.id } }
                        }
                    }
                    .padding(.bottom, theme.metrics.space1)
                }
            }
        }
    }

    // MARK: How it felt

    private var feltSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                SectionHeader(title: "How it felt")
                ForEach(symptomTypes) { type in
                    symptomGroup(type)
                }
            }
        }
    }

    private func symptomGroup(_ type: SrvLoggerSymptom) -> some View {
        let entries = draft.symptoms.filter { $0.symptomType == type.rawValue }
        return VStack(alignment: .leading, spacing: theme.metrics.space2) {
            addHeader(type.label, style: .subhead) {
                draft.symptoms.append(SymptomEntryDraft(
                    symptomType: type.rawValue, severity: 0, gasOdor: nil, occurredAt: nil, linkedMealId: nil))
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: theme.metrics.space1) {
                    HStack(spacing: theme.metrics.space2) {
                        SrvSeverityRow(severity: entry.severity) { level in
                            mutateSymptom(entry.id) { $0.severity = level }
                            // Gas: any rated level opens the odor popup (the cheap clue).
                            if type == .gas && level > 0 { gasOdorTarget = entry.id }
                        }
                        removeButton { draft.symptoms.removeAll { $0.id == entry.id } }
                    }
                    HStack(spacing: theme.metrics.space2) {
                        if type == .gas, let odor = entry.gasOdor, let known = SrvGasOdor(rawValue: odor) {
                            Badge(text: "\(known.shortLabel) +1", tint: theme.colors.secondary)
                                .onTapGesture { gasOdorTarget = entry.id }
                        }
                        timeControl(occurredAt: entry.occurredAt, linkedMealId: entry.linkedMealId) { at, meal in
                            mutateSymptom(entry.id) { $0.occurredAt = at; $0.linkedMealId = meal }
                        }
                    }
                }
            }
        }
    }

    // MARK: Mood

    private var moodSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                addHeader("Mood") {
                    draft.moods.append(MoodEntryDraft(uiValue: 1, occurredAt: nil, linkedMealId: nil))
                }
                if draft.moods.isEmpty { emptyHint("Tap + to note how steady you felt.") }
                ForEach(draft.moods) { entry in
                    VStack(alignment: .leading, spacing: theme.metrics.space1) {
                        SrvMoodRow(uiValue: entry.uiValue) { value in
                            mutateMood(entry.id) { $0.uiValue = value }
                        }
                        HStack {
                            timeControl(occurredAt: entry.occurredAt, linkedMealId: entry.linkedMealId) { at, meal in
                                mutateMood(entry.id) { $0.occurredAt = at; $0.linkedMealId = meal }
                            }
                            Spacer()
                            removeButton { draft.moods.removeAll { $0.id == entry.id } }
                        }
                    }
                }
            }
        }
    }

    // MARK: Anything else (notes, bottom)

    private var notesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                addHeader("Anything else?") {
                    draft.notes.append(CheckInNoteDraft(content: "", linkedMealId: nil))
                }
                if draft.notes.isEmpty { emptyHint("Add a note to remember anything that stood out.") }
                ForEach(draft.notes) { note in
                    HStack(spacing: theme.metrics.space2) {
                        TextField("Anything you want to remember (optional)",
                                  text: noteBinding(note.id), axis: .vertical)
                            .lineLimit(1...3)
                            .textFieldStyle(.roundedBorder)
                            .font(theme.typography.body())
                        removeButton { draft.notes.removeAll { $0.id == note.id } }
                    }
                }
            }
        }
    }

    // MARK: Save

    private var saveButton: some View {
        VStack(spacing: theme.metrics.space2) {
            PrimaryButton(title: isSaving ? "Saving" : "Save check-in", systemImage: "checkmark") {
                guard !isSaving else { return }
                isSaving = true
                Task {
                    let ok = await store.saveCheckIn(draft)
                    isSaving = false
                    if ok { dismiss() }
                }
            }
            .disabled(isSaving)
            Text(outcomePreview)
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var outcomePreview: String {
        switch SrvStreakEngine.outcome(for: draftDaySymptoms) {
        case .feltGood: "Today reads as a good day, it'll add to your streak."
        case .confounded: "With that context, today pauses your streak rather than breaking it."
        case .hadSymptoms: "Today reads as a rough one, that's useful signal, and tomorrow's a fresh start."
        }
    }

    /// What the streak engine sees from the live draft (no confounders here).
    private var draftDaySymptoms: SrvDaySymptoms {
        func worst(_ type: SrvLoggerSymptom) -> SrvSeverity {
            let worstLevel = draft.symptoms.filter { $0.symptomType == type.rawValue }.map(\.severity).max() ?? 0
            return SrvSeverity(clampingDBValue: worstLevel)
        }
        let bristol = draft.stools.compactMap { $0.bss.flatMap(SrvBristolType.init(rawValue:)) }
            .max { $0.deviationSeverity.rank < $1.deviationSeverity.rank }
        return SrvDaySymptoms(
            bristol: bristol,
            bloating: worst(.bloating), gas: worst(.gas),
            pain: worst(.pain), urgency: worst(.urgency))
    }

    // MARK: Reusable header / buttons

    private enum HeaderStyle { case section, subhead }

    private func addHeader(_ title: String, style: HeaderStyle = .section, add: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(style == .section ? theme.typography.title(20) : theme.typography.body(weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            Button(action: add) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: style == .section ? 22 : 19))
                    .foregroundStyle(theme.colors.primary)
            }
            .accessibilityLabel("Add \(title)")
        }
        .accessibilityAddTraits(style == .section ? .isHeader : [])
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle")
                .foregroundStyle(theme.colors.textSecondary)
        }
        .accessibilityLabel("Remove entry")
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text).font(theme.typography.caption()).foregroundStyle(theme.colors.textSecondary)
    }

    @ViewBuilder
    private func timeControl(occurredAt: Date?, linkedMealId: String?,
                             onUpdate: @escaping (Date?, String?) -> Void) -> some View {
        SrvTimeTieControl(occurredAt: occurredAt, linkedMealId: linkedMealId,
                          meals: store.recentMeals, onUpdate: onUpdate)
    }

    // MARK: Mutation helpers (find-by-id, mutate in place on the @Observable draft)

    private func mutateStool(_ id: UUID, _ change: (inout StoolEntryDraft) -> Void) {
        guard let i = draft.stools.firstIndex(where: { $0.id == id }) else { return }
        change(&draft.stools[i])
    }
    private func mutateSymptom(_ id: UUID, _ change: (inout SymptomEntryDraft) -> Void) {
        guard let i = draft.symptoms.firstIndex(where: { $0.id == id }) else { return }
        change(&draft.symptoms[i])
    }
    private func mutateMood(_ id: UUID, _ change: (inout MoodEntryDraft) -> Void) {
        guard let i = draft.moods.firstIndex(where: { $0.id == id }) else { return }
        change(&draft.moods[i])
    }
    private func setGasOdor(_ odor: SrvGasOdor, for id: UUID) {
        mutateSymptom(id) { $0.gasOdor = odor.rawValue }
    }

    private func noteBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { draft.notes.first { $0.id == id }?.content ?? "" },
            set: { v in if let i = draft.notes.firstIndex(where: { $0.id == id }) { draft.notes[i].content = v } }
        )
    }

    /// Sheet item binding (UUID is Identifiable-wrapped for `.sheet(item:)`).
    private var gasOdorBinding: Binding<SrvIdentifiableUUID?> {
        Binding(
            get: { gasOdorTarget.map(SrvIdentifiableUUID.init) },
            set: { gasOdorTarget = $0?.id }
        )
    }
}

// MARK: - Symptom types in the logger

enum SrvLoggerSymptom: String, CaseIterable, Identifiable {
    case bloating, gas, pain, urgency
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bloating: "Bloating"
        case .gas: "Gas"
        case .pain: "Pain"
        case .urgency: "Urgency"
        }
    }
}

struct SrvIdentifiableUUID: Identifiable { let id: UUID }

// MARK: - Bristol grid (1...7 picture grid)

struct SrvBristolGrid: View {
    @Environment(\.theme) private var theme
    let selected: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.metrics.space2), count: 4),
                  spacing: theme.metrics.space2) {
            ForEach(SrvBristolType.allCases) { type in
                let isOn = selected == type.rawValue
                Button { onSelect(type.rawValue) } label: {
                    VStack(spacing: theme.metrics.space1) {
                        Image(systemName: type.systemImage).font(.system(size: 20))
                        Text(type.title).font(theme.typography.caption())
                            .multilineTextAlignment(.center).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, theme.metrics.space2)
                    .foregroundStyle(isOn ? theme.colors.surface : theme.colors.textPrimary)
                    .background(isOn ? theme.colors.primary : theme.colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                }
                .accessibilityLabel("Type \(type.rawValue), \(type.title)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

// MARK: - Severity row (None / Mild / Moderate / Strong)

struct SrvSeverityRow: View {
    @Environment(\.theme) private var theme
    let severity: Int                 // 0...3
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            ForEach(SrvSeverity.allCases) { level in
                let isOn = severity == level.rawValue
                Button { onSelect(level.rawValue) } label: {
                    Text(level.label)
                        .font(theme.typography.caption(weight: isOn ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.metrics.space2)
                        .foregroundStyle(isOn ? theme.colors.surface : theme.colors.textSecondary)
                        .background(isOn ? theme.colors.primary : theme.colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                }
                .accessibilityLabel(level.label)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

// MARK: - Mood row (Regulated 1 .. Erratic 5; inversion handled in CheckInKit)

struct SrvMoodRow: View {
    @Environment(\.theme) private var theme
    let uiValue: Int                  // 1 = regulated .. 5 = erratic, as shown
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space1) {
            HStack {
                Text("Mood").font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Text("Regulated → Erratic").font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
            HStack(spacing: theme.metrics.space2) {
                ForEach(1...5, id: \.self) { n in
                    let isOn = uiValue == n
                    Button { onSelect(n) } label: {
                        Text("\(n)").font(theme.typography.data(17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, theme.metrics.space2)
                            .foregroundStyle(isOn ? theme.colors.surface : theme.colors.textSecondary)
                            .background(isOn ? theme.colors.primary : theme.colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                    }
                    .accessibilityLabel("Mood \(n) of 5, where 1 is regulated")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - Gas odor popup (the cheap discriminator, opened from a rated gas entry)

struct SrvGasOdorPopup: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let onPick: (SrvGasOdor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            Text("The smell is a useful clue.")
                .font(theme.typography.title(18))
                .foregroundStyle(theme.colors.textPrimary)
            HStack(spacing: theme.metrics.space2) {
                ForEach(SrvGasOdor.allCases) { odor in
                    Button { onPick(odor); dismiss() } label: {
                        VStack(spacing: theme.metrics.space1) {
                            Image(systemName: odor.systemImage).font(.system(size: 20))
                            Text(odor.label).font(theme.typography.caption()).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.metrics.space3)
                        .foregroundStyle(theme.colors.textPrimary)
                        .background(theme.colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                    }
                }
            }
        }
        .padding(theme.metrics.space5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background.ignoresSafeArea())
    }
}

// MARK: - Time / tie-to-photo control (unlabeled)

struct SrvTimeTieControl: View {
    @Environment(\.theme) private var theme
    let occurredAt: Date?
    let linkedMealId: String?
    let meals: [SrvRecentMeal]
    let onUpdate: (Date?, String?) -> Void

    @State private var showSheet = false

    private var displayLabel: String {
        if let id = linkedMealId, let meal = meals.first(where: { $0.id == id }) {
            if let occurredAt, let captured = meal.capturedDate {
                let mins = Int(occurredAt.timeIntervalSince(captured) / 60)
                if mins > 0 { return "\(mins) min after \(meal.label)" }
            }
            return "tied to \(meal.label)"
        }
        if let occurredAt { return occurredAt.formatted(date: .omitted, time: .shortened) }
        return ""
    }

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: theme.metrics.space1) {
                Image(systemName: "clock")
                if !displayLabel.isEmpty {
                    Text(displayLabel).font(theme.typography.caption())
                }
            }
            .foregroundStyle(displayLabel.isEmpty ? theme.colors.textSecondary : theme.colors.primary)
        }
        .accessibilityLabel(displayLabel.isEmpty ? "Add a time" : "Time: \(displayLabel)")
        .sheet(isPresented: $showSheet) {
            SrvTimeTieSheet(occurredAt: occurredAt, linkedMealId: linkedMealId, meals: meals) { at, meal in
                onUpdate(at, meal); showSheet = false
            }
            .themed(for: .survive)
            .presentationDetents([.medium])
        }
    }
}

private struct SrvTimeTieSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let occurredAt: Date?
    let linkedMealId: String?
    let meals: [SrvRecentMeal]
    let onCommit: (Date?, String?) -> Void

    @State private var time: Date
    @State private var meal: String?

    init(occurredAt: Date?, linkedMealId: String?, meals: [SrvRecentMeal],
         onCommit: @escaping (Date?, String?) -> Void) {
        self.occurredAt = occurredAt
        self.linkedMealId = linkedMealId
        self.meals = meals
        self.onCommit = onCommit
        _time = State(initialValue: occurredAt ?? Date())
        _meal = State(initialValue: linkedMealId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                    if !meals.isEmpty {
                        Text("Or tie it to a recent photo")
                            .font(theme.typography.body(weight: .medium))
                            .foregroundStyle(theme.colors.textPrimary)
                        ForEach(meals) { m in
                            Button { meal = (meal == m.id) ? nil : m.id } label: {
                                HStack {
                                    Image(systemName: m.photoUrl == nil ? "photo" : "photo.fill")
                                    Text(m.label).font(theme.typography.body())
                                    Spacer()
                                    if meal == m.id { Image(systemName: "checkmark.circle.fill") }
                                }
                                .foregroundStyle(meal == m.id ? theme.colors.primary : theme.colors.textPrimary)
                                .padding(theme.metrics.space3)
                                .background(theme.colors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                            }
                        }
                    }
                }
                .padding(theme.metrics.space4)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("When")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { onCommit(nil, nil); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onCommit(time, meal); dismiss() }
                        .foregroundStyle(theme.colors.primary)
                }
            }
        }
    }
}

// MARK: - Gas odor short label

private extension SrvGasOdor {
    var shortLabel: String {
        switch self {
        case .sulfur: "sulfur"
        case .sour: "sour"
        case .odorless: "odorless"
        }
    }
}
