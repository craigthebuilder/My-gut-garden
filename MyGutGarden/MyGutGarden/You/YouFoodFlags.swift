//
//  YouFoodFlags.swift
//  MyGutGarden — the food-flags management surface in the You section (SPEC §9).
//
//  The user's own list of foods they (or the quiet guardian) are keeping an eye on,
//  across the three tiers. Investigation, never accusation: neutral counts, no
//  severity/score/meter (rule #7). Allergy is clear + serious; sensitivity is a
//  gentle "on your list"; watching is quietly monitored. The user authors every
//  change here — this is where they confirm, relax, or remove a flag.
//

import SwiftUI
import Observation

struct YouFoodNameRow: Decodable, Sendable, Identifiable { let id: String; let canonicalName: String }

/// A resolved flag for display.
struct YouFlag: Identifiable, Sendable {
    let id: String
    let foodId: String?
    let name: String
    var tier: FlagTier
    let engineSuggested: Bool     // source='engine' && !confirmed → a "worth a look?" suggestion
}

extension FlagTier {
    var youTitle: String {
        switch self {
        case .watching:    "Keeping an eye on"
        case .sensitivity: "Doesn't always sit well"
        case .allergy:     "Allergies"
        }
    }
    var youBlurb: String {
        switch self {
        case .watching:    "We're quietly watching how these sit. Nothing's off-limits."
        case .sensitivity: "Foods you've noticed don't always agree with you. Still yours to eat — we just flag them gently."
        case .allergy:     "Always flagged, loudly, before anything else. You control this list."
        }
    }
}

@MainActor
@Observable
final class YouFoodFlagsModel {
    var flags: [YouFlag] = []
    var isLoading = false
    private var foodNames: [String: String] = [:]

    func load(_ appState: AppState) async {
        guard let repo = appState.repository else { return }
        isLoading = true
        defer { isLoading = false }
        async let flagRowsT = repo.fetchFoodFlags()
        async let foodsT: [YouFoodNameRow] = repo.select("foods", columns: "id,canonical_name")
        let flagRows = (try? await flagRowsT) ?? []
        let foods = (try? await foodsT) ?? []
        foodNames = Dictionary(foods.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { a, _ in a })
        flags = flagRows.compactMap { r in
            guard let tier = FlagTier(rawValue: r.flagTier) else { return nil }
            // Category flags store a key like "tree_nut" — show a readable label.
            let name = r.foodId.flatMap { foodNames[$0] }
                ?? r.category.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
                ?? "Food"
            return YouFlag(id: r.id, foodId: r.foodId, name: name, tier: tier,
                           engineSuggested: r.source == "engine" && !r.userConfirmed)
        }.sorted { $0.name < $1.name }
    }

    func flags(_ tier: FlagTier) -> [YouFlag] { flags.filter { $0.tier == tier } }

    func setTier(_ flag: YouFlag, to tier: FlagTier, appState: AppState) async {
        guard let repo = appState.repository else { return }
        try? await repo.update("food_flags",
            set: ["flag_tier": .string(tier.rawValue), "user_confirmed": .bool(true), "updated_at": .date(Date())],
            filters: ["id": "eq.\(flag.id)"])
        await load(appState)
    }

    func confirm(_ flag: YouFlag, appState: AppState) async {
        guard let repo = appState.repository else { return }
        try? await repo.update("food_flags",
            set: ["user_confirmed": .bool(true), "updated_at": .date(Date())],
            filters: ["id": "eq.\(flag.id)"])
        await load(appState)
    }

    func remove(_ flag: YouFlag, appState: AppState) async {
        guard let repo = appState.repository else { return }
        try? await repo.delete("food_flags", filters: ["id": "eq.\(flag.id)"])
        await load(appState)
    }

    func add(foodId: String, tier: FlagTier, appState: AppState) async {
        guard let repo = appState.repository, let uid = appState.profile?.id else { return }
        try? await repo.upsert("food_flags",
            ["user_id": .string(uid), "food_id": .string(foodId), "flag_tier": .string(tier.rawValue),
             "source": .string("user"), "user_confirmed": .bool(true), "updated_at": .date(Date())],
            onConflict: "user_id,food_id")
        await load(appState)
    }

    func search(_ q: String, appState: AppState) async -> [YouFoodNameRow] {
        let query = q.trimmingCharacters(in: .whitespaces)
        guard let repo = appState.repository, query.count >= 2 else { return [] }
        return (try? await repo.select("foods", columns: "id,canonical_name",
            filters: ["canonical_name": "ilike.*\(query)*"], order: "canonical_name", limit: 20)) ?? []
    }
}

struct YouFoodFlagsView: View {
    @Environment(\.theme) private var theme
    let appState: AppState

    @State private var model = YouFoodFlagsModel()
    @State private var adding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space5) {
                    if model.flags.isEmpty && !model.isLoading {
                        emptyState
                    } else {
                        ForEach(FlagTier.allCasesOrdered, id: \.self) { tier in
                            let items = model.flags(tier)
                            if !items.isEmpty { tierSection(tier, items) }
                        }
                    }
                }
                .padding(theme.metrics.space4)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Your foods")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add a food to keep an eye on")
                }
            }
        }
        .task { await model.load(appState) }
        .sheet(isPresented: $adding) {
            YouAddFlagSheet(appState: appState, model: model) { adding = false }
        }
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Text("Nothing on your list")
                    .font(theme.typography.body(weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Add a food you want to keep an eye on, or let the guardian quietly suggest one. You're in charge of this list.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tierSection(_ tier: FlagTier, _ items: [YouFlag]) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text("\(tier.youTitle) · \(items.count)")
                .font(theme.typography.title(20))
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(tier.youBlurb)
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(items) { flag in flagRow(flag) }
        }
    }

    private func flagRow(_ flag: YouFlag) -> some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                HStack {
                    Text(flag.name)
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(flag.tier == .allergy ? theme.colors.error : theme.colors.textPrimary)
                    if flag.engineSuggested {
                        Text("worth a look?")
                            .font(theme.typography.caption(weight: .semibold))
                            .foregroundStyle(theme.colors.warning)
                    }
                    Spacer()
                    Menu {
                        if flag.engineSuggested {
                            Button("Yes, keep an eye on it") { Task { await model.confirm(flag, appState: appState) } }
                        }
                        ForEach(FlagTier.allCasesOrdered, id: \.self) { t in
                            if t != flag.tier {
                                Button("Move to \(t.youTitle.lowercased())") { Task { await model.setTier(flag, to: t, appState: appState) } }
                            }
                        }
                        Button("Bring it back (remove)", role: .destructive) { Task { await model.remove(flag, appState: appState) } }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(theme.colors.textSecondary)
                    }
                    .accessibilityLabel("Options for \(flag.name)")
                }
            }
        }
    }
}

/// Add-a-food sheet: search the foods list, then pick a tier.
struct YouAddFlagSheet: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    let model: YouFoodFlagsModel
    let onDone: () -> Void

    @State private var query = ""
    @State private var results: [YouFoodNameRow] = []
    @State private var picked: YouFoodNameRow?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    TextField("Search foods", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, q in Task { results = await model.search(q, appState: appState) } }

                    if let picked {
                        Card {
                            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                                Text("How does \(picked.canonicalName) sit with you?")
                                    .font(theme.typography.body(weight: .semibold))
                                    .foregroundStyle(theme.colors.textPrimary)
                                tierButton(.watching, "Keep an eye on it", picked)
                                tierButton(.sensitivity, "It doesn't always agree with me", picked)
                                tierButton(.allergy, "I'm allergic to it", picked)
                            }
                        }
                    }

                    ForEach(results) { food in
                        Button { picked = food } label: {
                            HStack {
                                Text(food.canonicalName).foregroundStyle(theme.colors.textPrimary)
                                Spacer()
                                if picked?.id == food.id { Image(systemName: "checkmark").foregroundStyle(theme.colors.primary) }
                            }
                            .font(theme.typography.body())
                            .padding(theme.metrics.space3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(theme.metrics.space4)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Add a food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: onDone) } }
        }
    }

    private func tierButton(_ tier: FlagTier, _ label: String, _ food: YouFoodNameRow) -> some View {
        Button {
            Task { await model.add(foodId: food.id, tier: tier, appState: appState); onDone() }
        } label: {
            Text(label)
                .font(theme.typography.body(weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, theme.metrics.space3)
                .foregroundStyle(tier == .allergy ? theme.colors.surface : theme.colors.textPrimary)
                .background(tier == .allergy ? theme.colors.error : theme.colors.background)
                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension FlagTier {
    /// Display order: watching → sensitivity → allergy.
    static var allCasesOrdered: [FlagTier] { [.watching, .sensitivity, .allergy] }
}
