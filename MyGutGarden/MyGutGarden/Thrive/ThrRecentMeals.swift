//
//  ThrRecentMeals.swift
//  MyGutGarden, Module C: the Recent-Meals rail on the Thrive home surface
//  (Batch D / SPEC §11a).
//
//  A horizontal rail of the last few days of confirmed meals. Tapping one reopens
//  its ingredients with EDITABLE coarse amounts (trace/serving/lots, never grams,
//  rule #3) and lets the user confirm or deny the AI's hypotheses, writing
//  meal_items.user_confirmed / user_denied. photo_url is permanent; a nil photo
//  (a never-photographed manual meal, or a user-deleted photo) renders a neutral
//  placeholder.
//

import SwiftUI
import Observation

// MARK: - Section (rail of thumbnails)

struct ThrRecentMealsSection: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    let meals: [MealRow]
    /// The one-or-two KEY hidden-ingredient questions per meal id (⚠︎ badge;
    /// answered in the pop-up). Owner rework, 2026-07-02 round 2.
    var questions: [String: [ThrMealKeyQuestion]] = [:]

    @State private var selected: ThrSelectedMeal?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space3) {
            SectionHeader(title: "Recent meals")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.metrics.space3) {
                    ForEach(meals, id: \.id) { meal in
                        Button {
                            selected = ThrSelectedMeal(meal: meal, questions: questions[meal.id] ?? [])
                        } label: {
                            ThrMealThumbCard(meal: meal, hasQuestion: !(questions[meal.id] ?? []).isEmpty)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, theme.metrics.space1)
            }
        }
        .sheet(item: $selected) { wrapper in
            ThrMealDetailSheet(appState: appState, meal: wrapper.meal, questions: wrapper.questions)
        }
    }
}

/// Identifiable wrapper so a `MealRow` (spine type) can drive a `.sheet(item:)`
/// without retroactively conforming a type Module C doesn't own.
private struct ThrSelectedMeal: Identifiable {
    let meal: MealRow
    var questions: [ThrMealKeyQuestion] = []
    var id: String { meal.id }
}

// MARK: - Thumbnail card

struct ThrMealThumbCard: View {
    @Environment(\.theme) private var theme
    let meal: MealRow
    var hasQuestion = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space1) {
            ThrMealPhoto(photoUrl: meal.photoUrl)
                .frame(width: 116, height: 116)
                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if hasQuestion {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(theme.colors.surface, theme.colors.warning)
                            .padding(theme.metrics.space1)
                    }
                }
            Text(ThrMealDates.shortLabel(meal.capturedAt))
                .font(theme.typography.caption(weight: .medium))
                .foregroundStyle(theme.colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meal from \(ThrMealDates.shortLabel(meal.capturedAt))."
                            + (hasQuestion ? " Has a quick question." : "")
                            + " Tap to see ingredients.")
    }
}

/// The shared photo slot: the stored image when present, else a neutral
/// placeholder (used identically for nil, expired, and never-photographed meals).
struct ThrMealPhoto: View {
    @Environment(\.theme) private var theme
    let photoUrl: String?

    var body: some View {
        if let photoUrl, let url = URL(string: photoUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                default:
                    ZStack { placeholder; ProgressView() }
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            theme.colors.secondary.opacity(0.16)
            Image(systemName: "fork.knife")
                .font(.system(size: 28))
                .foregroundStyle(theme.colors.secondary.opacity(0.7))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Detail sheet (editable amounts + confirm/deny hypotheses)

struct ThrMealDetailSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let appState: AppState
    let meal: MealRow
    var questions: [ThrMealKeyQuestion] = []

    @State private var model: ThrMealDetailModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    ThrMealPhoto(photoUrl: meal.photoUrl)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))

                    if let note = meal.userAnnotation, !note.isEmpty {
                        Text("\u{201C}\(note)\u{201D}")
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textSecondary)
                    }

                    if let model {
                        quickCheck(model)
                        ingredients(model)
                        hypotheses(model)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(theme.metrics.space5)
                    }
                }
                .padding(theme.metrics.space5)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle(ThrMealDates.shortLabel(meal.capturedAt))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(theme.colors.primary)
                }
            }
        }
        .task {
            if model == nil {
                let m = ThrMealDetailModel(appState: appState, meal: meal, questions: questions)
                await m.load()
                model = m
            }
        }
    }

    // MARK: The one-or-two key questions (the ⚠︎'s payoff; ThrMealQuestions)

    @ViewBuilder private func quickCheck(_ model: ThrMealDetailModel) -> some View {
        if !model.pendingQuestions.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space3) {
                    HStack(spacing: theme.metrics.space2) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(theme.colors.warning)
                        SectionHeader(title: "Quick check")
                    }
                    ForEach(model.pendingQuestions) { question in
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            Text(question.prompt)
                                .font(theme.typography.body())
                                .foregroundStyle(theme.colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: theme.metrics.space3) {
                                quickAnswer("Yes, it was", question: question, wasPresent: true)
                                quickAnswer("No", question: question, wasPresent: false)
                            }
                        }
                        if question.id != model.pendingQuestions.last?.id {
                            Divider().overlay(theme.colors.divider)
                        }
                    }
                }
            }
        }
    }

    private func quickAnswer(_ title: String, question: ThrMealKeyQuestion, wasPresent: Bool) -> some View {
        Button {
            Task { await model?.answer(question, wasPresent: wasPresent) }
        } label: {
            Text(title)
                .font(theme.typography.body(weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, theme.metrics.space2)
        }
        .foregroundStyle(theme.colors.primary)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous)
                .strokeBorder(theme.colors.primary.opacity(0.4), lineWidth: 1)
        )
        .accessibilityLabel("\(title): \(question.foodName)")
    }

    // MARK: Ingredients (editable coarse amounts)

    private func ingredients(_ model: ThrMealDetailModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "What was in it")
                if model.items.isEmpty {
                    Text("No ingredients recorded for this meal.")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                } else {
                    ForEach(model.items) { item in
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            Text(model.name(for: item))
                                .font(theme.typography.body(weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                            ThrPortionPicker(selection: PortionTier(rawValue: item.portionTier)) { tier in
                                Task { await model.setPortion(item, tier) }
                            }
                        }
                        if item.id != model.items.last?.id { Divider().overlay(theme.colors.divider) }
                    }
                    Text("Amounts are coarse and directional, just enough to point you the right way.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
    }

    // MARK: Confirm / deny the AI's hypotheses

    @ViewBuilder private func hypotheses(_ model: ThrMealDetailModel) -> some View {
        let ai = model.items.filter { $0.source == "vision" || $0.source == "annotation" }
        if !ai.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space3) {
                    SectionHeader(title: "Did we get these right?")
                    Text("Your confirmations teach the garden, not a verdict on you.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                    ForEach(ai) { item in
                        ThrMealHypothesisRow(
                            name: model.name(for: item),
                            confirmed: item.userConfirmed,
                            denied: item.userDenied,
                            onConfirm: { Task { await model.setVerdict(item, confirmed: true) } },
                            onDeny: { Task { await model.setVerdict(item, confirmed: false) } }
                        )
                    }
                }
            }
        }
    }
}

/// One AI-identified item with a confirm / deny choice (writes user_confirmed /
/// user_denied). Neutral, never an accusation, the user authors the verdict.
struct ThrMealHypothesisRow: View {
    @Environment(\.theme) private var theme
    let name: String
    let confirmed: Bool?
    let denied: Bool?
    let onConfirm: () -> Void
    let onDeny: () -> Void

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            Text(name)
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            choice(systemImage: "checkmark", label: "Looks right",
                   on: confirmed == true, tint: theme.colors.success, action: onConfirm)
            choice(systemImage: "xmark", label: "Not in it",
                   on: denied == true, tint: theme.colors.secondary, action: onDeny)
        }
        .padding(.vertical, theme.metrics.space1)
    }

    private func choice(systemImage: String, label: String, on: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(on ? theme.colors.surface : tint)
                .frame(width: 32, height: 32)
                .background(on ? tint : tint.opacity(0.14))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) for \(name)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A coarse trace/serving/lots picker (no grams, rule #3).
struct ThrPortionPicker: View {
    @Environment(\.theme) private var theme
    let selection: PortionTier?
    let onPick: (PortionTier) -> Void

    private let tiers: [PortionTier] = [.trace, .serving, .lots]

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            ForEach(tiers, id: \.self) { tier in
                let on = selection == tier
                Button { onPick(tier) } label: {
                    Text(tier.rawValue.capitalized)
                        .font(theme.typography.caption(weight: on ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.metrics.space2)
                        .foregroundStyle(on ? theme.colors.surface : theme.colors.textSecondary)
                        .background(on ? theme.colors.primary : theme.colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tier.rawValue) amount")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: - Detail model

@MainActor
@Observable
final class ThrMealDetailModel {
    let appState: AppState
    let meal: MealRow

    var items: [ThrMealItemRow] = []
    var pendingQuestions: [ThrMealKeyQuestion] = []
    private var answers: [[String: Any]] = []       // meals.hidden_ingredient_answers, appended per answer
    private var nameByFood: [String: String] = [:]

    init(appState: AppState, meal: MealRow, questions: [ThrMealKeyQuestion] = []) {
        self.appState = appState
        self.meal = meal
        self.pendingQuestions = questions
        if let raw = meal.hiddenIngredientAnswers,
           let existing = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]] {
            answers = existing
        }
    }

    /// Answer a key question: record it on the meal (so the ⚠︎ clears for good)
    /// and, on "yes", log the food as a hidden_confirmed item — the DB trigger
    /// derives its fiber, and the garden picks it up on the next ingest pass.
    func answer(_ question: ThrMealKeyQuestion, wasPresent: Bool) async {
        guard let repo = appState.repository else { return }
        answers.append(["food_name": question.foodName,
                        "dish_type": question.dishType,
                        "was_present": wasPresent])
        if let data = try? JSONSerialization.data(withJSONObject: answers),
           let json = String(data: data, encoding: .utf8) {
            try? await repo.update("meals",
                                   set: ["hidden_ingredient_answers": .string(json)],
                                   filters: ["id": "eq.\(meal.id)"])
        }
        if wasPresent {
            try? await repo.insertVoid("meal_items", [
                "meal_id": .string(meal.id),
                "food_id": .string(question.foodId),
                "portion_tier": .string(PortionTier.serving.rawValue),
                "source": .string("hidden_confirmed"),
            ])
            await load()
        }
        pendingQuestions.removeAll { $0.id == question.id }
    }

    func name(for item: ThrMealItemRow) -> String {
        nameByFood[item.foodId] ?? "This food"
    }

    func load() async {
        guard let repo = appState.repository else { return }
        let rows: [ThrMealItemRow] = (try? await repo.select(
            "meal_items",
            columns: "id,food_id,portion_tier,source,est_fiber_g,user_confirmed,user_denied",
            filters: ["meal_id": "eq.\(meal.id)"]
        )) ?? []
        items = rows
        let ids = Set(rows.map(\.foodId))
        guard !ids.isEmpty else { return }
        let inList = "(" + ids.joined(separator: ",") + ")"
        if let foods: [ThrFoodNameRow] = try? await repo.select(
            "foods", columns: "id,canonical_name", filters: ["id": "in.\(inList)"]
        ) {
            nameByFood = Dictionary(foods.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { a, _ in a })
        }
    }

    /// Edit a coarse amount (writes meal_items.portion_tier).
    func setPortion(_ item: ThrMealItemRow, _ tier: PortionTier) async {
        guard let repo = appState.repository else { return }
        try? await repo.update("meal_items",
                               set: ["portion_tier": .string(tier.rawValue)],
                               filters: ["id": "eq.\(item.id)"])
        replace(item) { ThrMealItemRow(id: $0.id, foodId: $0.foodId, portionTier: tier.rawValue,
                                       source: $0.source, estFiberG: $0.estFiberG,
                                       userConfirmed: $0.userConfirmed, userDenied: $0.userDenied) }
    }

    /// Confirm or deny the AI hypothesis (writes user_confirmed / user_denied).
    func setVerdict(_ item: ThrMealItemRow, confirmed: Bool) async {
        guard let repo = appState.repository else { return }
        try? await repo.update("meal_items",
                               set: ["user_confirmed": .bool(confirmed), "user_denied": .bool(!confirmed)],
                               filters: ["id": "eq.\(item.id)"])
        replace(item) { ThrMealItemRow(id: $0.id, foodId: $0.foodId, portionTier: $0.portionTier,
                                       source: $0.source, estFiberG: $0.estFiberG,
                                       userConfirmed: confirmed, userDenied: !confirmed) }
    }

    private func replace(_ item: ThrMealItemRow, _ transform: (ThrMealItemRow) -> ThrMealItemRow) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = transform(items[idx])
    }
}

// MARK: - Date labels

enum ThrMealDates {
    static func shortLabel(_ timestamp: String) -> String {
        guard let date = ThrDates.parseTimestamp(timestamp) else { return "Recent" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }
}

#if DEBUG
#Preview("Recent meals") {
    ThrRecentMealsSection(
        appState: AppState(auth: AuthService()),
        meals: [
            MealRow(id: "1", photoUrl: nil, capturedAt: "2026-06-26T12:00:00Z",
                    confirmed: true, userAnnotation: "lunch bowl"),
            MealRow(id: "2", photoUrl: nil, capturedAt: "2026-06-24T12:00:00Z",
                    confirmed: true, userAnnotation: nil),
        ]
    )
    .padding()
    .themed()
}
#endif
