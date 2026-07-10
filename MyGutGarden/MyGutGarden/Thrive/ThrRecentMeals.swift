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
    /// Called (mealId, questionId) when the sheet answers a quick check, so
    /// the owner of `questions` prunes it and the ⚠︎ clears immediately.
    var onQuestionAnswered: (String, String) -> Void = { _, _ in }

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
                            ThrMealThumbCard(appState: appState, meal: meal,
                                             hasQuestion: !(questions[meal.id] ?? []).isEmpty)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, theme.metrics.space1)
            }
        }
        .sheet(item: $selected) { wrapper in
            // Owner (2026-07-09): the SAME editor as the fresh-scan review, not
            // a separate legacy sheet.
            ThrMealEditSheet(appState: appState, meal: wrapper.meal, questions: wrapper.questions,
                             onQuestionAnswered: { onQuestionAnswered(wrapper.meal.id, $0) })
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
    let appState: AppState
    let meal: MealRow
    var hasQuestion = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space1) {
            ThrMealPhoto(appState: appState, photoUrl: meal.photoUrl)
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
///
/// The meal-photos bucket is PRIVATE (per-user RLS, Fence 5), so a plain
/// AsyncImage — which can't send the apikey/Authorization headers — failed on
/// every photo and the rail showed nothing but placeholders (owner report,
/// 2026-07-09). This loads through ThrMealPhotoLoader instead: authenticated
/// fetch, one 401→token-refresh retry, downsampled + cached in memory.
struct ThrMealPhoto: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    let photoUrl: String?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            placeholder
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if photoUrl != nil, !failed {
                ProgressView()
            }
        }
        .task(id: photoUrl) {
            guard let photoUrl else { return }
            if let loaded = await ThrMealPhotoLoader.shared.load(photoUrl, auth: appState.auth) {
                image = loaded
            } else {
                failed = true
            }
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

/// Authenticated image fetcher for the private meal-photos bucket, with an
/// in-memory cache of downsampled images (full-size camera JPEGs are megabytes;
/// the rail needs ~116pt). One instance app-wide so scrolling stays warm.
@MainActor
final class ThrMealPhotoLoader {
    static let shared = ThrMealPhotoLoader()

    private let cache = NSCache<NSString, UIImage>()
    private init() { cache.countLimit = 120 }

    func load(_ urlString: String, auth: AuthService) async -> UIImage? {
        if let hit = cache.object(forKey: urlString as NSString) { return hit }
        guard let url = URL(string: urlString) else { return nil }

        let (image0, status) = await fetch(url, token: auth.session?.accessToken)
        var image = image0
        if image == nil {
            // Refresh + retry ONLY on 401 (a stale JWT) — a network blip or a
            // 404 (deleted object) shouldn't burn a token refresh (2026-07-09).
            guard status == 401, let fresh = await auth.refreshSession() else { return nil }
            image = await fetch(url, token: fresh).0
            guard image != nil else { return nil }
        }
        let prepared = await downsample(image!)
        cache.setObject(prepared, forKey: urlString as NSString)
        return prepared
    }

    /// - Returns: the decoded image (nil on any failure) + the HTTP status (0 on
    ///   transport error) so the caller can refresh only on 401.
    private func fetch(_ url: URL, token: String?) async -> (UIImage?, Int) {
        guard let token else { return (nil, 0) }
        var req = URLRequest(url: url)
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return (nil, 0) }
        guard (200..<300).contains(http.statusCode), let image = UIImage(data: data) else {
            return (nil, http.statusCode)
        }
        return (image, http.statusCode)
    }

    /// Downsample to display size (max ~800px) so the cache holds thumbnails,
    /// not multi-megabyte camera frames.
    private func downsample(_ image: UIImage) async -> UIImage {
        let maxSide: CGFloat = 800
        let largest = max(image.size.width, image.size.height)
        guard largest > maxSide else { return image }
        let scale = maxSide / largest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return await image.byPreparingThumbnail(ofSize: target) ?? image
    }
}

// MARK: - Meal edit sheet (owner, 2026-07-09: the SAME editor as fresh-scan)

/// Tapping a photo in Today opens this — the fresh-scan review editor
/// (CapReviewPanel: sliders, add-a-food, remove, "Looks right", grams that
/// match the DB) rebuilt from the persisted meal, PLUS the meal's quick-check
/// nudges and the photo-delete control. The old bespoke detail sheet (coarse
/// tiers + confirm/deny) is retired: one editing experience everywhere.
struct ThrMealEditSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let appState: AppState
    let meal: MealRow
    var questions: [ThrMealKeyQuestion] = []
    /// Bubbles an answered quick-check (question id) up so the ⚠︎ badge clears.
    var onQuestionAnswered: (String) -> Void = { _ in }

    @State private var reviewModel: CapReviewModel?
    @State private var quickCheck: ThrQuickCheckModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space4) {
                    ThrMealPhoto(appState: appState, photoUrl: meal.photoUrl)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))

                    if let note = meal.userAnnotation, !note.isEmpty {
                        Text("\u{201C}\(note)\u{201D}")
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textSecondary)
                    }

                    if let quickCheck, !quickCheck.pending.isEmpty {
                        ThrQuickCheckCard(model: quickCheck, onAnswered: onQuestionAnswered)
                    }

                    if let reviewModel {
                        CapReviewPanel(model: reviewModel)
                        photoRow(reviewModel)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(theme.colors.primary)
                }
            }
        }
        .task {
            if reviewModel == nil, let repo = appState.repository, let uid = appState.profile?.id {
                reviewModel = await CapReviewModel.forLoggedMeal(
                    mealId: meal.id, photoURL: meal.photoUrl, repository: repo, userId: uid)
            }
            if quickCheck == nil {
                quickCheck = ThrQuickCheckModel(appState: appState, meal: meal, questions: questions)
            }
        }
    }

    /// Fence 5: photos are permanent-but-deletable; this is the delete surface.
    @ViewBuilder
    private func photoRow(_ model: CapReviewModel) -> some View {
        if model.hadPhoto, model.canPersist {
            Card {
                HStack(spacing: theme.metrics.space3) {
                    Image(systemName: model.photoRemoved ? "photo.badge.exclamationmark" : "photo")
                        .foregroundStyle(theme.colors.textSecondary)
                    Text(model.photoRemoved ? "Photo removed" : "Photo saved to your private log")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                    Spacer()
                    if !model.photoRemoved {
                        Button(role: .destructive) { Task { await model.deletePhoto() } } label: {
                            Text("Delete photo").font(theme.typography.caption(weight: .semibold))
                        }
                        .foregroundStyle(theme.colors.error)
                    }
                }
            }
        }
    }
}

// MARK: - Quick check (the one-or-two ⚠︎ key questions; the nudge stays)

/// The ⚠︎ hidden-ingredient nudges for a meal ("this curry often has onion —
/// was it?"). On "yes" it adds the food as a hidden_confirmed item (DB derives
/// fiber) and records the answer so the badge clears for good.
struct ThrQuickCheckCard: View {
    @Environment(\.theme) private var theme
    @Bindable var model: ThrQuickCheckModel
    var onAnswered: (String) -> Void = { _ in }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                HStack(spacing: theme.metrics.space2) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(theme.colors.warning)
                    SectionHeader(title: "Quick check")
                }
                ForEach(model.pending) { question in
                    VStack(alignment: .leading, spacing: theme.metrics.space2) {
                        Text(question.prompt)
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: theme.metrics.space3) {
                            answerButton("Yes, it was", question: question, wasPresent: true)
                            answerButton("No", question: question, wasPresent: false)
                        }
                    }
                    if question.id != model.pending.last?.id { Divider().overlay(theme.colors.divider) }
                }
            }
        }
    }

    private func answerButton(_ title: String, question: ThrMealKeyQuestion, wasPresent: Bool) -> some View {
        Button {
            Task { await model.answer(question, wasPresent: wasPresent); onAnswered(question.id) }
        } label: {
            Text(title)
                .font(theme.typography.body(weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, theme.metrics.space2)
        }
        .foregroundStyle(theme.colors.primary)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous)
            .strokeBorder(theme.colors.primary.opacity(0.4), lineWidth: 1))
        .accessibilityLabel("\(title): \(question.foodName)")
    }
}

@MainActor
@Observable
final class ThrQuickCheckModel {
    let appState: AppState
    let meal: MealRow
    var pending: [ThrMealKeyQuestion]
    private var answers: [[String: Any]] = []

    init(appState: AppState, meal: MealRow, questions: [ThrMealKeyQuestion]) {
        self.appState = appState
        self.meal = meal
        self.pending = questions
        if let raw = meal.hiddenIngredientAnswers,
           let existing = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]] {
            answers = existing
        }
    }

    /// Record the answer (clears the ⚠︎ for good) and, on "yes", log the food as
    /// a hidden_confirmed item so the DB derives its fiber + the garden counts it.
    func answer(_ question: ThrMealKeyQuestion, wasPresent: Bool) async {
        guard let repo = appState.repository else { return }
        answers.append(["food_name": question.foodName, "dish_type": question.dishType,
                        "was_present": wasPresent])
        if let data = try? JSONSerialization.data(withJSONObject: answers),
           let json = String(data: data, encoding: .utf8) {
            try? await repo.update("meals", set: ["hidden_ingredient_answers": .string(json)],
                                   filters: ["id": "eq.\(meal.id)"])
        }
        if wasPresent {
            // Don't double-count: only add the food if the meal doesn't already
            // contain it (the user may have added it via the editor, or answered
            // an overlapping prompt) — 2026-07-09 review.
            struct ItemIdRow: Decodable { let foodId: String }
            let existing: [ItemIdRow] = (try? await repo.select(
                "meal_items", columns: "food_id",
                filters: ["meal_id": "eq.\(meal.id)", "food_id": "eq.\(question.foodId)"])) ?? []
            if existing.isEmpty {
                try? await repo.insertVoid("meal_items", [
                    "meal_id": .string(meal.id),
                    "food_id": .string(question.foodId),
                    "portion_tier": .string(PortionTier.serving.rawValue),
                    "source": .string("hidden_confirmed"),
                ])
            }
        }
        pending.removeAll { $0.id == question.id }
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
