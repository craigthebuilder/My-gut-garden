//
//  ThrTestTab.swift
//  MyGutGarden, Module C: the Thrive "test" check-in surface (Batch D / §11a).
//
//  Two related surfaces:
//   1. ThrTestTabView, a "Today"-style multi-entry check-in that mirrors the
//      Survive logger (stool / symptoms / mood / notes) via the shared spine
//      CheckInKit (CheckInDraft(context: .thriveTestTab) + CheckInWriter). A
//      "Light check-in" toggle collapses it to mood-only and stamps
//      thrive_checkins.checkin_mode='light'. This lets a THRIVING user test or
//      reintroduce one or two "bad apple" foods without leaving Thrive.
//   2. ThrDailyCheckinSheet, the lightweight daily mood/energy/clarity +
//      bowel-consistency check-in writing thrive_checkins (opened from Today).
//
//  Mood polarity: the regulated->erratic UI inversion (6 - uiValue) happens ONCE,
//  inside CheckInKit. This file NEVER inverts again (rule: single inversion point).
//

import SwiftUI
import Observation

// MARK: - Test tab (multi-entry check-in on CheckInKit)

struct ThrTestTabView: View {
    @Environment(\.theme) private var theme

    let appState: AppState

    @State private var draft = CheckInDraft(context: .thriveTestTab)
    @State private var todayMeals: [ThrTodayMeal] = []
    @State private var isSaving = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space5) {
                    intro
                    lightToggle
                    if !draft.lightMode {
                        ThrStoolSection(draft: draft, meals: todayMeals)
                        ThrSymptomsSection(draft: draft, meals: todayMeals)
                    }
                    ThrMoodSection(draft: draft, meals: todayMeals)
                    if !draft.lightMode {
                        ThrNotesSection(draft: draft)
                    }
                    saveButton
                }
                .padding(theme.metrics.space4)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Today's check-in")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await loadTodayMeals() }
    }

    private var intro: some View {
        Text("Testing a food? Log how today went. Skip anything that doesn't apply, empty is fine.")
            .font(theme.typography.body())
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var lightToggle: some View {
        Card {
            Toggle(isOn: Binding(get: { draft.lightMode }, set: { draft.lightMode = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Light check-in")
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("Just a quick mood read, nothing else.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .tint(theme.colors.primary)
        }
    }

    private var saveButton: some View {
        VStack(spacing: theme.metrics.space2) {
            PrimaryButton(title: isSaving ? "Saving\u{2026}" : "Save check-in", systemImage: "checkmark") {
                guard !isSaving else { return }
                Task { await save() }
            }
            .disabled(isSaving)
            if saved {
                Text("Saved, thanks for checking in.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.success)
            }
        }
    }

    private func loadTodayMeals() async {
        guard let repo = appState.repository else { return }
        let since = ThrDates.timestampString(ThrDates.startOfToday())
        guard let meals: [MealRow] = try? await repo.select(
            "meals", columns: "id,mode,photo_url,captured_at,confirmed,user_annotation,photo_expires_at",
            filters: ["captured_at": "gte.\(since)", "confirmed": "eq.true"], order: "captured_at.asc"
        ) else { return }
        todayMeals = meals.enumerated().map { idx, meal in
            ThrTodayMeal(id: meal.id, label: ThrTodayMeal.label(for: meal, index: idx + 1))
        }
    }

    private func save() async {
        guard let repo = appState.repository, let uid = appState.profile?.id else { return }
        isSaving = true
        defer { isSaving = false }

        // Light mode stamps thrive_checkins.checkin_mode so the day is recorded as
        // a quick read even when only a mood lands.
        if draft.lightMode {
            try? await repo.upsert("thrive_checkins", [
                "user_id": .string(uid),
                "log_date": .string(ThrDates.dateString(draft.logDate)),
                "checkin_mode": .string("light"),
            ], onConflict: "user_id,log_date")
        }

        let writer = CheckInWriter(repository: repo, userId: uid)
        try? await writer.save(draft)
        saved = true
        draft = CheckInDraft(context: .thriveTestTab)   // reset for the next entry
    }
}

// MARK: - Stool section (multi-entry Bristol + time/tie-to-photo)

struct ThrStoolSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: CheckInDraft
    let meals: [ThrTodayMeal]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                ThrSectionHeaderAdd(title: "Stool") {
                    draft.stools.append(StoolEntryDraft(bss: nil, occurredAt: nil, linkedMealId: nil))
                }
                if draft.stools.isEmpty {
                    ThrAddHint(text: "Add an entry if you'd like to log a bowel movement.")
                }
                ForEach(draft.stools) { entry in
                    if let idx = draft.stools.firstIndex(where: { $0.id == entry.id }) {
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            HStack {
                                Text("Bristol type")
                                    .font(theme.typography.caption(weight: .semibold))
                                    .foregroundStyle(theme.colors.textSecondary)
                                Spacer()
                                ThrRemoveButton { draft.stools.remove(at: idx) }
                            }
                            ThrBristolGrid(selection: draft.stools[idx].bss) { draft.stools[idx].bss = $0 }
                            ThrTimeTieControl(
                                occurredAt: bind(\.occurredAt, idx),
                                linkedMealId: bind(\.linkedMealId, idx),
                                meals: meals
                            )
                        }
                        if entry.id != draft.stools.last?.id { Divider().overlay(theme.colors.divider) }
                    }
                }
            }
        }
    }

    private func bind<V>(_ key: WritableKeyPath<StoolEntryDraft, V>, _ idx: Int) -> Binding<V> {
        Binding(get: { draft.stools[idx][keyPath: key] },
                set: { draft.stools[idx][keyPath: key] = $0 })
    }
}

// MARK: - Symptoms section (bloating / gas / pain / urgency)

struct ThrSymptomsSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: CheckInDraft
    let meals: [ThrTodayMeal]

    private let types = ["bloating", "gas", "pain", "urgency"]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                Text("How it felt")
                    .font(theme.typography.title(20))
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(types, id: \.self) { type in
                    ThrSymptomTypeBlock(draft: draft, type: type, meals: meals)
                }
            }
        }
    }
}

struct ThrSymptomTypeBlock: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: CheckInDraft
    let type: String
    let meals: [ThrTodayMeal]

    @State private var odorEditing: ThrOdorTarget?

    private var rows: [(offset: Int, element: SymptomEntryDraft)] {
        draft.symptoms.enumerated().filter { $0.element.symptomType == type }.map { ($0.offset, $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            ThrSectionHeaderAdd(title: type.capitalized, compact: true) {
                draft.symptoms.append(SymptomEntryDraft(symptomType: type, severity: 0,
                                                        gasOdor: nil, occurredAt: nil, linkedMealId: nil))
            }
            ForEach(rows, id: \.element.id) { pair in
                let idx = pair.offset
                VStack(alignment: .leading, spacing: theme.metrics.space2) {
                    HStack {
                        ThrSeverity0to3Picker(value: draft.symptoms[idx].severity) {
                            draft.symptoms[idx].severity = $0
                            if type == "gas", $0 > 0, draft.symptoms[idx].gasOdor == nil {
                                odorEditing = ThrOdorTarget(id: pair.element.id)
                            }
                        }
                        ThrRemoveButton { draft.symptoms.removeAll { $0.id == pair.element.id } }
                    }
                    if type == "gas", draft.symptoms[idx].severity > 0 {
                        Button { odorEditing = ThrOdorTarget(id: pair.element.id) } label: {
                            HStack(spacing: theme.metrics.space1) {
                                Image(systemName: "nose")
                                Text(draft.symptoms[idx].gasOdor.map { "Odor: \(ThrGasOdor.label(for: $0))" } ?? "Add the smell")
                            }
                            .font(theme.typography.caption(weight: .medium))
                            .foregroundStyle(theme.colors.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    ThrTimeTieControl(
                        occurredAt: bind(\.occurredAt, idx),
                        linkedMealId: bind(\.linkedMealId, idx),
                        meals: meals
                    )
                }
            }
        }
        .sheet(item: $odorEditing) { target in
            if let idx = draft.symptoms.firstIndex(where: { $0.id == target.id }) {
                ThrGasOdorPopup(selected: draft.symptoms[idx].gasOdor) {
                    draft.symptoms[idx].gasOdor = $0
                    odorEditing = nil
                }
            }
        }
    }

    private func bind<V>(_ key: WritableKeyPath<SymptomEntryDraft, V>, _ idx: Int) -> Binding<V> {
        Binding(get: { draft.symptoms[idx][keyPath: key] },
                set: { draft.symptoms[idx][keyPath: key] = $0 })
    }
}

/// Identifiable wrapper so a symptom entry's UUID can drive `.sheet(item:)`.
private struct ThrOdorTarget: Identifiable { let id: UUID }

// MARK: - Mood section (regulated -> erratic; inversion is in CheckInKit)

struct ThrMoodSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: CheckInDraft
    let meals: [ThrTodayMeal]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                ThrSectionHeaderAdd(title: "Mood") {
                    draft.moods.append(MoodEntryDraft(uiValue: 1, occurredAt: nil, linkedMealId: nil))
                }
                if draft.moods.isEmpty {
                    ThrAddHint(text: "Add a mood read for today.")
                }
                ForEach(draft.moods) { entry in
                    if let idx = draft.moods.firstIndex(where: { $0.id == entry.id }) {
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            HStack {
                                Text("Regulated \u{2192} erratic")
                                    .font(theme.typography.caption())
                                    .foregroundStyle(theme.colors.textSecondary)
                                Spacer()
                                ThrRemoveButton { draft.moods.remove(at: idx) }
                            }
                            ThrFiveSegment(value: draft.moods[idx].uiValue) { draft.moods[idx].uiValue = $0 }
                            ThrTimeTieControl(
                                occurredAt: bind(\.occurredAt, idx),
                                linkedMealId: bind(\.linkedMealId, idx),
                                meals: meals
                            )
                        }
                        if entry.id != draft.moods.last?.id { Divider().overlay(theme.colors.divider) }
                    }
                }
            }
        }
    }

    private func bind<V>(_ key: WritableKeyPath<MoodEntryDraft, V>, _ idx: Int) -> Binding<V> {
        Binding(get: { draft.moods[idx][keyPath: key] },
                set: { draft.moods[idx][keyPath: key] = $0 })
    }
}

// MARK: - Notes section ("Anything else?")

struct ThrNotesSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: CheckInDraft

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                ThrSectionHeaderAdd(title: "Anything else?") {
                    draft.notes.append(CheckInNoteDraft(content: "", linkedMealId: nil))
                }
                ForEach(draft.notes) { entry in
                    if let idx = draft.notes.firstIndex(where: { $0.id == entry.id }) {
                        HStack(alignment: .top, spacing: theme.metrics.space2) {
                            TextField("Anything you want to remember (optional)",
                                      text: Binding(get: { draft.notes[idx].content },
                                                    set: { draft.notes[idx].content = $0 }),
                                      axis: .vertical)
                                .lineLimit(1...4)
                                .textFieldStyle(.roundedBorder)
                                .font(theme.typography.body())
                            ThrRemoveButton { draft.notes.remove(at: idx) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Daily check-in sheet (thrive_checkins: mood/energy/clarity + bowel)

struct ThrDailyCheckinSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let appState: AppState

    @State private var mood: Int?
    @State private var energy: Int?
    @State private var clarity: Int?
    @State private var bowel: Int?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    Text("A quick read on how you feel, tracked against where you started. One tap each is plenty.")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Card {
                        VStack(alignment: .leading, spacing: theme.metrics.space3) {
                            ThrScalePicker(label: "Mood", selection: mood) { mood = $0 }
                            ThrScalePicker(label: "Energy", selection: energy) { energy = $0 }
                            ThrScalePicker(label: "Clarity", selection: clarity) { clarity = $0 }
                            ThrScalePicker(label: "Regularity", selection: bowel) { bowel = $0 }
                            Text("Regularity: 1 = all over the place, 5 = nice and consistent.")
                                .font(theme.typography.caption())
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                    PrimaryButton(title: isSaving ? "Saving\u{2026}" : "Save check-in", systemImage: "checkmark") {
                        guard !isSaving else { return }
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
                .padding(theme.metrics.space5)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Daily check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(theme.colors.primary)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let repo = appState.repository, let uid = appState.profile?.id else { return }
        let today = ThrDates.dateString()
        if let rows: [ThriveCheckinRow] = try? await repo.select(
            "thrive_checkins", filters: ["user_id": "eq.\(uid)", "log_date": "eq.\(today)"], limit: 1
        ), let row = rows.first {
            mood = row.mood; energy = row.energy; clarity = row.clarity; bowel = row.bowelConsistency
        }
    }

    private func save() async {
        guard let repo = appState.repository, let uid = appState.profile?.id else { dismiss(); return }
        isSaving = true
        defer { isSaving = false }
        try? await repo.upsert("thrive_checkins", [
            "user_id": .string(uid),
            "log_date": .string(ThrDates.dateString()),
            "mood": mood.map(PGValue.int) ?? .null,
            "energy": energy.map(PGValue.int) ?? .null,
            "clarity": clarity.map(PGValue.int) ?? .null,
            "bowel_consistency": bowel.map(PGValue.int) ?? .null,
        ], onConflict: "user_id,log_date")
        dismiss()
    }
}

// MARK: - Shared building blocks

/// Today's logged meals, for the tie-to-photo control. Label is derived
/// client-side ("after photo 2 of lunch" style), never stored.
struct ThrTodayMeal: Identifiable, Sendable, Equatable {
    let id: String
    let label: String

    static func label(for meal: MealRow, index: Int) -> String {
        if let note = meal.userAnnotation, !note.isEmpty { return "After \(note)" }
        return "After photo \(index)"
    }
}

private struct ThrSectionHeaderAdd: View {
    @Environment(\.theme) private var theme
    let title: String
    var compact = false
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(compact ? theme.typography.body(weight: .semibold) : theme.typography.title(20))
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.colors.primary)
            }
            .accessibilityLabel("Add \(title.lowercased()) entry")
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ThrAddHint: View {
    @Environment(\.theme) private var theme
    let text: String
    var body: some View {
        Text(text)
            .font(theme.typography.caption())
            .foregroundStyle(theme.colors.textSecondary)
    }
}

private struct ThrRemoveButton: View {
    @Environment(\.theme) private var theme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle")
                .font(.system(size: 18))
                .foregroundStyle(theme.colors.textSecondary)
        }
        .accessibilityLabel("Remove entry")
    }
}

/// Bristol 1-7 grid.
struct ThrBristolGrid: View {
    @Environment(\.theme) private var theme
    let selection: Int?
    let onPick: (Int?) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.metrics.space1), count: 7),
                  spacing: theme.metrics.space1) {
            ForEach(1...7, id: \.self) { n in
                let on = selection == n
                Button { onPick(on ? nil : n) } label: {
                    Text("\(n)")
                        .font(theme.typography.data(15, weight: on ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.metrics.space2)
                        .foregroundStyle(on ? theme.colors.surface : theme.colors.textSecondary)
                        .background(on ? theme.colors.primary : theme.colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bristol type \(n)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// 0-3 severity (none / mild / moderate / strong).
struct ThrSeverity0to3Picker: View {
    @Environment(\.theme) private var theme
    let value: Int
    let onPick: (Int) -> Void

    private let labels = ["None", "Mild", "Moderate", "Strong"]

    var body: some View {
        HStack(spacing: theme.metrics.space1) {
            ForEach(0..<labels.count, id: \.self) { level in
                let on = value == level
                Button { onPick(level) } label: {
                    Text(labels[level])
                        .font(theme.typography.caption(weight: on ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.metrics.space2)
                        .foregroundStyle(on ? theme.colors.surface : theme.colors.textSecondary)
                        .background(on ? theme.colors.primary : theme.colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(labels[level])")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// 1-5 segmented control (mood uiValue: 1 = regulated .. 5 = erratic).
struct ThrFiveSegment: View {
    @Environment(\.theme) private var theme
    let value: Int
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            ForEach(1...5, id: \.self) { n in
                let on = value == n
                Button { onPick(n) } label: {
                    Text("\(n)")
                        .font(theme.typography.data(16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.metrics.space2)
                        .foregroundStyle(on ? theme.colors.surface : theme.colors.textSecondary)
                        .background(on ? theme.colors.primary : theme.colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mood \(n) of 5, 1 regulated, 5 erratic")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Unlabeled time control: pick a specific time OR tie the entry to a meal photo.
struct ThrTimeTieControl: View {
    @Environment(\.theme) private var theme
    @Binding var occurredAt: Date?
    @Binding var linkedMealId: String?
    let meals: [ThrTodayMeal]

    @State private var showTime = false

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            Menu {
                Button("No specific time") { occurredAt = nil; linkedMealId = nil; showTime = false }
                if !meals.isEmpty {
                    ForEach(meals) { meal in
                        Button(meal.label) { linkedMealId = meal.id; occurredAt = nil; showTime = false }
                    }
                }
                Button("Pick a time\u{2026}") {
                    linkedMealId = nil
                    if occurredAt == nil { occurredAt = Date() }
                    showTime = true
                }
            } label: {
                HStack(spacing: theme.metrics.space1) {
                    Image(systemName: "clock")
                    Text(label)
                }
                .font(theme.typography.caption(weight: .medium))
                .foregroundStyle(theme.colors.secondary)
            }
            if showTime, occurredAt != nil {
                DatePicker("", selection: Binding(get: { occurredAt ?? Date() }, set: { occurredAt = $0 }),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            Spacer()
        }
    }

    private var label: String {
        if let id = linkedMealId, let meal = meals.first(where: { $0.id == id }) { return meal.label }
        if let occurredAt {
            let f = DateFormatter(); f.timeStyle = .short
            return f.string(from: occurredAt)
        }
        return "Add a time"
    }
}

/// Gas-odor popup (sulfur / sour / odorless) for a gas symptom entry.
struct ThrGasOdorPopup: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let selected: String?
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            Text("The smell")
                .font(theme.typography.title())
                .foregroundStyle(theme.colors.textPrimary)
            Text("A surprisingly useful clue, no judgment.")
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
            ForEach(ThrGasOdor.all, id: \.self) { odor in
                Button { onPick(odor) } label: {
                    HStack {
                        Image(systemName: ThrGasOdor.icon(for: odor))
                        Text(ThrGasOdor.label(for: odor))
                        Spacer()
                        if selected == odor { Image(systemName: "checkmark") }
                    }
                    .font(theme.typography.body())
                    .foregroundStyle(selected == odor ? theme.colors.surface : theme.colors.textPrimary)
                    .padding(theme.metrics.space3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selected == odor ? theme.colors.primary : theme.colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(theme.metrics.space5)
        .background(theme.colors.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

/// Local mirror of the gas_odor enum values (sulfur / sour / odorless). Kept
/// here so Module C never imports a Survive type.
enum ThrGasOdor {
    static let all = ["sulfur", "sour", "odorless"]
    static func label(for raw: String) -> String {
        switch raw {
        case "sulfur": "Sulfur (rotten egg)"
        case "sour": "Sour"
        default: "Odorless"
        }
    }
    static func icon(for raw: String) -> String {
        switch raw {
        case "sulfur": "smoke.fill"
        case "sour": "drop.fill"
        default: "wind"
        }
    }
}

#if DEBUG
#Preview("Thrive test tab") {
    ThrTestTabView(appState: AppState(auth: AuthService()))
        .themed(for: .thrive)
}
#endif
