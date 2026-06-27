//
//  SrvEpisode.swift
//  MyGutGarden, Module E (R3 Batch E): Survive as a time-boxed episode.
//
//  Entering Survive IS entering the reset (after a hard disclaimer): low-residue
//  break -> gentle reintroduction -> graduate to Thrive. This file holds the
//  episode machinery the home surface composes:
//   • SrvEpisode.ensureStarted        - start/resume one reset arc on entry,
//   • SrvMealPlanModel                - today's curated 7-day plan for the phase (Fence 6),
//   • SrvNotifications                - evening check-in + 30-min post-meal nudge,
//   • SrvResetBreakDetector           - auto-add a high-residue "break" food to Checking
//                                       when a meal preceded an unwell check-in (Fence 6).
//
//  Progress stays RELIEF-only, the reset is never named "carnivore", and the
//  auto-track is investigation, not accusation (rules #4, #7).
//

import SwiftUI
import Observation

// MARK: - Episode bootstrap

enum SrvEpisode {
    /// Ensure an active reset exists when the user is in Survive. Starts a fresh
    /// arc only if there is none, or the last one ended / graduated, so re-entering
    /// Survive resumes an in-progress reset rather than restarting it.
    static func ensureStarted(appState: AppState) async {
        guard let repo = appState.repository, let uid = appState.profile?.id else { return }
        let existing = try? await repo.fetchSurviveReset()
        let needsFresh = existing == nil
            || existing?.endedAt != nil
            || existing?.phase == SrvResetPhase.graduated.rawValue
        guard needsFresh else { return }
        let body: [String: PGValue] = [
            "user_id": .string(uid), "phase": .string(SrvResetPhase.reset.rawValue),
            "symptom_free_days": .int(0),
            "started_at": .date(Date()), "paused_at": .null, "ended_at": .null,
            "graduated_at": .null, "clinician_prompted_at": .null, "no_improvement_alerts": .int(0)
        ]
        try? await repo.upsert("survive_reset", body, onConflict: "user_id")
    }
}

// MARK: - Suggested meals (survive_meal_plan, curated + fenced)

@MainActor
@Observable
final class SrvMealPlanModel {
    /// ONE meal per slot (R4): a single suggestion you can refresh for a different one.
    struct Slot: Identifiable, Sendable {
        let id: String
        let title: String
        let meal: SurviveMealPlanRow
    }
    struct DayPlan: Identifiable, Sendable {
        let id: Int
        let title: String
        let slots: [Slot]
    }

    var todaySlots: [Slot] = []
    var dayIndex = 0
    var isLoaded = false

    private var all: [SurviveMealPlanRow] = []
    private var cursor = 0
    private static let order: [(slot: String, title: String)] = [
        ("breakfast", "Breakfast"), ("lunch", "Lunch"), ("dinner", "Dinner")
    ]

    func load(repo: Repository, phase: String, startedAt: Date?) async {
        all = (try? await repo.fetchSurviveMealPlan(phase: phase)) ?? []
        dayIndex = Self.dayIndex(startedAt: startedAt)
        cursor = 0
        rebuildToday()
        isLoaded = true
    }

    /// New ideas for today: cycles through the whole pool for each slot.
    func refresh() { cursor += 1; rebuildToday() }

    private func rebuildToday() {
        var built: [Slot] = []
        for entry in Self.order {
            let pool = all.filter { $0.mealSlot == entry.slot }
                .sorted { ($0.dayIndex, $0.optionIndex) < ($1.dayIndex, $1.optionIndex) }
            guard !pool.isEmpty else { continue }
            let idx = (dayIndex * 2 + cursor) % pool.count
            built.append(Slot(id: entry.slot, title: entry.title, meal: pool[idx]))
        }
        todaySlots = built
    }

    /// The week at a glance: one option per slot per day (the click-in view).
    func weeklyPlan() -> [DayPlan] {
        (0..<7).map { d in
            var slots: [Slot] = []
            for entry in Self.order {
                if let m = all.first(where: { $0.dayIndex == d && $0.mealSlot == entry.slot && $0.optionIndex == 1 }) {
                    slots.append(Slot(id: "\(d)-\(entry.slot)", title: entry.title, meal: m))
                }
            }
            return DayPlan(id: d, title: "Day \(d + 1)", slots: slots)
        }
    }

    /// Everything you'd buy to cook the week, de-duplicated (the grocery haul).
    func groceryHaul() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for day in weeklyPlan() {
            for slot in day.slots {
                for food in slot.meal.exampleFoods where !seen.contains(food.lowercased()) {
                    seen.insert(food.lowercased())
                    out.append(food)
                }
            }
        }
        return out.sorted()
    }

    /// Day 0..6 of the plan: days since the reset began, wrapped to a week.
    static func dayIndex(startedAt: Date?) -> Int {
        guard let start = startedAt else { return 0 }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: Date())).day ?? 0
        return ((days % 7) + 7) % 7
    }
}

// MARK: - Weekly plan + grocery haul (the suggested-meals click-in)

struct SrvWeeklyPlanView: View {
    @Environment(\.theme) private var theme
    let model: SrvMealPlanModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                groceryCard
                ForEach(model.weeklyPlan()) { day in
                    Card {
                        VStack(alignment: .leading, spacing: theme.metrics.space2) {
                            Text(day.title)
                                .font(theme.typography.title(18))
                                .foregroundStyle(theme.colors.textPrimary)
                            ForEach(day.slots) { slot in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(slot.title)
                                        .font(theme.typography.caption(weight: .semibold))
                                        .foregroundStyle(theme.colors.secondary)
                                    Text(slot.meal.title)
                                        .font(theme.typography.body(weight: .medium))
                                        .foregroundStyle(theme.colors.textPrimary)
                                    Text(slot.meal.description)
                                        .font(theme.typography.caption())
                                        .foregroundStyle(theme.colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                Text("A starting point your dietitian can tune.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .padding(theme.metrics.space4)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("This week's plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var groceryCard: some View {
        let haul = model.groceryHaul()
        return Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                SectionHeader(title: "Grocery haul")
                if haul.isEmpty {
                    Text("Your shopping list appears once a plan is loaded.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                } else {
                    Text(haul.joined(separator: " \u{00B7} "))
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Everything you'd buy to cook this week's gentle meals.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
    }
}

// MARK: - Notifications (cadence = post-meal + evening)

@MainActor
enum SrvNotifications {
    /// Request permission once and schedule the daily evening check-in reminder.
    static func enableEveningReminder() async {
        guard await NotificationScheduler.requestAuthorization() else { return }
        NotificationScheduler.cancel(ids: ["srv-evening"])
        var when = DateComponents()
        when.hour = GameConfig.shared.surviveEveningCheckinHour
        when.minute = 0
        NotificationScheduler.schedule(
            id: "srv-evening",
            title: "Evening check-in",
            body: "How did today sit? A quick log keeps your reset on track.",
            at: when)
    }

    /// 30-min post-meal "how did that sit?" nudge (replaces the inline prompt).
    static func schedulePostMealNudge(mealId: String) {
        let mins = GameConfig.shared.surviveReintroFollowupMinutes
        NotificationScheduler.scheduleIn(
            id: "srv-postmeal-\(mealId)",
            title: "How did that sit?",
            body: "It's been about \(mins) minutes since your meal. Tap to log how you feel.",
            seconds: Double(mins) * 60)
    }
}

// MARK: - Reset diet-break auto-track (Fence 6)

enum SrvResetBreakDetector {
    private struct FiberRow: Decodable, Sendable { let foodId: String; let estFiberG: Double? }

    private static let mealColumns = "id,mode,photo_url,captured_at,confirmed,user_annotation,photo_expires_at"
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    /// After a Survive check-in: if a reset is active and today read unwell, scan
    /// today's meals and quietly add any high-residue ("break") food to Checking
    /// with a removable note. No-op when paused / graduated / feeling fine.
    static func run(appState: AppState) async {
        guard let repo = appState.repository, let uid = appState.profile?.id else { return }
        guard let reset = try? await repo.fetchSurviveReset(),
              reset.endedAt == nil, reset.pausedAt == nil,
              reset.phase != SrvResetPhase.graduated.rawValue else { return }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let today = dayFmt.string(from: Date())

        let symptoms: [SymptomEntryRow] = (try? await repo.select(
            "symptom_entries", filters: ["user_id": "eq.\(uid)", "log_date": "eq.\(today)"])) ?? []
        let minSeverity = GameConfig.shared.suspectSuggestionMinSeverity
        guard symptoms.contains(where: { $0.severity >= minSeverity }) else { return }

        let since = isoFmt.string(from: startOfToday)
        let meals: [MealRow] = (try? await repo.select(
            "meals", columns: mealColumns,
            filters: ["captured_at": "gte.\(since)", "mode": "eq.survive", "confirmed": "eq.true"])) ?? []
        guard !meals.isEmpty else { return }
        let mealList = "(" + meals.map(\.id).joined(separator: ",") + ")"
        let items: [FiberRow] = (try? await repo.select(
            "meal_items", columns: "food_id,est_fiber_g", filters: ["meal_id": "in.\(mealList)"])) ?? []
        let threshold = GameConfig.shared.resetBreakFoodFiberThresholdG
        let breakFoods = Set(items.filter { ($0.estFiberG ?? 0) > threshold }.map(\.foodId))
        guard !breakFoods.isEmpty else { return }

        let store = FoodStatusStore(repository: repo, userId: uid, appState: appState)
        await store.load()
        for foodId in breakFoods { await store.autoFlagBreakFood(foodId) }
    }
}
