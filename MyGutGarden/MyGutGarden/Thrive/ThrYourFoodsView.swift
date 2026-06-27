//
//  ThrYourFoodsView.swift
//  MyGutGarden, Module C: the Thrive "Your foods" surface (Batch E, §11b model).
//
//  The SAME four-tab Suspects / Re-intro / Timeline / Avoid "lab notebook" the
//  Survive side shows, rendered on Thrive so a thriving user can quietly test one
//  or two "bad apple" foods. The model + engine live ONCE in Module E
//  (FoodStatusStore); Module C only READS/mutates through that shared store, never
//  importing a Survive view.
//
//  Invariants enforced here (load-bearing):
//   - Investigation, never accusation. The app only SUGGESTS; the user AUTHORS
//     every negative transition (confirm / set-aside). Neutral counts only, no
//     severity / score / "problem foods".
//   - The reintro bar is EVENT-DRIVEN (store.challengeProgressPct), one-at-a-time,
//     never a time countdown. A reintro CLEAR is a GAIN ("you can enjoy it again"),
//     never "you got through it".
//   - Adding a `medical_allergy` food as a suspect is BLOCKED (it stays loud).
//   - The "switch to Survive" route goes via pendingSurvivePrompt (handled by the
//     lead). Thrive NEVER reaches a reset directly.
//

import SwiftUI
import Observation

struct ThrYourFoodsView: View {
    @Environment(\.theme) private var theme
    let appState: AppState

    @State private var store: FoodStatusStore?
    @State private var tab: ThrFoodsTab = .suspects

    var body: some View {
        Group {
            if let store {
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.metrics.space4) {
                        ThrSegmentedTabs(selection: $tab)
                        switch tab {
                        case .suspects: ThrSuspectsTab(store: store)
                        case .reintro:  ThrReintroTab(store: store)
                        case .timeline: ThrTimelineTab(store: store)
                        case .avoid:    ThrAvoidTab(store: store)
                        }
                    }
                    .padding(theme.metrics.space5)
                }
                .background(theme.colors.background.ignoresSafeArea())
            } else {
                ThrEmptyState(icon: "list.bullet.clipboard",
                              title: "Sign in to track foods",
                              message: "Foods you choose to keep an eye on live with your account.")
            }
        }
        .navigationTitle("Your foods")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil, let repo = appState.repository, let uid = appState.profile?.id {
                let s = FoodStatusStore(repository: repo, userId: uid, appState: appState)
                await s.load()
                store = s
            }
        }
    }
}

enum ThrFoodsTab: String, CaseIterable, Identifiable {
    case suspects, reintro, timeline, avoid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .suspects: "Checking"
        case .reintro:  "Re-intro"
        case .timeline: "Timeline"
        case .avoid:    "On pause"
        }
    }
}

// MARK: - Suspects ("Checking") tab

struct ThrSuspectsTab: View {
    @Environment(\.theme) private var theme
    let store: FoodStatusStore

    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            // Move-to-Avoid OFFER (a question, never an app verdict).
            if let offer = store.shouldOfferAvoid() {
                ThrAvoidOfferCard(name: store.foodName(offer.foodId),
                                  onSetAside: { Task { await store.moveToAvoid(offer) } },
                                  onKeepChecking: { /* leave as a suspect; no silent parking */ })
            }

            // "Worth a look?" suggestions (added_by=system, dismissible).
            let suggestions = store.suggested()
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: theme.metrics.space2) {
                    Text("Worth a look?")
                        .font(theme.typography.title(20))
                        .foregroundStyle(theme.colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(suggestions, id: \.id) { s in
                        ThrSuggestionCard(name: store.foodName(s.foodId),
                                          onAdd: { Task { await store.confirmSuggestion(s) } },
                                          onDismiss: { Task { await store.denySuggestion(s) } })
                    }
                }
            }

            // Foods the user is actively checking. Neutral count only.
            let checking = store.checking()
            HStack {
                Text(checking.isEmpty ? "Foods you're checking"
                     : "\(checking.count) food\(checking.count == 1 ? "" : "s") you're checking")
                    .font(theme.typography.title(20))
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 22))
                        .foregroundStyle(theme.colors.primary)
                }
                .accessibilityLabel("Add a food to check")
            }

            if checking.isEmpty {
                Text("Add a food you want to keep an eye on. You're in charge of this list.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(checking, id: \.id) { s in
                    Card {
                        HStack(spacing: theme.metrics.space2) {
                            Text(store.foodName(s.foodId))
                                .font(theme.typography.body(weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                            Spacer()
                            Menu {
                                Button("Start re-intro") {
                                    Task { await store.startChallenge(s) }
                                }
                                Button("Remove from list", role: .destructive) {
                                    Task { await store.removeSuspect(s) }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.system(size: 20))
                                    .foregroundStyle(theme.colors.secondary)
                            }
                            .accessibilityLabel("Options for \(store.foodName(s.foodId))")
                        }
                    }
                }
                if store.activeFoodChallenge != nil {
                    Text("You're already testing a food. Finish that re-intro before starting another.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            ThrAddSuspectSheet(store: store)
        }
    }
}

/// A dismissible system suggestion. Investigation framing, never "trigger found".
struct ThrSuggestionCard: View {
    @Environment(\.theme) private var theme
    let name: String
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                Text("You've noted not feeling great after a few meals with \(name). Want to keep an eye on it?")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: theme.metrics.space2) {
                    PrimaryButton(title: "Yes, add it", action: onAdd)
                    SecondaryButton(title: "Not now", action: onDismiss)
                }
            }
        }
    }
}

/// The move-to-Avoid OFFER, fenced copy (// RD-REVIEW-REQUIRED Fence 1 wording).
struct ThrAvoidOfferCard: View {
    @Environment(\.theme) private var theme
    let name: String
    let onSetAside: () -> Void
    let onKeepChecking: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                // RD-REVIEW-REQUIRED (Fence 1): never "cannot tolerate".
                Text("Everyone's gut is different, and yours doesn't seem to love \(name) right now. Want to set it aside for a while? You can always revisit it.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: theme.metrics.space2) {
                    PrimaryButton(title: "Set aside for now", action: onSetAside)
                    SecondaryButton(title: "Keep checking", action: onKeepChecking)
                }
            }
        }
    }
}

// MARK: - Add-suspect sheet (with the medical_allergy block)

struct ThrAddSuspectSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let store: FoodStatusStore

    @State private var query = ""
    @State private var results: [FoodStatusStore.FoodSearchHit] = []
    @State private var blockedName: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                TextField("Search a food", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { Task { await search() } }
                    .onChange(of: query) { _, _ in Task { await search() } }
                if let blockedName {
                    // Allergy block: a confirm/deny flow would falsely imply doubt.
                    Text("\(blockedName) is already flagged as an allergy. It stays loud, so there's nothing to test here.")
                        .font(theme.typography.caption(weight: .medium))
                        .foregroundStyle(theme.colors.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    VStack(spacing: theme.metrics.space2) {
                        ForEach(results) { food in
                            let blocked = store.isMedicalAllergy(food.id)
                            Button {
                                Task { await add(food) }
                            } label: {
                                HStack {
                                    Text(food.canonicalName)
                                        .font(theme.typography.body())
                                        .foregroundStyle(theme.colors.textPrimary)
                                    Spacer()
                                    Image(systemName: blocked ? "exclamationmark.triangle.fill" : "plus")
                                        .foregroundStyle(blocked ? theme.colors.error : theme.colors.primary)
                                }
                                .padding(theme.metrics.space3)
                                .background(theme.colors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
            }
            .padding(theme.metrics.space5)
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Add a food to check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(theme.colors.primary)
                }
            }
        }
    }

    private func search() async {
        results = await store.searchFoods(query)
    }

    private func add(_ food: FoodStatusStore.FoodSearchHit) async {
        // BLOCK adding a medical_allergy food as a suspect (rule #1). The store
        // guards defensively too, but the UI shows WHY rather than silently failing.
        guard !store.isMedicalAllergy(food.id) else {
            blockedName = food.canonicalName
            return
        }
        await store.addSuspect(foodId: food.id)
        dismiss()
    }
}

// MARK: - Re-intro tab (event-driven bar, one at a time)

struct ThrReintroTab: View {
    @Environment(\.theme) private var theme
    let store: FoodStatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            if let challenge = store.activeFoodChallenge, let foodId = challenge.foodId {
                Card {
                    VStack(alignment: .leading, spacing: theme.metrics.space3) {
                        Text("Building toward \(store.foodName(foodId))")
                            .font(theme.typography.title(20))
                            .foregroundStyle(theme.colors.textPrimary)
                        // Event-driven progress: advances on good meals, NEVER on time.
                        ThrReintroBar(pct: store.challengeProgressPct())
                        Text("\(challenge.mealsFeelingFineCount) of \(GameConfig.shared.reintroMealsToPass) good meals. Each meal where it sat fine moves this along.")
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SecondaryButton(title: "End this re-intro") {
                            Task { await store.endActiveChallenge() }
                        }
                    }
                }
            } else {
                Text("No re-intro in progress. Start one from a food you're checking, you can test one at a time.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let reintroducing = store.reintroducing()
            if !reintroducing.isEmpty {
                Text("Testing")
                    .font(theme.typography.title(20))
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(reintroducing, id: \.id) { s in
                    Card {
                        HStack {
                            Text(store.foodName(s.foodId))
                                .font(theme.typography.body(weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                            Spacer()
                            Badge(text: "Testing", tint: theme.colors.accent)
                        }
                    }
                }
            }
        }
    }
}

/// A simple additive fill (0...100%). Event-driven; carries no time denominator.
struct ThrReintroBar: View {
    @Environment(\.theme) private var theme
    let pct: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.colors.divider)
                Capsule().fill(theme.colors.success)
                    .frame(width: max(6, geo.size.width * CGFloat(max(0, min(100, pct))) / 100))
            }
        }
        .frame(height: 12)
        .accessibilityLabel("\(pct) percent of the way to enjoying this food again")
    }
}

// MARK: - Timeline tab (read-only observations)

struct ThrTimelineTab: View {
    @Environment(\.theme) private var theme
    let store: FoodStatusStore

    // The shared store synthesizes the chronological observation log (Module E).
    private var events: [SrvFoodEvent] { store.timelineEvents() }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space3) {
            if events.isEmpty {
                Text("Your observations will show here as you check and re-intro foods.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(events) { event in
                    Card {
                        HStack(alignment: .top, spacing: theme.metrics.space3) {
                            Image(systemName: event.systemImage)
                                .foregroundStyle(theme.colors.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.summary)
                                    .font(theme.typography.body())
                                    .foregroundStyle(theme.colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(Self.dateLabel(event.date))
                                    .font(theme.typography.caption(11))
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                        }
                    }
                }
                Text("These are your own observations, worth raising with a dietitian.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.top, theme.metrics.space2)
            }
        }
    }

    private static func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }
}

// MARK: - Avoid ("On pause") tab

struct ThrAvoidTab: View {
    @Environment(\.theme) private var theme
    let store: FoodStatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space3) {
            let avoided = store.avoided()
            Text(avoided.isEmpty ? "Foods you're setting aside for now"
                 : "\(avoided.count) food\(avoided.count == 1 ? "" : "s") you're setting aside for now")
                .font(theme.typography.title(20))
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if avoided.isEmpty {
                Text("Nothing here yet. If a food keeps not sitting right, you can set it aside, and pick it back up whenever you like.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(avoided, id: \.id) { s in
                    Card {
                        HStack {
                            Text(store.foodName(s.foodId))
                                .font(theme.typography.body(weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                            Spacer()
                            Button {
                                Task { await store.revisit(s) }
                            } label: {
                                HStack(spacing: theme.metrics.space1) {
                                    Image(systemName: "arrow.uturn.backward")
                                    Text("Revisit")
                                }
                                .font(theme.typography.caption(weight: .semibold))
                                .foregroundStyle(theme.colors.primary)
                            }
                            .accessibilityLabel("Revisit \(store.foodName(s.foodId))")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Segmented tabs

struct ThrSegmentedTabs: View {
    @Environment(\.theme) private var theme
    @Binding var selection: ThrFoodsTab

    var body: some View {
        HStack(spacing: theme.metrics.space1) {
            ForEach(ThrFoodsTab.allCases) { t in
                let on = selection == t
                Button { selection = t } label: {
                    Text(t.title)
                        .font(theme.typography.caption(weight: on ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.metrics.space2)
                        .foregroundStyle(on ? theme.colors.surface : theme.colors.textSecondary)
                        .background(on ? theme.colors.primary : theme.colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(theme.metrics.space1)
        .background(theme.colors.background)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
    }
}
