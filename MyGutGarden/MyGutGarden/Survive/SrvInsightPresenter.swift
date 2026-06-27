//
//  SrvInsightPresenter.swift
//  MyGutGarden, Module E. The Survive per-photo view (SPEC §11b).
//
//  Conforms to the `MealInsightPresenting` seam (Seams.swift): the AppShell
//  injects this presenter while in Survive mode, so Module B (capture) never
//  imports Module E. It reuses `FoodAttributeJoin.surviveInsights(_:)` for the
//  FODMAP overlay, no insight logic is re-implemented here.
//
//  What it shows, in Survive's calm register:
//    • a FODMAP safety check per food via the shared `SafetyChip`
//      (color + shape + label, never color alone, DESIGN.md §5),
//    • hidden-trigger flags ("this dish often contains onion, was it?"),
//    • during reintro: "contains [the group you're testing], logging for your
//      challenge,"
//    • medical-allergy alerts, which stay LOUD even here (SPEC §9 / rule #1).
//  No bacteria, no diagnosis, no scores.
//

import SwiftUI

@MainActor
struct SrvInsightPresenter: MealInsightPresenting {
    /// Groups the user is actively testing, so the view can say "logging for
    /// your challenge" when a food contains one (SPEC §11b).
    let activeReintroGroups: [SrvFodmapGroup]
    /// Lets the view check whether a reset is active, so it can flag high-residue
    /// foods as "not for this phase" (R4) instead of a misleading FODMAP "safe".
    let appState: AppState?

    init(activeReintroGroups: [SrvFodmapGroup] = [], appState: AppState? = nil) {
        self.activeReintroGroups = activeReintroGroups
        self.appState = appState
    }

    func insightView(for meal: ConfirmedMeal) -> AnyView {
        AnyView(SrvPhotoInsightView(response: meal.response,
                                    activeReintroGroups: activeReintroGroups, appState: appState))
    }
}

/// One row of FODMAP safety: the food name + its SafetyChip + any reintro note.
struct SrvSafetyRow: Identifiable, Sendable {
    let foodName: String
    let safety: FodmapSafety
    /// The active groups this food contributes to (drives the challenge note).
    let testingGroups: [SrvFodmapGroup]
    var id: String { foodName }
}

enum SrvInsightModel {
    /// Build the safety rows, threading in which active groups each food feeds.
    static func safetyRows(
        for response: RecognitionResponse,
        activeReintroGroups: [SrvFodmapGroup]
    ) -> [SrvSafetyRow] {
        let attrs = FoodAttributeJoin.surfacedAttributes(response)
        let insights = FoodAttributeJoin.surviveInsights(response)

        // Map canonical name → fodmap attr so we can detect tested groups.
        var fodmapByName: [String: FodmapAttr] = [:]
        for a in attrs { if let f = a.fodmap { fodmapByName[a.canonicalName] = f } }

        return insights.safety.map { entry in
            let groups: [SrvFodmapGroup]
            if let f = fodmapByName[entry.foodName] {
                groups = activeReintroGroups.filter { $0.isPresent(in: f) }
            } else {
                groups = []
            }
            return SrvSafetyRow(foodName: entry.foodName, safety: entry.safety, testingGroups: groups)
        }
    }
}

// MARK: - The view

struct SrvPhotoInsightView: View {
    @Environment(\.theme) private var theme
    let response: RecognitionResponse
    let activeReintroGroups: [SrvFodmapGroup]
    var appState: AppState? = nil

    @State private var resetActive = false

    private var rows: [SrvSafetyRow] {
        SrvInsightModel.safetyRows(for: response, activeReintroGroups: activeReintroGroups)
    }
    private var survive: SurvivePhotoInsights {
        FoodAttributeJoin.surviveInsights(response)
    }

    /// Foods whose est fiber per serving exceeds the reset threshold, i.e. not
    /// low-residue. Computed from the meal's own attributes, no extra query.
    private var highResidueFoods: [String] {
        let threshold = GameConfig.shared.resetBreakFoodFiberThresholdG
        return FoodAttributeJoin.surfacedAttributes(response).compactMap { a in
            let grams = a.fibers.compactMap(\.estGramsPerServing).reduce(0, +)
            return grams > threshold ? a.canonicalName : nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                // Medical allergies stay LOUD across both modes (SPEC §9 / rule #1).
                if !response.allergyAlerts.isEmpty {
                    SrvAllergyBanner(alerts: response.allergyAlerts)
                }

                if resetActive && !highResidueFoods.isEmpty { resetCard }
                safetyCard
                if !survive.fermentedCaution.isEmpty { fermentCautionCard }
                if !survive.hiddenIngredientPrompts.isEmpty { hiddenIngredientCard }

                Text("Safety here is a per-serving guide, not a verdict, your own logs are the real signal.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, theme.metrics.space2)
            }
            .padding(theme.metrics.space4)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .task {
            guard let repo = appState?.repository, let reset = try? await repo.fetchSurviveReset() else { return }
            resetActive = reset.endedAt == nil && reset.pausedAt == nil && reset.phase == "reset"
        }
    }

    /// During the low-residue reset, FODMAP-safe is misleading for high-fiber foods.
    /// This headline flags them as "not for this phase" (R4 / Fence 6).
    private var resetCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Label("Not for this phase", systemImage: "hand.raised.fill")
                    .font(theme.typography.body(weight: .semibold))
                    .foregroundStyle(theme.colors.secondary)
                Text("\(highResidueFoods.joined(separator: ", ")) are higher-residue. They're gentle on many guts, but best saved until you're ramping fiber back. Low-FODMAP isn't the same as low-residue.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(theme.colors.secondary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
    }

    private var safetyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                SectionHeader(title: "FODMAP safety")
                if rows.isEmpty {
                    Text("No FODMAP data for these foods yet.")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: theme.metrics.space1) {
                        HStack(spacing: theme.metrics.space2) {
                            Text(row.foodName)
                                .font(theme.typography.body(weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                            Spacer()
                            SafetyChip(safety: row.safety)
                        }
                        ForEach(row.testingGroups) { group in
                            Label("Contains \(group.shortName), logging for your challenge.",
                                  systemImage: "target")
                                .font(theme.typography.caption(weight: .medium))
                                .foregroundStyle(theme.colors.primary)
                        }
                    }
                    if row.id != rows.last?.id {
                        Divider().overlay(theme.colors.divider)
                    }
                }
            }
        }
    }

    private var fermentCautionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Label("Fermented foods", systemImage: "leaf")
                    .font(theme.typography.body(weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("\(survive.fermentedCaution.joined(separator: ", ")), great for many guts, but ferments can provoke a histamine-sensitive day. Worth noting how you feel.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private var hiddenIngredientCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Label("Worth a quick check", systemImage: "questionmark.circle")
                    .font(theme.typography.body(weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                ForEach(survive.hiddenIngredientPrompts) { prompt in
                    Text(prompt.prompt)
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
    }
}

/// Medical-allergy alert, serious and clear even on the calm Survive surface
/// (SPEC §9: `medical_allergy` is LOUD across both modes).
struct SrvAllergyBanner: View {
    @Environment(\.theme) private var theme
    let alerts: [AllergyAlert]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                ForEach(alerts, id: \.foodName) { alert in
                    Label("Contains \(alert.foodName), this is on your allergy list.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.error)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Allergy alert. " + alerts.map { "Contains \($0.foodName)." }.joined(separator: " "))
    }
}
