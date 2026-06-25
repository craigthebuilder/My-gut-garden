//
//  CapResultView.swift
//  MyGutGarden — Module B insight hand-off (SPEC §11, Seams.ConfirmedMeal).
//
//  Once a meal is logged, Module B hands the `ConfirmedMeal` to the mode-specific
//  insight view supplied by C (Thrive) or E (Survive) through the
//  `mealInsightPresenter` environment seam — B never imports C/E. When no
//  presenter is injected (e.g. the offline shell), a calm built-in summary
//  stands in so the flow always completes.
//

import SwiftUI

struct CapResultScreen: View {
    @Environment(\.theme) private var theme
    let model: CapCaptureModel
    let presenter: (any MealInsightPresenting)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space5) {
                if let meal = model.confirmedMeal {
                    if let presenter {
                        presenter.insightView(for: meal)
                    } else {
                        CapFallbackSummary(response: meal.response, mode: model.mode)
                    }
                }
                SecondaryButton(title: "Snap another", systemImage: "camera.fill") {
                    model.reset()
                }
            }
            .padding(theme.metrics.space5)
        }
    }
}

// MARK: - Built-in fallback summary (used only when no presenter is injected)

/// A minimal, honest per-photo summary. Reads the shared Phase-0 join helpers so
/// it never invents nutrition numbers (rule #2) and keeps Survive non-clinical
/// (rule #4). Allergy alerts stay LOUD in both modes (§9).
struct CapFallbackSummary: View {
    @Environment(\.theme) private var theme
    let response: RecognitionResponse
    let mode: AppMode

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            Text("Meal logged")
                .font(theme.typography.display(28))
                .foregroundStyle(theme.colors.primary)

            allergyAlerts

            if mode == .thrive { thrive } else { survive }
        }
    }

    @ViewBuilder
    private var allergyAlerts: some View {
        ForEach(response.allergyAlerts, id: \.foodName) { alert in
            Label("Contains \(alert.foodName) — flagged allergy", systemImage: "exclamationmark.triangle.fill")
                .font(theme.typography.body(weight: .semibold))
                .foregroundStyle(theme.colors.error)
        }
    }

    private var thrive: some View {
        let insights = FoodAttributeJoin.thriveInsights(response)
        return Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                StatPill(value: "\(insights.plantNames.count)", label: "plants")
                if !insights.plantNames.isEmpty {
                    Text(insights.plantNames.joined(separator: ", "))
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textPrimary)
                }
                if !insights.colorsHit.isEmpty {
                    Text("Rainbow: " + insights.colorsHit
                        .map { $0.replacingOccurrences(of: "_", with: " ") }
                        .joined(separator: ", "))
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Text("3 P's: \(insights.threePs.count)/3" + (insights.threePs.allThree ? " ✓" : ""))
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private var survive: some View {
        let insights = FoodAttributeJoin.surviveInsights(response)
        return Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                Text("FODMAP safety")
                    .font(theme.typography.body(weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                ForEach(insights.safety, id: \.foodName) { entry in
                    HStack {
                        Text(entry.foodName)
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textPrimary)
                        Spacer()
                        SafetyChip(safety: entry.safety)
                    }
                }
            }
        }
    }
}
