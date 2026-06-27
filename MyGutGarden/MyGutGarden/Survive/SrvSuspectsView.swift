//
//  SrvSuspectsView.swift
//  MyGutGarden, Module E. The "Lab Notebook" food surface (Batch E).
//
//  Four tabs over ONE `food_suspects` table: Suspects / Re-intro / Timeline /
//  Avoid. The user is the scientist, the app is the notebook. Investigation, never
//  accusation: the app only SUGGESTS (dismissibly), the user authors every commit.
//  NO severity, NO ranked "worst foods", NO accumulating meter (rules #1/#4/#7).
//

import SwiftUI

// MARK: - Four-tab container

struct SrvFoodSurfaceView: View {
    @Environment(\.theme) private var theme
    @Bindable var foodStore: FoodStatusStore
    @State private var tab: SrvFoodTab = .suspects

    enum SrvFoodTab: String, CaseIterable, Identifiable {
        case suspects = "Checking"
        case reintro = "Re-intro"
        case timeline = "Timeline"
        case avoid = "On pause"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(SrvFoodTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(theme.metrics.space4)

            switch tab {
            case .suspects: SrvSuspectsTab(foodStore: foodStore)
            case .reintro: SrvReintroView(foodStore: foodStore)
            case .timeline: SrvTimelineView(foodStore: foodStore)
            case .avoid: SrvAvoidView(foodStore: foodStore)
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Your foods")
        .navigationBarTitleDisplayMode(.inline)
        .task { await foodStore.load() }
    }
}

// MARK: - Suspects tab

struct SrvSuspectsTab: View {
    @Environment(\.theme) private var theme
    @Bindable var foodStore: FoodStatusStore

    @State private var query = ""
    @State private var results: [FoodStatusStore.FoodSearchHit] = []
    @State private var allergyBlockName: String?
    @State private var pendingStart: FoodSuspectRow?

    /// The "Foods you're checking" list excludes still-pending system suggestions
    /// (those live in the dismissible tray). Neutral count, never a meter.
    private var confirmedChecking: [FoodSuspectRow] {
        foodStore.checking().filter { !($0.addedBy == "system" && $0.userVerdict == nil) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                searchCard
                if let name = allergyBlockName { allergyBanner(name) }
                suggestionTray
                checkingList
            }
            .padding(theme.metrics.space4)
        }
    }

    // MARK: Search + add

    private var searchCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                Text("Add a food you want to keep an eye on. You're in charge of this list.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
                TextField("Search foods", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: query) { _, q in
                        Task { results = await foodStore.searchFoods(q) }
                    }
                ForEach(results) { hit in
                    Button {
                        addFood(hit)
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text(hit.canonicalName).font(theme.typography.body())
                            Spacer()
                        }
                        .foregroundStyle(theme.colors.primary)
                        .padding(.vertical, theme.metrics.space1)
                    }
                    .accessibilityLabel("Add \(hit.canonicalName)")
                }
            }
        }
    }

    private func addFood(_ hit: FoodStatusStore.FoodSearchHit) {
        // ALLERGY BLOCK (rule #1): an allergy stays LOUD, a confirm/deny flow would
        // falsely imply uncertainty, so it can never become a suspect.
        if foodStore.isMedicalAllergy(hit.id) {
            allergyBlockName = hit.canonicalName
            return
        }
        allergyBlockName = nil
        query = ""
        results = []
        Task { await foodStore.addSuspect(foodId: hit.id) }
    }

    private func allergyBanner(_ name: String) -> some View {
        Card {
            HStack(spacing: theme.metrics.space2) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(theme.colors.error)
                Text("\(name) is already flagged as an allergy, it stays loud. No need to track it here.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    // MARK: Suggestion tray (dismissible system proposals)

    @ViewBuilder private var suggestionTray: some View {
        let suggestions = foodStore.suggested()
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "Worth a look?")
                ForEach(suggestions, id: \.id) { s in
                    Card {
                        VStack(alignment: .leading, spacing: theme.metrics.space3) {
                            Text("You've noted not feeling great after a few meals with \(foodStore.foodName(s.foodId)). Want to keep an eye on it?")
                                .font(theme.typography.body())
                                .foregroundStyle(theme.colors.textPrimary)
                            HStack(spacing: theme.metrics.space2) {
                                PrimaryButton(title: "Yes, add it") {
                                    Task { await foodStore.confirmSuggestion(s) }
                                }
                                SecondaryButton(title: "Not now") {
                                    Task { await foodStore.denySuggestion(s) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Checking list

    @ViewBuilder private var checkingList: some View {
        let foods = confirmedChecking
        VStack(alignment: .leading, spacing: theme.metrics.space3) {
            SectionHeader(title: foods.isEmpty ? "Nothing on your list yet"
                          : "\(foods.count) \(foods.count == 1 ? "food" : "foods") you're checking")
            if foods.isEmpty {
                Text("When something doesn't sit right, add it above and watch how it goes.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
            }
            ForEach(foods, id: \.id) { s in
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space1) {
                        HStack(spacing: theme.metrics.space3) {
                            Image(systemName: "leaf").foregroundStyle(theme.colors.secondary)
                            Text(foodStore.foodName(s.foodId))
                                .font(theme.typography.body(weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                            Spacer()
                            Button("Re-intro") { startReintro(s) }
                                .font(theme.typography.caption(weight: .semibold))
                                .foregroundStyle(theme.colors.primary)
                            Button {
                                Task { await foodStore.removeSuspect(s) }
                            } label: {
                                Image(systemName: "xmark.circle").foregroundStyle(theme.colors.textSecondary)
                            }
                            .accessibilityLabel("Remove \(foodStore.foodName(s.foodId))")
                        }
                        if s.addedBy == "auto_reset_break" {
                            Text("Added automatically after a meal that didn't sit well. Remove it anytime.")
                                .font(theme.typography.caption())
                                .foregroundStyle(theme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .confirmationDialog("Start a new re-intro?",
                            isPresented: Binding(get: { pendingStart != nil }, set: { if !$0 { pendingStart = nil } }),
                            titleVisibility: .visible) {
            if let s = pendingStart {
                Button("End current challenge and start") {
                    Task { await foodStore.startChallenge(s); pendingStart = nil }
                }
            }
            Button("Keep current", role: .cancel) { pendingStart = nil }
        } message: {
            Text("You can ease one food back in at a time.")
        }
    }

    private func startReintro(_ s: FoodSuspectRow) {
        if foodStore.activeFoodChallenge != nil {
            pendingStart = s            // one-at-a-time guard
        } else {
            Task { await foodStore.startChallenge(s) }
        }
    }
}
