//
//  ThrTestTab.swift
//  MyGutGarden, Module C: the Thrive check-in surface (R3 Batch C rebuild).
//
//  ONE check-in, two entry points:
//   • ThrCheckInFormView, the single multi-entry form (stool / symptoms / mood /
//     energy / clarity / notes), opened from BOTH the Today "Log your daily
//     check-in" button and the Check-in tab's "Log a new check-in". No more two
//     different check-ins.
//   • ThrTestTabView, the Check-in TAB, now a LOG of past check-ins grouped by
//     month + week, each editable, plus the persisted "light check-in" pick.
//
//  Light check-in lives here (not in the form): the user picks ONE category to
//  record; it persists on users.light_checkin_category until de-selected, so it no
//  longer flips back after a save.
//
//  Mood polarity: the regulated->erratic inversion (6 - uiValue) happens ONCE,
//  inside CheckInKit. This file never inverts again, except the symmetric reverse
//  (uiValue = 6 - storedScore) when pre-filling an edit.
//

import SwiftUI
import Observation

extension MealRow {
    /// Parsed capture timestamp (meals.captured_at is an ISO string).
    var capturedAtDate: Date? { ThrDates.parseTimestamp(capturedAt) }
}

// MARK: - Check-in TAB: history log + light pick + log-new

struct ThrTestTabView: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    var context: CheckInContext = .thriveCheckin
    var onSaved: (() async -> Void)? = nil

    @State private var model = ThrCheckInHistoryModel()
    @State private var presenting: ThrCheckInFormView.Mode?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space5) {
                    PrimaryButton(title: "Log a new check-in", systemImage: "square.and.pencil") {
                        presenting = .new
                    }
                    // Owner (round 2): ONE place to customize the check-in — the
                    // You section's "Customize check-in" sheet. The session-only
                    // light-pick card that lived here is retired.
                    history
                }
                .padding(theme.metrics.space4)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Check-ins")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await model.load(appState) }
        .sheet(item: $presenting) { mode in
            ThrCheckInFormView(appState: appState, mode: mode, context: context, onSaved: onSaved) {
                presenting = nil
                Task { await model.load(appState) }
            }
        }
    }

    @ViewBuilder private var history: some View {
        if model.isLoading && model.days.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.top, theme.metrics.space5)
        } else if model.days.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space2) {
                    Text("No check-ins yet")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("Your daily check-ins will collect here, grouped by week, ready to revisit and edit.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ForEach(model.groupedByMonth(), id: \.label) { month in
                VStack(alignment: .leading, spacing: theme.metrics.space2) {
                    Text(month.label)
                        .font(theme.typography.title(20))
                        .foregroundStyle(theme.colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(month.days.enumerated()), id: \.element.id) { idx, day in
                        if idx == 0 || !ThrCheckInHistoryModel.sameWeek(month.days[idx - 1].date, day.date) {
                            Text(ThrCheckInHistoryModel.weekLabel(day.date))
                                .font(theme.typography.caption(weight: .semibold))
                                .foregroundStyle(theme.colors.textSecondary)
                                .padding(.top, theme.metrics.space1)
                        }
                        Button { presenting = .edit(day) } label: { dayRow(day) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func dayRow(_ day: ThrCheckInDay) -> some View {
        Card {
            HStack(spacing: theme.metrics.space3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ThrCheckInHistoryModel.dayLabel(day.date))
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(day.summaryLine)
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this check-in to edit")
    }
}

// (The session-only "Light check-in" picker was retired — owner, 2026-07-02
// round 2. Customization lives solely in You → "Customize check-in".)

// MARK: - The single multi-entry check-in form (new + edit)

struct ThrCheckInFormView: View {
    enum Mode: Identifiable {
        case new
        case edit(ThrCheckInDay)
        var id: String { switch self { case .new: "new"; case .edit(let d): d.id } }
    }

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let appState: AppState
    let mode: Mode
    /// Which surface this check-in belongs to. Thrive uses .thriveCheckin (light
    /// pick + the thrive_checkins trend aggregate); Survive uses .surviveLogger
    /// (no light, runs the post-save hook to refresh the streak + break detector).
    var context: CheckInContext = .thriveCheckin
    /// Mode-specific work to run after a successful save (e.g. Survive store reload).
    var onSaved: (() async -> Void)? = nil
    let onDone: () -> Void

    @State private var draft = CheckInDraft(context: .thriveCheckin)
    @State private var meals: [ThrTodayMeal] = []
    @State private var editingCheckInIds: [String] = []   // the day's check_ins, dropped-and-reinserted on save
    @State private var isSaving = false
    @State private var configured = false

    private func active(_ c: CheckInCategory) -> Bool {
        (draft.lightCategory == nil || draft.lightCategory == c) && (draft.enabledCategories?.contains(c) ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space5) {
                    intro
                    if active(.stool)   { ThrStoolSection(draft: draft, meals: meals) }
                    if active(.symptom) { ThrSymptomsSection(draft: draft, meals: meals) }
                    if active(.mood)    { ThrMoodSection(draft: draft, meals: meals) }
                    if active(.energy)  { ThrMetricSection(draft: draft, title: "Energy", metricType: "energy", keyPath: \.energy, meals: meals) }
                    if active(.clarity) { ThrMetricSection(draft: draft, title: "Clarity", metricType: "clarity", keyPath: \.clarity, meals: meals) }
                    if draft.lightCategory == nil && draft.notesEnabled { ThrNotesSection(draft: draft) }
                    saveButton
                }
                .padding(theme.metrics.space4)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(theme.colors.primary)
                }
            }
        }
        .task {
            if !configured { await loadPrefs(); configure(); configured = true }
            await loadMeals()
        }
    }

    private var navTitle: String {
        if case .edit = mode { return "Edit check-in" }
        return "Today's check-in"
    }

    private var intro: some View {
        Text(draft.lightCategory == nil
             ? "Log how today went. Skip anything that doesn't apply, empty is fine."
             : "A quick \(draft.lightCategory!.title.lowercased()) read. Change this in the Check-in tab.")
            .font(theme.typography.body())
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var saveButton: some View {
        PrimaryButton(title: isSaving ? "Saving\u{2026}" : "Save check-in", systemImage: "checkmark") {
            guard !isSaving else { return }
            Task { await save() }
        }
        .disabled(isSaving)
    }

    private func loadPrefs() async {
        guard let repo = appState.repository else { return }
        struct PrefsRow: Decodable { let enabledSections: [String] }
        let rows: [PrefsRow] = (try? await repo.select("check_in_prefs", columns: "enabled_sections", limit: 1)) ?? []
        guard let sections = rows.first?.enabledSections else { return }
        let cats = Set(sections.compactMap { CheckInCategory(rawValue: $0) })
        guard !cats.isEmpty else { return }        // no real category chosen → keep all (default)
        draft.enabledCategories = cats
        draft.notesEnabled = sections.contains("notes")
    }

    private func configure() {
        draft.context = context
        switch mode {
        case .new:
            draft.logDate = Date()
            // TODO(Phase 1E): restore the persisted light-check-in pick once the
            // profile/prefs model resurfaces `light_checkin_category`. For now every
            // new check-in opens as the full form.
            draft.lightCategory = nil
            draft.seedEmptyEntries()
        case .edit(let day):
            draft.logDate = day.date
            draft.lightCategory = nil            // editing always shows the full form
            editingCheckInIds = day.checkInIds
            prefill(from: day)
        }
    }

    private func prefill(from day: ThrCheckInDay) {
        draft.stools = day.stools.map {
            StoolEntryDraft(bss: $0.bss, occurredAt: ThrDates.parseTimestamp($0.occurredAt ?? ""), linkedMealId: $0.linkedMealId)
        }
        draft.symptoms = day.symptoms.map {
            SymptomEntryDraft(symptomType: $0.symptomType, severity: $0.severity, gasOdor: $0.gasOdor,
                              occurredAt: ThrDates.parseTimestamp($0.occurredAt ?? ""), linkedMealId: $0.linkedMealId)
        }
        draft.moods = day.moods.map {
            MoodEntryDraft(uiValue: 6 - $0.moodScore, occurredAt: ThrDates.parseTimestamp($0.occurredAt ?? ""), linkedMealId: $0.linkedMealId)
        }
        draft.energy = day.metrics.filter { $0.metricType == "energy" }.map {
            MetricEntryDraft(metricType: "energy", score: $0.score, occurredAt: ThrDates.parseTimestamp($0.occurredAt ?? ""), linkedMealId: $0.linkedMealId)
        }
        draft.clarity = day.metrics.filter { $0.metricType == "clarity" }.map {
            MetricEntryDraft(metricType: "clarity", score: $0.score, occurredAt: ThrDates.parseTimestamp($0.occurredAt ?? ""), linkedMealId: $0.linkedMealId)
        }
        draft.notes = day.notes.map { CheckInNoteDraft(content: $0.content, linkedMealId: $0.linkedMealId) }

        // Make sure each category has at least one row so the user can add/keep editing.
        if draft.stools.isEmpty  { draft.stools = [StoolEntryDraft()] }
        if draft.moods.isEmpty   { draft.moods = [MoodEntryDraft(uiValue: 0)] }
        if draft.energy.isEmpty  { draft.energy = [MetricEntryDraft(metricType: "energy", score: 0)] }
        if draft.clarity.isEmpty { draft.clarity = [MetricEntryDraft(metricType: "clarity", score: 0)] }
    }

    private func loadMeals() async {
        guard let repo = appState.repository else { return }
        let dayStart = Calendar.current.startOfDay(for: draft.logDate)
        let dayEnd = dayStart.addingTimeInterval(24 * 3600)
        guard let rows: [MealRow] = try? await repo.select(
            "meals", columns: "id,photo_url,captured_at,confirmed,user_annotation",
            filters: ["captured_at": "gte.\(ThrDates.timestampString(dayStart))",
                      "confirmed": "eq.true"], order: "captured_at.asc"
        ) else { return }
        meals = ThrTodayMeal.list(rows.filter { ($0.capturedAtDate ?? dayStart) < dayEnd })
    }

    private func save() async {
        guard let repo = appState.repository, let uid = appState.profile?.id else { dismiss(); return }
        isSaving = true
        defer { isSaving = false }
        // Replace-in-place on edit: delete the day's check_ins (cascade removes entries).
        if case .edit = mode, !editingCheckInIds.isEmpty {
            try? await repo.delete("check_ins", filters: ["id": "in.(\(editingCheckInIds.joined(separator: ",")))"])
        }
        try? await CheckInWriter(repository: repo, userId: uid).save(draft)
        await onSaved?()                                         // mode-specific refresh
        onDone()
        dismiss()
    }
}

// MARK: - History model

struct ThrCheckInDay: Identifiable, Sendable {
    let id: String           // log_date "yyyy-MM-dd"
    let date: Date
    var checkInIds: [String] = []    // the check_ins making up this day (deleted on edit; cascade)
    var stools: [StoolEntryRow] = []
    var symptoms: [SymptomEntryRow] = []
    var moods: [MoodEntryRow] = []
    var metrics: [MetricEntryRow] = []
    var notes: [CheckinNoteRow] = []

    var summaryLine: String {
        var parts: [String] = []
        if !stools.isEmpty { parts.append("\(stools.count) stool\(stools.count > 1 ? "s" : "")") }
        if !symptoms.isEmpty {
            let names = Set(symptoms.map(\.symptomType)).sorted()
            parts.append(names.joined(separator: ", "))
        }
        if !moods.isEmpty { parts.append("mood") }
        if metrics.contains(where: { $0.metricType == "energy" }) { parts.append("energy") }
        if metrics.contains(where: { $0.metricType == "clarity" }) { parts.append("clarity") }
        if !notes.isEmpty { parts.append("note") }
        return parts.isEmpty ? "Tap to view" : parts.joined(separator: " \u{00B7} ")
    }
}

@Observable @MainActor
final class ThrCheckInHistoryModel {
    var days: [ThrCheckInDay] = []
    var isLoading = false

    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func load(_ appState: AppState) async {
        guard let repo = appState.repository, let uid = appState.profile?.id else { return }
        isLoading = true
        defer { isLoading = false }
        let checkIns: [CheckInRow] = (try? await repo.select(
            "check_ins", filters: ["user_id": "eq.\(uid)"], order: "log_date.desc", limit: 500)) ?? []
        guard !checkIns.isEmpty else { days = []; return }
        let dayByCheckIn = Dictionary(checkIns.map { ($0.id, $0.logDate) }, uniquingKeysWith: { a, _ in a })
        let ids = checkIns.map(\.id).joined(separator: ",")
        let entries: [CheckInEntryRow] = (try? await repo.select(
            "check_in_entries", filters: ["check_in_id": "in.(\(ids))"])) ?? []

        var map: [String: ThrCheckInDay] = [:]
        func ensure(_ d: String) -> ThrCheckInDay {
            map[d] ?? ThrCheckInDay(id: d, date: Self.dayParser.date(from: d) ?? Date())
        }
        for ci in checkIns { var x = ensure(ci.logDate); x.checkInIds.append(ci.id); map[ci.logDate] = x }
        for e in entries {
            guard let day = dayByCheckIn[e.checkInId] else { continue }
            var x = ensure(day)
            switch e.sectionKey {
            case "bss":
                x.stools.append(StoolEntryRow(id: e.id, userId: uid, logDate: day, bss: e.valueInt,
                                              occurredAt: e.occurredAt, linkedMealId: e.linkedMealId, loggedAt: ""))
            case "bloating", "gas", "pain", "urgency", "cramping":
                x.symptoms.append(SymptomEntryRow(id: e.id, userId: uid, logDate: day, symptomType: e.sectionKey,
                                                  severity: e.valueInt ?? 0, gasOdor: e.valueText,
                                                  occurredAt: e.occurredAt, linkedMealId: e.linkedMealId))
            case "mood":
                x.moods.append(MoodEntryRow(id: e.id, userId: uid, logDate: day, moodScore: e.valueInt ?? 0,
                                            context: "", occurredAt: e.occurredAt, linkedMealId: e.linkedMealId))
            case "energy", "clarity":
                x.metrics.append(MetricEntryRow(id: e.id, userId: uid, logDate: day, metricType: e.sectionKey,
                                                score: e.valueInt ?? 0, context: "", occurredAt: e.occurredAt,
                                                linkedMealId: e.linkedMealId))
            case "notes":
                x.notes.append(CheckinNoteRow(id: e.id, userId: uid, logDate: day, content: e.valueText ?? "",
                                              context: "", linkedMealId: e.linkedMealId, createdAt: ""))
            default: break   // felt_okay / context aren't shown in the form history
            }
            map[day] = x
        }
        days = map.values.sorted { $0.date > $1.date }
    }

    func groupedByMonth() -> [(label: String, days: [ThrCheckInDay])] {
        let cal = Calendar.current
        var order: [String] = []
        var buckets: [String: [ThrCheckInDay]] = [:]
        let fmt = DateFormatter(); fmt.dateFormat = "LLLL yyyy"
        for day in days {
            let key = fmt.string(from: day.date)
            if buckets[key] == nil { buckets[key] = []; order.append(key) }
            buckets[key]?.append(day)
        }
        _ = cal
        return order.map { ($0, buckets[$0] ?? []) }
    }

    static func sameWeek(_ a: Date, _ b: Date) -> Bool {
        let cal = Calendar.current
        return cal.component(.weekOfYear, from: a) == cal.component(.weekOfYear, from: b)
            && cal.component(.yearForWeekOfYear, from: a) == cal.component(.yearForWeekOfYear, from: b)
    }

    static func weekLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) ?? d
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "Week of \(f.string(from: start))"
    }

    static func dayLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f.string(from: d)
    }
}

// MARK: - Sections (id-based bindings; add-then-remove can never crash)

struct ThrStoolSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: CheckInDraft
    let meals: [ThrTodayMeal]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                ThrSectionHeaderAdd(title: "Stool") { draft.stools.append(StoolEntryDraft()) }
                ForEach(draft.stools) { entry in
                    VStack(alignment: .leading, spacing: theme.metrics.space2) {
                        HStack {
                            Text("Bristol type")
                                .font(theme.typography.caption(weight: .semibold))
                                .foregroundStyle(theme.colors.textSecondary)
                            Spacer()
                            ThrRemoveButton { draft.stools.removeAll { $0.id == entry.id } }
                        }
                        ThrBristolGrid(selection: entry.bss) { v in update(entry.id) { $0.bss = v } }
                        ThrTimeTieControl(
                            occurredAt: bind(entry.id, \.occurredAt, nil),
                            linkedMealId: bind(entry.id, \.linkedMealId, nil),
                            mealOffsetMinutes: bind(entry.id, \.mealOffsetMinutes, nil),
                            meals: meals)
                    }
                    if entry.id != draft.stools.last?.id { Divider().overlay(theme.colors.divider) }
                }
            }
        }
    }

    private func update(_ id: UUID, _ mutate: (inout StoolEntryDraft) -> Void) {
        if let i = draft.stools.firstIndex(where: { $0.id == id }) { mutate(&draft.stools[i]) }
    }
    private func bind<V>(_ id: UUID, _ key: WritableKeyPath<StoolEntryDraft, V>, _ fb: V) -> Binding<V> {
        Binding(get: { draft.stools.first { $0.id == id }?[keyPath: key] ?? fb },
                set: { v in update(id) { $0[keyPath: key] = v } })
    }
}

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

    private var entries: [SymptomEntryDraft] { draft.symptoms.filter { $0.symptomType == type } }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            ThrSectionHeaderAdd(title: type.capitalized, compact: true) {
                draft.symptoms.append(SymptomEntryDraft(symptomType: type, severity: 0))
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: theme.metrics.space2) {
                    HStack {
                        ThrSeverity0to3Picker(value: entry.severity) { v in
                            update(entry.id) { $0.severity = v }
                            if type == "gas", v > 0, entry.gasOdor == nil { odorEditing = ThrOdorTarget(id: entry.id) }
                        }
                        ThrRemoveButton { draft.symptoms.removeAll { $0.id == entry.id } }
                    }
                    if type == "gas", entry.severity > 0 {
                        Button { odorEditing = ThrOdorTarget(id: entry.id) } label: {
                            HStack(spacing: theme.metrics.space1) {
                                Image(systemName: "nose")
                                Text(entry.gasOdor.map { "Odor: \(ThrGasOdor.label(for: $0))" } ?? "Add the smell")
                            }
                            .font(theme.typography.caption(weight: .medium))
                            .foregroundStyle(theme.colors.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    ThrTimeTieControl(
                        occurredAt: bind(entry.id, \.occurredAt, nil),
                        linkedMealId: bind(entry.id, \.linkedMealId, nil),
                        mealOffsetMinutes: bind(entry.id, \.mealOffsetMinutes, nil),
                        meals: meals)
                }
            }
        }
        .sheet(item: $odorEditing) { target in
            ThrGasOdorPopup(selected: draft.symptoms.first { $0.id == target.id }?.gasOdor) { odor in
                update(target.id) { $0.gasOdor = odor }
                odorEditing = nil
            }
        }
    }

    private func update(_ id: UUID, _ mutate: (inout SymptomEntryDraft) -> Void) {
        if let i = draft.symptoms.firstIndex(where: { $0.id == id }) { mutate(&draft.symptoms[i]) }
    }
    private func bind<V>(_ id: UUID, _ key: WritableKeyPath<SymptomEntryDraft, V>, _ fb: V) -> Binding<V> {
        Binding(get: { draft.symptoms.first { $0.id == id }?[keyPath: key] ?? fb },
                set: { v in update(id) { $0[keyPath: key] = v } })
    }
}

private struct ThrOdorTarget: Identifiable { let id: UUID }

struct ThrMoodSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: CheckInDraft
    let meals: [ThrTodayMeal]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                ThrSectionHeaderAdd(title: "Mood") { draft.moods.append(MoodEntryDraft(uiValue: 0)) }
                ForEach(draft.moods) { entry in
                    VStack(alignment: .leading, spacing: theme.metrics.space2) {
                        HStack {
                            Text("Regulated \u{2192} erratic")
                                .font(theme.typography.caption())
                                .foregroundStyle(theme.colors.textSecondary)
                            Spacer()
                            ThrRemoveButton { draft.moods.removeAll { $0.id == entry.id } }
                        }
                        ThrFiveSegment(value: entry.uiValue, accessibilityPrefix: "Mood") { v in update(entry.id) { $0.uiValue = v } }
                        ThrTimeTieControl(
                            occurredAt: bind(entry.id, \.occurredAt, nil),
                            linkedMealId: bind(entry.id, \.linkedMealId, nil),
                            mealOffsetMinutes: bind(entry.id, \.mealOffsetMinutes, nil),
                            meals: meals)
                    }
                    if entry.id != draft.moods.last?.id { Divider().overlay(theme.colors.divider) }
                }
            }
        }
    }

    private func update(_ id: UUID, _ mutate: (inout MoodEntryDraft) -> Void) {
        if let i = draft.moods.firstIndex(where: { $0.id == id }) { mutate(&draft.moods[i]) }
    }
    private func bind<V>(_ id: UUID, _ key: WritableKeyPath<MoodEntryDraft, V>, _ fb: V) -> Binding<V> {
        Binding(get: { draft.moods.first { $0.id == id }?[keyPath: key] ?? fb },
                set: { v in update(id) { $0[keyPath: key] = v } })
    }
}

/// Energy / Clarity (high=better, no inversion). Shares one view over a keypath
/// to the chosen draft array.
struct ThrMetricSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: CheckInDraft
    let title: String
    let metricType: String
    let keyPath: ReferenceWritableKeyPath<CheckInDraft, [MetricEntryDraft]>
    let meals: [ThrTodayMeal]

    private var entries: [MetricEntryDraft] { draft[keyPath: keyPath] }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                ThrSectionHeaderAdd(title: title) {
                    draft[keyPath: keyPath].append(MetricEntryDraft(metricType: metricType, score: 0))
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: theme.metrics.space2) {
                        HStack {
                            Text("Low \u{2192} high")
                                .font(theme.typography.caption())
                                .foregroundStyle(theme.colors.textSecondary)
                            Spacer()
                            ThrRemoveButton { draft[keyPath: keyPath].removeAll { $0.id == entry.id } }
                        }
                        ThrFiveSegment(value: entry.score, accessibilityPrefix: title) { v in update(entry.id) { $0.score = v } }
                        ThrTimeTieControl(
                            occurredAt: bind(entry.id, \.occurredAt, nil),
                            linkedMealId: bind(entry.id, \.linkedMealId, nil),
                            mealOffsetMinutes: bind(entry.id, \.mealOffsetMinutes, nil),
                            meals: meals)
                    }
                    if entry.id != entries.last?.id { Divider().overlay(theme.colors.divider) }
                }
            }
        }
    }

    private func update(_ id: UUID, _ mutate: (inout MetricEntryDraft) -> Void) {
        if let i = draft[keyPath: keyPath].firstIndex(where: { $0.id == id }) { mutate(&draft[keyPath: keyPath][i]) }
    }
    private func bind<V>(_ id: UUID, _ key: WritableKeyPath<MetricEntryDraft, V>, _ fb: V) -> Binding<V> {
        Binding(get: { draft[keyPath: keyPath].first { $0.id == id }?[keyPath: key] ?? fb },
                set: { v in update(id) { $0[keyPath: key] = v } })
    }
}

struct ThrNotesSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: CheckInDraft

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                ThrSectionHeaderAdd(title: "Anything else?") { draft.notes.append(CheckInNoteDraft(content: "")) }
                ForEach(draft.notes) { entry in
                    HStack(alignment: .top, spacing: theme.metrics.space2) {
                        TextField("Anything you want to remember (optional)",
                                  text: bind(entry.id), axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.roundedBorder)
                            .font(theme.typography.body())
                        ThrRemoveButton { draft.notes.removeAll { $0.id == entry.id } }
                    }
                }
            }
        }
    }

    private func bind(_ id: UUID) -> Binding<String> {
        Binding(get: { draft.notes.first { $0.id == id }?.content ?? "" },
                set: { v in if let i = draft.notes.firstIndex(where: { $0.id == id }) { draft.notes[i].content = v } })
    }
}

// MARK: - Shared building blocks

/// A logged meal for the tie-to-photo control. Labels come from the capture
/// TIME ("11am breakfast", MealTimeLabel) — never the note text, never
/// "Meal 2" — so linking a symptom to a meal reads the way people remember
/// meals. The DB records which meal + the derived occurred_at.
struct ThrTodayMeal: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let capturedAt: Date

    static func list(_ rows: [MealRow]) -> [ThrTodayMeal] {
        let dates = rows.map { $0.capturedAtDate ?? Date() }
        let labels = MealTimeLabel.labels(for: dates)
        return rows.indices.map { ThrTodayMeal(id: rows[$0].id, label: labels[$0], capturedAt: dates[$0]) }
    }
}

/// Unlabeled time control: No specific time / Link to a meal (-> offset) / Pick a time.
struct ThrTimeTieControl: View {
    @Environment(\.theme) private var theme
    @Binding var occurredAt: Date?
    @Binding var linkedMealId: String?
    @Binding var mealOffsetMinutes: Int?
    let meals: [ThrTodayMeal]

    @State private var showTime = false

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            Menu {
                Button("No specific time") { clearAll() }
                if !meals.isEmpty {
                    Menu("Link to a meal") {
                        ForEach(meals) { meal in
                            Menu(meal.label) {
                                ForEach(mealTieOffsets, id: \.self) { off in
                                    Button(mealTieLabel(off)) { link(meal, off) }
                                }
                            }
                        }
                    }
                }
                Button("Pick a time\u{2026}") { pickTime() }
            } label: {
                HStack(spacing: theme.metrics.space1) {
                    Image(systemName: "clock")
                    Text(label)
                }
                .font(theme.typography.caption(weight: .medium))
                .foregroundStyle(theme.colors.secondary)
            }
            if showTime, linkedMealId == nil, occurredAt != nil {
                DatePicker("", selection: Binding(get: { occurredAt ?? Date() }, set: { occurredAt = $0 }),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            Spacer()
        }
    }

    private func clearAll() { occurredAt = nil; linkedMealId = nil; mealOffsetMinutes = nil; showTime = false }
    private func link(_ meal: ThrTodayMeal, _ off: Int) {
        linkedMealId = meal.id
        mealOffsetMinutes = off
        occurredAt = meal.capturedAt.addingTimeInterval(Double(off) * 60)
        showTime = false
    }
    private func pickTime() {
        linkedMealId = nil; mealOffsetMinutes = nil
        if occurredAt == nil { occurredAt = Date() }
        showTime = true
    }

    private var label: String {
        if linkedMealId != nil { return mealTieLabel(mealOffsetMinutes ?? 0) }
        if let occurredAt {
            let f = DateFormatter(); f.timeStyle = .short
            return f.string(from: occurredAt)
        }
        return "Add a time"
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

/// Bristol 1-7 as an ICON grid (identical to Survive's, R4 unification).
struct ThrBristolGrid: View {
    @Environment(\.theme) private var theme
    let selection: Int?
    let onPick: (Int?) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.metrics.space2), count: 4),
                  spacing: theme.metrics.space2) {
            ForEach(CheckInBristol.allCases) { type in
                let on = selection == type.rawValue
                Button { onPick(on ? nil : type.rawValue) } label: {
                    VStack(spacing: theme.metrics.space1) {
                        Image(systemName: type.systemImage).font(.system(size: 20))
                        Text(type.title).font(theme.typography.caption())
                            .multilineTextAlignment(.center).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, theme.metrics.space2)
                    .foregroundStyle(on ? theme.colors.surface : theme.colors.textPrimary)
                    .background(on ? theme.colors.primary : theme.colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bristol type \(type.rawValue), \(type.title)")
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

/// 1-5 segmented control. value 0 = unset (nothing highlighted).
struct ThrFiveSegment: View {
    @Environment(\.theme) private var theme
    let value: Int
    var accessibilityPrefix: String = "Value"
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
                .accessibilityLabel("\(accessibilityPrefix) \(n) of 5")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
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

/// Local mirror of the gas_odor enum values. Kept here so Module C never imports a
/// Survive type.
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

// MARK: - Customize check-in (which sections appear; SPEC §12)

struct YouCheckInPrefsSheet: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    let onDone: () -> Void

    @State private var enabled: Set<CheckInCategory> = Set(CheckInCategory.allCases)
    @State private var notesEnabled = true
    @State private var loaded = false
    @State private var saving = false
    // A sheet-LOCAL coach controller (owner, 2026-07-09: "add a tour for
    // customize"). The shared shell overlay can't reach into a sheet, so the
    // sheet renders its own spotlight overlay bound to this local controller —
    // isolated, so the tour can never leak back onto the home screen. Completion
    // still persists to tutorial_state (section "customize"), so it shows once.
    @State private var coach = CoachMarkController()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    Text("Pick what your check-in asks about — add as much or as little as you like. This also shapes your trends.")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Card {
                        VStack(spacing: theme.metrics.space2) {
                            ForEach(CheckInCategory.allCases) { cat in
                                toggleRow(cat.title, on: enabled.contains(cat)) {
                                    if enabled.contains(cat) { enabled.remove(cat) } else { enabled.insert(cat) }
                                }
                            }
                            toggleRow("Notes", on: notesEnabled) { notesEnabled.toggle() }
                        }
                    }
                    .coachTarget("customize")
                    PrimaryButton(title: saving ? "Saving\u{2026}" : "Save") { Task { await save() } }
                        .disabled(saving)
                }
                .padding(theme.metrics.space4)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Customize check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: onDone) } }
            .overlayPreferenceValue(CoachTargetKey.self) { anchors in
                CoachMarkOverlay(controller: coach, appState: appState, anchors: anchors)
            }
        }
        .task {
            await load()
            await coach.loadCompleted(appState)
            await coach.startIfNeeded("customize", appState: appState)
        }
    }

    private func toggleRow(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? theme.colors.primary : theme.colors.textSecondary)
            }
            .font(theme.typography.body())
            .padding(.vertical, theme.metrics.space1)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard !loaded, let repo = appState.repository else { return }
        struct PrefsRow: Decodable { let enabledSections: [String] }
        let rows: [PrefsRow] = (try? await repo.select("check_in_prefs", columns: "enabled_sections", limit: 1)) ?? []
        if let sections = rows.first?.enabledSections {
            let cats = Set(sections.compactMap { CheckInCategory(rawValue: $0) })
            if !cats.isEmpty { enabled = cats; notesEnabled = sections.contains("notes") }
        }
        loaded = true
    }

    private func save() async {
        guard let repo = appState.repository, let uid = appState.profile?.id else { return }
        saving = true
        defer { saving = false }
        var sections = enabled.map(\.rawValue)
        if notesEnabled { sections.append("notes") }
        try? await repo.upsert("check_in_prefs",
            ["user_id": .string(uid), "enabled_sections": .stringArray(sections)],
            onConflict: "user_id")
        onDone()
    }
}

#if DEBUG
#Preview("Thrive check-in tab") {
    ThrTestTabView(appState: AppState(auth: AuthService()))
        .themed()
}
#endif
