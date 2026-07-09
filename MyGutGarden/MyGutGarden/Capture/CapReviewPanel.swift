//
//  CapReviewPanel.swift
//  MyGutGarden, Module B — the result-screen review (owner shape, 2026-07-09):
//  a COMPACT header card ("2 plants spotted — tap to edit") opens a pop-up
//  holding the full editor: per-item rows with the model's hand-anchored
//  measure ("~a fist · ~120g") and a ½×–2× slider, inline resolution for
//  unmatched names, add-a-food, photo delete (Fence 5 — this sheet is the
//  photo's ONLY delete surface), and a one-tap "Looks right." The old
//  standalone "Edit this meal" sheet is retired; this replaces it.
//
//  Every interaction is logged to `recognition_feedback` — the accuracy ledger
//  that doubles as the owner's is-it-working metric, the eval set for vision-
//  model changes, and the label source for a future custom model. Numbers stay
//  "~" softened (directional, rule #3); composition math mirrors the DB
//  trigger via PortionMath so the live total agrees with what persists.
//

import SwiftUI
import Observation

// MARK: - Model

@MainActor
@Observable
final class CapReviewModel {

    /// One recognized (matched) item under review.
    struct Row: Identifiable, Sendable {
        let rowID = UUID()
        let foodId: String
        let name: String                 // catalogue canonical name
        let visionName: String?          // what the model called it (feedback provenance)
        let source: CapItemSource
        let isPlant: Bool
        let baseGrams: Double?           // the model's estimate — the slider's 1× anchor
        let typicalServingG: Double?
        let fiberPerServingG: Double
        let householdMeasure: String?
        var portionTier: PortionTier
        var multiplier: Double = 1.0     // slider ½×–2×
        var expanded = false

        var id: UUID { rowID }

        /// Current grams under the slider (anchor × multiplier); nil when the
        /// food has neither a model estimate nor a serving anchor.
        var gramsNow: Double? { (baseGrams ?? typicalServingG).map { $0 * multiplier } }

        /// Portion ratio for live math — same rules as the DB trigger.
        var ratio: Double {
            if let grams = gramsNow, let typical = typicalServingG, typical > 0 {
                return PortionMath.ratio(estGrams: grams, typicalServingG: typical, tier: portionTier)
            }
            return PortionMath.ratio(estGrams: nil, typicalServingG: nil, tier: portionTier) * multiplier
        }

        var estFiberNowG: Double { fiberPerServingG * ratio }

        /// The persistable item. Grams carry the truth; the coarse tier shadows
        /// the ratio so v1 readers of `portion_tier` stay meaningful.
        var mealItem: CapMealItem {
            CapMealItem(foodId: foodId,
                        portion: PortionMath.tier(forRatio: ratio),
                        source: source,
                        estGrams: gramsNow.map { ($0 * 10).rounded() / 10 },
                        householdMeasure: householdMeasure)
        }
    }

    /// A vision name the catalogue couldn't resolve ("new to us"). While the
    /// librarian is generating its profile, `pending` shows "Adding it to the
    /// garden…"; a failed/skipped verdict falls back to manual "Pick a match."
    struct Unresolved: Identifiable, Sendable {
        let visionName: String
        var pending = false
        var id: String { visionName }
    }

    private(set) var rows: [Row] = []
    private(set) var unresolved: [Unresolved] = []
    private(set) var looksRightSent = false
    private(set) var isSaving = false
    /// Fence 5: photos are permanent-but-deletable, and this sheet is the
    /// delete surface. `hadPhoto` remembers one existed even after removal.
    private(set) var hadPhoto = false
    private(set) var photoRemoved = false
    var errorText: String?

    private let repository: Repository?
    private let userId: String?
    private let mealId: String?

    init(response: RecognitionResponse, annotationFoodIds: Set<String>,
         photoURL: String?,
         repository: Repository?, userId: String?, mealId: String?) {
        self.repository = repository
        self.userId = userId
        self.mealId = mealId
        self.hadPhoto = photoURL != nil

        rows = response.items.compactMap { item in
            guard let attrs = item.attributes else { return nil }
            return Row(
                foodId: attrs.foodId,
                name: attrs.canonicalName,
                visionName: item.vision.name,
                source: annotationFoodIds.contains(attrs.foodId) ? .annotation : .vision,
                isPlant: attrs.isPlant,
                baseGrams: item.vision.estGrams,
                typicalServingG: attrs.typicalServingG,
                fiberPerServingG: attrs.fiberPerServingG,
                householdMeasure: item.vision.householdMeasure,
                portionTier: item.vision.portionTier
            )
        }
        unresolved = response.unmatched.map { Unresolved(visionName: $0) }
        // The camera's quantity estimates for unmatched names, kept so a
        // librarian-healed row keeps its grams.
        unmatchedVision = Dictionary(
            response.items.filter { $0.attributes == nil }.map { ($0.vision.name, $0.vision) },
            uniquingKeysWith: { a, _ in a })
    }

    private var unmatchedVision: [String: VisionFood] = [:]

    // MARK: Derived

    var plantCount: Int { Set(rows.filter(\.isPlant).map(\.foodId)).count }
    var mealFiberG: Double { rows.reduce(0) { $0 + $1.estFiberNowG } }
    var canPersist: Bool { repository != nil && userId != nil && mealId != nil }

    // MARK: Interactions

    func toggleExpanded(_ row: Row) {
        guard let idx = rows.firstIndex(where: { $0.rowID == row.rowID }) else { return }
        rows[idx].expanded.toggle()
    }

    /// Live slider movement — no persistence until the drag ends.
    func setMultiplier(_ row: Row, _ value: Double) {
        guard let idx = rows.firstIndex(where: { $0.rowID == row.rowID }) else { return }
        rows[idx].multiplier = value
    }

    /// Drag ended: persist the new amount + log the correction.
    func commitMultiplier(_ row: Row) {
        guard let idx = rows.firstIndex(where: { $0.rowID == row.rowID }) else { return }
        let r = rows[idx]
        guard r.multiplier != 1.0 else { return }
        persistItems()
        log("portion_changed", foodId: r.foodId, visionName: r.visionName, detail: [
            "multiplier": r.multiplier,
            "from_grams": r.baseGrams ?? r.typicalServingG ?? 0,
            "to_grams": r.gramsNow ?? 0
        ])
    }

    func remove(_ row: Row) {
        guard let idx = rows.firstIndex(where: { $0.rowID == row.rowID }) else { return }
        let r = rows.remove(at: idx)
        persistItems()
        log("item_removed", foodId: r.foodId, visionName: r.visionName)
    }

    /// "Add a food" — the model missed it entirely.
    func add(_ food: CapFoodSearchResult) async {
        await appendRow(for: food, source: .manual, visionName: nil)
        persistItems()
        log("item_added", foodId: food.id)
    }

    /// Map a "new to us" vision name onto a catalogue food.
    func resolve(_ item: Unresolved, with food: CapFoodSearchResult) async {
        unresolved.removeAll { $0.visionName == item.visionName }
        await appendRow(for: food, source: .manual, visionName: item.visionName)
        persistItems()
        log("unmatched_resolved", foodId: food.id, visionName: item.visionName)
    }

    // MARK: The librarian (SPEC §4 Coverage — unknown foods heal themselves)

    /// Mark every unresolved name as in-generation ("Adding it to the garden…").
    func markLibrarianPending() {
        for idx in unresolved.indices { unresolved[idx].pending = true }
    }

    /// Fold the librarian's verdicts in: healed names become editable rows
    /// (the server already linked the meal_item, so no persist here); failures
    /// fall back to the manual "Pick a match" flow. Names the response didn't
    /// cover (or a failed call, results == []) also drop back to manual.
    func applyLibrarianResults(_ results: [CapLibrarianResult]) {
        for result in results {
            guard let idx = unresolved.firstIndex(where: { $0.visionName == result.name }) else { continue }
            guard let food = result.food,
                  ["added", "alias", "linked"].contains(result.status) else {
                unresolved[idx].pending = false
                continue
            }
            let vision = unmatchedVision[result.name]
            unresolved.remove(at: idx)
            guard !rows.contains(where: { $0.foodId == food.id }) else { continue }
            rows.append(Row(
                foodId: food.id,
                name: food.canonicalName,
                visionName: result.name,
                source: .librarian,
                isPlant: food.isPlant,
                baseGrams: vision?.estGrams,
                typicalServingG: food.typicalServingG,
                fiberPerServingG: food.fiberPerServingG ?? 0,
                householdMeasure: vision?.householdMeasure,
                portionTier: vision?.portionTier ?? .serving
            ))
        }
        for idx in unresolved.indices { unresolved[idx].pending = false }
    }

    /// One-tap positive label for the whole scan.
    func confirmLooksRight() {
        guard !looksRightSent else { return }
        looksRightSent = true
        log("looks_right", detail: ["foods": rows.count, "unmatched": unresolved.count])
    }

    func searchFoods(_ term: String) async -> [CapFoodSearchResult] {
        guard let repository else { return [] }
        return (try? await CapFoodSearchService(repository: repository).search(term)) ?? []
    }

    /// Delete the meal's photo (privacy, Fence 5). Food data stays.
    func deletePhoto() async {
        guard let repository, let userId, let mealId else { return }
        do {
            try await CapMealPersistence(repository: repository, userId: userId)
                .deletePhoto(mealId: mealId)
            photoRemoved = true
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: IO

    /// Fetch the picked food's math anchors so the new row joins the live total.
    private func appendRow(for food: CapFoodSearchResult, source: CapItemSource,
                           visionName: String?) async {
        guard !rows.contains(where: { $0.foodId == food.id }) else { return }
        struct AnchorRow: Decodable, Sendable {
            struct Fiber: Decodable, Sendable { let estGramsPerServing: Double? }
            let id: String
            let isPlant: Bool
            let typicalServingG: Double?
            let foodFibers: [Fiber]?
        }
        var anchor: AnchorRow?
        if let repository {
            let fetched: [AnchorRow]? = try? await repository.select(
                "foods", columns: "id,is_plant,typical_serving_g,food_fibers(est_grams_per_serving)",
                filters: ["id": "eq.\(food.id)"], limit: 1)
            anchor = fetched?.first
        }
        rows.append(Row(
            foodId: food.id,
            name: food.canonicalName,
            visionName: visionName,
            source: source,
            isPlant: anchor?.isPlant ?? true,
            baseGrams: nil,                              // user-added: anchor on the typical serving
            typicalServingG: anchor?.typicalServingG,
            fiberPerServingG: anchor?.foodFibers?.compactMap(\.estGramsPerServing).reduce(0, +) ?? 0,
            householdMeasure: nil,
            portionTier: .serving
        ))
    }

    /// Replace the meal's items wholesale (same path the edit sheet uses).
    private func persistItems() {
        guard let repository, let userId, let mealId else { return }
        let items = rows.map(\.mealItem)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await CapMealPersistence(repository: repository, userId: userId)
                    .updateItems(mealId: mealId, items: items)
                errorText = nil
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func log(_ event: String, foodId: String? = nil,
                     visionName: String? = nil, detail: [String: Any]? = nil) {
        guard let repository, let userId else { return }
        let logger = CapFeedbackLog(repository: repository, userId: userId, mealId: mealId)
        Task { await logger.log(event, foodId: foodId, visionName: visionName, detail: detail) }
    }
}

// MARK: - Compact summary card (the result screen's header; taps into the editor)

struct CapReviewSummaryCard: View {
    @Environment(\.theme) private var theme
    let model: CapReviewModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Card {
                HStack(spacing: theme.metrics.space3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.plantCount == 1 ? "1 plant spotted" : "\(model.plantCount) plants spotted")
                            .font(theme.typography.title(20))
                            .foregroundStyle(theme.colors.textPrimary)
                        Text(subtitle)
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.primary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.plantCount) plants spotted. \(subtitle)")
        .accessibilityHint("Opens the meal editor")
    }

    private var subtitle: String {
        var parts = ["~\(Int(model.mealFiberG.rounded()))g fiber"]
        if !model.unresolved.isEmpty {
            parts.append(model.unresolved.count == 1 ? "1 new to us" : "\(model.unresolved.count) new to us")
        }
        parts.append("tap to edit")
        return parts.joined(separator: " · ")
    }
}

// MARK: - The editor pop-up (sheet)

struct CapReviewSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CapReviewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    CapReviewPanel(model: model)
                    photoRow
                }
                .padding(theme.metrics.space5)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Your meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Fence 5: this sheet is the photo's delete surface (photos are otherwise
    /// permanent, private, disclosed).
    @ViewBuilder
    private var photoRow: some View {
        if model.hadPhoto, model.canPersist {
            Card {
                HStack(spacing: theme.metrics.space3) {
                    Image(systemName: model.photoRemoved ? "photo.badge.exclamationmark" : "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.colors.textSecondary)
                    Text(model.photoRemoved ? "Photo removed" : "Photo saved to your private log")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                    Spacer()
                    if !model.photoRemoved {
                        Button(role: .destructive) {
                            Task { await model.deletePhoto() }
                        } label: {
                            Text("Delete photo")
                                .font(theme.typography.caption(weight: .semibold))
                        }
                        .foregroundStyle(theme.colors.error)
                    }
                }
            }
        }
    }
}

// MARK: - The full editor panel (lives inside the sheet)

struct CapReviewPanel: View {
    @Environment(\.theme) private var theme
    @Bindable var model: CapReviewModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                header
                ForEach(model.rows) { row in
                    CapReviewRowView(model: model, row: row)
                    if row.id != model.rows.last?.id || !model.unresolved.isEmpty {
                        Divider().overlay(theme.colors.divider)
                    }
                }
                ForEach(model.unresolved) { item in
                    CapUnresolvedRowView(model: model, item: item)
                    if item.id != model.unresolved.last?.id {
                        Divider().overlay(theme.colors.divider)
                    }
                }
                CapReviewAddRow(model: model)
                footer
                if let error = model.errorText {
                    Text(error)
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.error)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space1) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.plantCount == 1 ? "1 plant spotted" : "\(model.plantCount) plants spotted")
                    .font(theme.typography.title(20))
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Text("~\(Int(model.mealFiberG.rounded()))g fiber")
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.secondary)
                    .accessibilityLabel("About \(Int(model.mealFiberG.rounded())) grams of fiber in this meal")
            }
            Text("Tap anything that's off — fixing it teaches your garden.")
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var footer: some View {
        Button {
            model.confirmLooksRight()
        } label: {
            HStack(spacing: theme.metrics.space2) {
                Image(systemName: model.looksRightSent ? "checkmark.circle.fill" : "checkmark.circle")
                Text(model.looksRightSent ? "Thanks — noted!" : "Looks right")
                    .font(theme.typography.body(weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.metrics.space2)
        }
        .foregroundStyle(model.looksRightSent ? theme.colors.textSecondary : theme.colors.primary)
        .background(theme.colors.primary.opacity(model.looksRightSent ? 0.06 : 0.12),
                    in: RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
        .disabled(model.looksRightSent)
        .accessibilityLabel(model.looksRightSent ? "Marked as looking right" : "Confirm the scan looks right")
    }
}

// MARK: - One matched row (tap → ½×–2× amount slider)

private struct CapReviewRowView: View {
    @Environment(\.theme) private var theme
    let model: CapReviewModel
    let row: CapReviewModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Button { model.toggleExpanded(row) } label: {
                HStack(spacing: theme.metrics.space2) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: theme.metrics.space1) {
                            Text(row.name)
                                .font(theme.typography.body(weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                            if row.isPlant {
                                Image(systemName: "leaf.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.colors.primary)
                                    .accessibilityLabel("Counts as a plant")
                            }
                        }
                        Text(amountText)
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: row.expanded ? "chevron.up" : "slider.horizontal.3")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.name), \(amountText). Tap to adjust the amount.")

            if row.expanded { slider }
        }
    }

    /// "~a fist · ~120g", falling back to the coarse tier label when the food
    /// has no gram anchor. Always "~" — directional, never measured (rule #3).
    private var amountText: String {
        var parts: [String] = []
        if let measure = row.householdMeasure { parts.append("~\(measure)") }
        if let grams = row.gramsNow { parts.append("~\(Int(grams.rounded()))g") }
        if parts.isEmpty { parts.append(CapPortion.label(row.portionTier)) }
        if row.multiplier != 1.0 {
            parts.append("adjusted")
        }
        return parts.joined(separator: " · ")
    }

    private var slider: some View {
        HStack(spacing: theme.metrics.space3) {
            Text("½×")
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
            Slider(
                value: Binding(get: { row.multiplier },
                               set: { model.setMultiplier(row, $0) }),
                in: 0.5...2.0,
                step: 0.25
            ) { editing in
                if !editing { model.commitMultiplier(row) }
            }
            .tint(theme.colors.primary)
            .accessibilityLabel("Amount of \(row.name)")
            .accessibilityValue(row.gramsNow.map { "about \(Int($0.rounded())) grams" }
                                ?? CapPortion.label(row.portionTier))
            Text("2×")
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
            Button { model.remove(row) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.colors.error)
            }
            .accessibilityLabel("Remove \(row.name) — it wasn't in this meal")
        }
    }
}

// MARK: - One unmatched row ("new to us" → pick a match inline)

private struct CapUnresolvedRowView: View {
    @Environment(\.theme) private var theme
    let model: CapReviewModel
    let item: CapReviewModel.Unresolved

    @State private var searching = false
    @State private var term = ""
    @State private var results: [CapFoodSearchResult] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            HStack(spacing: theme.metrics.space2) {
                Image(systemName: item.pending ? "sparkles" : "questionmark.circle")
                    .foregroundStyle(theme.colors.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.visionName)
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(item.pending ? "New to us — adding it to the garden…"
                                      : "Spotted, but new to us — not counted yet.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Spacer()
                if item.pending {
                    ProgressView()
                } else {
                    Button { searching.toggle() } label: {
                        Text(searching ? "Close" : "Pick a match")
                            .font(theme.typography.caption(weight: .semibold))
                            .foregroundStyle(theme.colors.primary)
                    }
                    .accessibilityLabel("Pick a catalogue match for \(item.visionName)")
                }
            }
            if searching {
                TextField("Search foods", text: $term)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: term) { _, newValue in search(newValue) }
                    .onAppear { term = item.visionName; search(item.visionName) }
                ForEach(results) { result in
                    Button {
                        Task { await model.resolve(item, with: result) }
                    } label: {
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
                    .accessibilityLabel("Log \(item.visionName) as \(result.canonicalName)")
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
}

// MARK: - "Add a food" row (the model missed it entirely)

private struct CapReviewAddRow: View {
    @Environment(\.theme) private var theme
    let model: CapReviewModel

    @State private var adding = false
    @State private var term = ""
    @State private var results: [CapFoodSearchResult] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Button { adding.toggle() } label: {
                HStack(spacing: theme.metrics.space2) {
                    Image(systemName: adding ? "minus.circle" : "plus.circle")
                    Text(adding ? "Never mind" : "Add a food we missed")
                        .font(theme.typography.body(weight: .medium))
                }
                .foregroundStyle(theme.colors.primary)
            }
            .accessibilityLabel(adding ? "Close the add-a-food search" : "Add a food the scan missed")
            if adding {
                TextField("Search foods", text: $term)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: term) { _, newValue in search(newValue) }
                ForEach(results) { result in
                    Button {
                        Task { await model.add(result) }
                        adding = false
                        term = ""
                        results = []
                    } label: {
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
                    .accessibilityLabel("Add \(result.canonicalName) to this meal")
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
}
