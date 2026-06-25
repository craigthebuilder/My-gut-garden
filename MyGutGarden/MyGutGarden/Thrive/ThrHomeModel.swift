//
//  ThrHomeModel.swift
//  MyGutGarden — Module C: load + shape the Thrive home dashboard (SPEC §10,
//  §11a). Best-effort loads against the RLS-scoped Repository; every fetch is
//  guarded so a partial/offline backend degrades to a clean empty state that
//  invites action rather than erroring (DESIGN.md "Writing").
//

import SwiftUI
import Observation

@MainActor
@Observable
final class ThrHomeModel {
    // Surfaced goal (the ONLY anthropometric-derived number shown — §10 / rule #6).
    var fiberGoalG: Int?
    var fiberConsumedTodayG: Double = 0

    // Weekly plant variety toward 30 (presence-based, Sunday reset — §8/§13).
    var uniquePlantsThisWeek = 0
    var weekly30Streak = 0
    var bestWeekCount = 0

    // 3 P's + rainbow (today / this week).
    var todayThreePs = ThreePs(prebiotic: false, probiotic: false, polyphenol: false)
    var rainbow = ThrRainbowStatus()

    // Variable reward + rainbow education content.
    var curiosity: ThrCuriosityFactRow?
    var colorEducation: [String: ThrColorEducation] = ThrRainbowContent.fallback

    // Today's optional mood tap (Thrive keeps tracking burden to one tap — §12).
    var loggedMoodToday = false

    var isLoaded = false

    private let target = GameConfig.shared.weeklyPlantTarget

    var fiberFraction: Double {
        guard let goal = fiberGoalG, goal > 0 else { return 0 }
        return min(1, fiberConsumedTodayG / Double(goal))
    }
    var plantsRemaining: Int { max(0, target - uniquePlantsThisWeek) }
    var plantFraction: Double { min(1, Double(uniquePlantsThisWeek) / Double(target)) }

    /// Load from the latest meal first (works fully offline), then enrich from
    /// the backend if a session is available.
    func load(appState: AppState, latestMeal: ConfirmedMeal?) async {
        applyLatestMeal(latestMeal)

        guard let repo = appState.repository else {
            fiberGoalG = appState.profile?.fiberGoalG
            isLoaded = true
            return
        }

        var profile = appState.profile
        if profile == nil { profile = (try? await repo.fetchProfile()) ?? nil }
        fiberGoalG = profile?.fiberGoalG

        await loadWeeklyVariety(repo)
        await loadCuriosity(repo)
        await loadColorEducation(repo)
        await loadTodayCheckin(repo, userId: profile?.id)
        await loadTodayFiber(repo)

        isLoaded = true
    }

    // MARK: - Pieces

    private func applyLatestMeal(_ latestMeal: ConfirmedMeal?) {
        guard let meal = latestMeal else { return }
        let insights = FoodAttributeJoin.thriveInsights(meal.response)
        todayThreePs = insights.threePs
        for c in insights.colorsHit { rainbow.mark(c, .hit) }
    }

    private func loadWeeklyVariety(_ repo: Repository) async {
        guard let rows: [WeeklySummaryRow] = try? await repo.select(
            "weekly_summaries", order: "week_start.desc", limit: 26
        ) else { return }

        let thisMonday = ThrDates.dateString(ThrDates.currentMonday())
        bestWeekCount = rows.map(\.uniquePlantCount).max() ?? 0

        // Current in-progress week (if present) drives the "X/30" indicator but
        // is excluded from the streak count (it hasn't had its chance to close).
        var completed = rows
        if let first = rows.first, first.weekStart == thisMonday {
            uniquePlantsThisWeek = first.uniquePlantCount
            completed = Array(rows.dropFirst())
        }
        weekly30Streak = ThrIngestor.consecutiveWeeklyHits(mostRecentFirst: completed.map(\.hit30))
    }

    private func loadCuriosity(_ repo: Repository) async {
        if let facts: [ThrCuriosityFactRow] = try? await repo.select("curiosity_facts", limit: 50) {
            curiosity = facts.randomElement()
        }
    }

    private func loadColorEducation(_ repo: Repository) async {
        guard let rows: [ThrColorRow] = try? await repo.select("colors") else { return }
        for row in rows {
            colorEducation[row.id] = ThrColorEducation(
                meaning: row.meaningCopy ?? colorEducation[row.id]?.meaning ?? "",
                whatItDoes: row.whatItDoesCopy ?? colorEducation[row.id]?.whatItDoes ?? ""
            )
        }
    }

    private func loadTodayCheckin(_ repo: Repository, userId: String?) async {
        guard let userId else { return }
        let today = ThrDates.dateString()
        if let rows: [ThriveCheckinRow] = try? await repo.select(
            "thrive_checkins", filters: ["user_id": "eq.\(userId)", "log_date": "eq.\(today)"], limit: 1
        ), let row = rows.first {
            loggedMoodToday = row.mood != nil || row.energy != nil || row.clarity != nil
        }
    }

    /// Sum today's coarse/directional fiber from `meal_items` (two cheap reads;
    /// no fragile embedded join). Errors leave the running total at 0.
    private func loadTodayFiber(_ repo: Repository) async {
        let since = ThrDates.timestampString(ThrDates.startOfToday())
        guard let meals: [MealRow] = try? await repo.select(
            "meals", columns: "id,mode,photo_url,captured_at,confirmed",
            filters: ["captured_at": "gte.\(since)", "mode": "eq.thrive", "confirmed": "eq.true"]
        ), !meals.isEmpty else { return }

        let inList = "(" + meals.map(\.id).joined(separator: ",") + ")"
        if let items: [ThrMealItemFiberRow] = try? await repo.select(
            "meal_items", columns: "est_fiber_g", filters: ["meal_id": "in.\(inList)"]
        ) {
            fiberConsumedTodayG = items.compactMap(\.estFiberG).reduce(0, +)
        }
    }
}
