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
    /// Shared by both modes (R4). Thrive shows the light-check-in picker; Survive
    /// passes showsLight=false and an onSaved hook to refresh its store.
    var context: CheckInContext = .thriveCheckin
    var showsLight: Bool = true
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
                    if showsLight { ThrLightCheckInPicker(appState: appState) }
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

// MARK: - Persisted light-check-in picker

struct ThrLightCheckInPicker: View {
    @Environment(\.theme) private var theme
    let appState: AppState

    @State private var selection: CheckInCategory?   // nil = full check-in

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Text("Light check-in")
                    .font(theme.typography.body(weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Pick one thing to track each day, or the full check-in. This sticks until you change it.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Menu {
                    Button { set(nil) } label: { pickRow("Full check-in", on: selection == nil) }
                    ForEach(CheckInCategory.allCases) { cat in
                        Button { set(cat) } label: { pickRow("\(cat.title) only", on: selection == cat) }
                    }
                } label: {
                    HStack(spacing: theme.metrics.space1) {
                        Image(systemName: "slider.horizontal.3")
                        Text(selection.map { "\($0.title) only" } ?? "Full check-in")
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                    }
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.surface)
                    .padding(.vertical, theme.metrics.space2)
                    .padding(.horizontal, theme.metrics.space3)
                    .background(theme.colors.primary)
                    .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { selection = appState.profile?.lightCheckinCategory.flatMap(CheckInCategory.init(rawValue:)) }
    }

    @ViewBuilder private func pickRow(_ title: String, on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func set(_ cat: CheckInCategory?) {
        selection = cat
        Task {
            guard let repo = appState.repository, let uid = appState.profile?.id else { return }
            try? await repo.update("users",
                                   set: ["light_checkin_category": cat.map { PGValue.string($0.rawValue) } ?? .null],
                                   filters: ["id": "eq.\(uid)"])
            await appState.refreshProfile()
        }
    }
}

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
    @State private var editing = ThrEditingIds()
    @State private var isSaving = false
    @State private var configured = false

    private func active(_ c: CheckInCategory) -> Bool { draft.lightCategory == nil || draft.lightCategory == c }

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
                    if draft.lightCategory == nil { ThrNotesSection(draft: draft) }
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
            if !configured { configure(); configured = true }
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

    private func configure() {
        draft.context = context
        switch mode {
        case .new:
            draft.logDate = Date()
            // Light check-in is Thrive-only; Survive is always the full check-in.
            draft.lightCategory = context == .thriveCheckin
                ? appState.profile?.lightCheckinCategory.flatMap(CheckInCategory.init(rawValue:))
                : nil
            draft.seedEmptyEntries()
        case .edit(let day):
            draft.logDate = day.date
            draft.lightCategory = nil            // editing always shows the full form
            prefill(from: day)
        }
    }

    private func prefill(from day: ThrCheckInDay) {
        editing.stools   = day.stools.map(\.id)
        editing.symptoms = day.symptoms.map(\.id)
        editing.moods    = day.moods.map(\.id)
        editing.metrics  = day.metrics.map(\.id)
        editing.notes    = day.notes.map(\.id)

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
        let mealMode = context == .thriveCheckin ? "thrive" : "survive"
        guard let rows: [MealRow] = try? await repo.select(
            "meals", columns: "id,mode,photo_url,captured_at,confirmed,user_annotation,photo_expires_at",
            filters: ["captured_at": "gte.\(ThrDates.timestampString(dayStart))",
                      "confirmed": "eq.true", "mode": "eq.\(mealMode)"], order: "captured_at.asc"
        ) else { return }
        meals = rows.filter { ($0.capturedAtDate ?? dayStart) < dayEnd }
                    .enumerated().map { ThrTodayMeal.make($0.element, index: $0.offset + 1) }
    }

    private func save() async {
        guard let repo = appState.repository, let uid = appState.profile?.id else { dismiss(); return }
        isSaving = true
        defer { isSaving = false }
        if case .edit = mode { await deleteEditingRows(repo) }   // replace-in-place
        try? await CheckInWriter(repository: repo, userId: uid).save(draft)
        if context == .thriveCheckin {
            await upsertDailyAggregate(repo, uid: uid)           // keep "Is it working?" trends fed
        }
        await onSaved?()                                         // mode-specific refresh (Survive)
        onDone()
        dismiss()
    }

    /// Mirrors the day's mood/energy/clarity into thrive_checkins so the trends
    /// dashboard (which reads the scalar table) keeps getting points.
    private func upsertDailyAggregate(_ repo: Repository, uid: String) async {
        func avg(_ xs: [Int]) -> Int? { xs.isEmpty ? nil : Int((Double(xs.reduce(0, +)) / Double(xs.count)).rounded()) }
        let mood = avg(draft.moods.filter { $0.uiValue >= 1 }.map(\.storedScore))
        let energy = avg(draft.energy.filter { $0.score >= 1 }.map(\.score))
        let clarity = avg(draft.clarity.filter { $0.score >= 1 }.map(\.score))
        var body: [String: PGValue] = ["user_id": .string(uid), "log_date": .string(ThrDates.dateString(draft.logDate))]
        if let mood { body["mood"] = .int(mood) }
        if let energy { body["energy"] = .int(energy) }
        if let clarity { body["clarity"] = .int(clarity) }
        guard body.count > 2 else { return }
        try? await repo.upsert("thrive_checkins", body, onConflict: "user_id,log_date")
    }

    private func deleteEditingRows(_ repo: Repository) async {
        async let a: Void = delete(repo, "stool_entries", editing.stools)
        async let b: Void = delete(repo, "symptom_entries", editing.symptoms)
        async let c: Void = delete(repo, "mood_entries", editing.moods)
        async let d: Void = delete(repo, "metric_entries", editing.metrics)
        async let e: Void = delete(repo, "checkin_notes", editing.notes)
        _ = await (a, b, c, d, e)
    }

    private func delete(_ repo: Repository, _ table: String, _ ids: [String]) async {
        guard !ids.isEmpty else { return }
        let list = ids.joined(separator: ",")
        try? await repo.delete(table, filters: ["id": "in.(\(list))"])
    }
}

/// DB row ids loaded for an edit, deleted-and-reinserted on save (replace-in-place,
/// so it never touches rows the form didn't load, e.g. a same-day Survive entry).
struct ThrEditingIds {
    var stools: [String] = []
    var symptoms: [String] = []
    var moods: [String] = []
    var metrics: [String] = []
    var notes: [String] = []
}

// MARK: - History model

struct ThrCheckInDay: Identifiable, Sendable {
    let id: String           // log_date "yyyy-MM-dd"
    let date: Date
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
        let f = ["user_id": "eq.\(uid)"]
        async let st: [StoolEntryRow]   = (try? await repo.select("stool_entries",   filters: f, order: "log_date.desc", limit: 500)) ?? []
        async let sy: [SymptomEntryRow] = (try? await repo.select("symptom_entries", filters: f, order: "log_date.desc", limit: 500)) ?? []
        async let mo: [MoodEntryRow]    = (try? await repo.select("mood_entries",    filters: f, order: "log_date.desc", limit: 500)) ?? []
        async let mt: [MetricEntryRow]  = (try? await repo.select("metric_entries",  filters: f, order: "log_date.desc", limit: 500)) ?? []
        async let nt: [CheckinNoteRow]  = (try? await repo.select("checkin_notes",   filters: f, order: "log_date.desc", limit: 500)) ?? []
        let (stools, symptoms, moods, metrics, notes) = await (st, sy, mo, mt, nt)

        var map: [String: ThrCheckInDay] = [:]
        func ensure(_ d: String) -> ThrCheckInDay {
            map[d] ?? ThrCheckInDay(id: d, date: Self.dayParser.date(from: d) ?? Date())
        }
        for r in stools   { var x = ensure(r.logDate); x.stools.append(r);   map[r.logDate] = x }
        for r in symptoms { var x = ensure(r.logDate); x.symptoms.append(r); map[r.logDate] = x }
        for r in moods    { var x = ensure(r.logDate); x.moods.append(r);    map[r.logDate] = x }
        for r in metrics  { var x = ensure(r.logDate); x.metrics.append(r);  map[r.logDate] = x }
        for r in notes    { var x = ensure(r.logDate); x.notes.append(r);    map[r.logDate] = x }
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

/// A logged meal for the tie-to-photo control. Label is derived client-side; the
/// DB records which meal + the derived occurred_at, the UI never names the meal.
struct ThrTodayMeal: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let capturedAt: Date

    static func make(_ meal: MealRow, index: Int) -> ThrTodayMeal {
        let label = (meal.userAnnotation.map { !$0.isEmpty } ?? false) ? "After \(meal.userAnnotation!)" : "Meal \(index)"
        return ThrTodayMeal(id: meal.id, label: label, capturedAt: meal.capturedAtDate ?? Date())
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

#if DEBUG
#Preview("Thrive check-in tab") {
    ThrTestTabView(appState: AppState(auth: AuthService()))
        .themed(for: .thrive)
}
#endif
