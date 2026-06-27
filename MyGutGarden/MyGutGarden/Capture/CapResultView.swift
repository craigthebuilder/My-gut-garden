//
//  CapResultView.swift
//  MyGutGarden, Module B insight hand-off (SPEC §11, Seams.ConfirmedMeal).
//
//  The meal is already auto-logged (Batch C). This screen surfaces the insight and
//  the camera flagging layers, in strict order:
//    LAYER 1 (LOUD, rule #1): the medical_allergy red banner - ALWAYS rendered
//      first, independent of the soft pass, even mid-celebration.
//    LAYER 2 (soft, the user's own notes, rules #4/#8): suspect heads-up, avoid
//      soft flag, reintro over-eating nudge, and the "How did it feel?" card.
//  Then the mode-specific insight (Module C/E via the injected presenter; B never
//  imports C/E). A top-left ✕ exits the 4-plants page. Tokens only (rule #5).
//

import SwiftUI

struct CapResultScreen: View {
    @Environment(\.theme) private var theme
    @Bindable var model: CapCaptureModel
    let presenter: (any MealInsightPresenting)?

    @State private var editModel: CapEditMealModel?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.metrics.space5) {
                    CapAllergyBanner(alerts: model.allergyAlerts)          // LAYER 1, always first
                    softFlags                                              // LAYER 2 (soft)
                    reintroNudge
                    reintroFeelingCard
                    insight
                    actions
                }
                .padding(theme.metrics.space5)
                .padding(.top, theme.metrics.space5)                      // clear the ✕
            }
            dismissButton
        }
        .sheet(item: $editModel) { editor in
            CapEditMealView(model: editor) { editModel = nil }
        }
    }

    // MARK: Exit (top-left ✕)

    private var dismissButton: some View {
        Button { model.reset() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(theme.metrics.space4)
        .accessibilityLabel("Close")
    }

    // MARK: LAYER 2 soft flags (calm, user-framed, never an alarm)

    @ViewBuilder
    private var softFlags: some View {
        if let meal = model.confirmedMeal {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                ForEach(meal.suspectFoodIds, id: \.self) { foodId in
                    CapSoftFlag(
                        systemImage: "eye",
                        text: "You've got \(model.foodName(for: foodId)) on your list to keep an eye on."
                    )
                }
                ForEach(meal.avoidFoodIds, id: \.self) { foodId in
                    CapSoftFlag(
                        systemImage: "arrow.uturn.backward",
                        text: "You set \(model.foodName(for: foodId)) aside for now. Want to revisit it?"
                    )
                }
            }
        }
    }

    // MARK: Reintro coaching (over-eating nudge + feeling card)

    @ViewBuilder
    private var reintroNudge: some View {
        if model.confirmedMeal?.reintroFoodId != nil, model.reintroPortion == .lots {
            CapSoftFlag(
                systemImage: "tortoise",
                text: "That looks like a lot for a food you're still checking. Going slow tells you more."
            )
        }
    }

    @ViewBuilder
    private var reintroFeelingCard: some View {
        if let id = model.confirmedMeal?.reintroFoodId {
            Card {
                VStack(alignment: .leading, spacing: theme.metrics.space3) {
                    Text("How did the \(model.foodName(for: id)) feel?")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    if let answer = model.reintroAnswer {
                        Text(answer ? "Noted, felt fine. That counts toward bringing it back."
                                     : "Noted, a bit rough. No rush, you can try again later.")
                            .font(theme.typography.caption())
                            .foregroundStyle(theme.colors.textSecondary)
                    } else {
                        HStack(spacing: theme.metrics.space3) {
                            feelingButton("Felt fine", feltFine: true)
                            feelingButton("A bit rough", feltFine: false)
                        }
                    }
                }
            }
        }
    }

    private func feelingButton(_ title: String, feltFine: Bool) -> some View {
        Button { Task { await model.recordReintroFeeling(feltFine) } } label: {
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
        .accessibilityLabel(title)
    }

    // MARK: Insight + actions

    @ViewBuilder
    private var insight: some View {
        if let meal = model.confirmedMeal {
            if let presenter {
                presenter.insightView(for: meal)
            } else {
                CapFallbackSummary(response: meal.response, mode: model.mode)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: theme.metrics.space2) {
            if model.canEditMeal {
                SecondaryButton(title: "Edit this meal", systemImage: "slider.horizontal.3") {
                    editModel = model.makeEditModel()
                }
            }
            SecondaryButton(title: "Snap another", systemImage: "camera.fill") {
                model.reset()
            }
        }
    }
}

// MARK: - LAYER 1 LOUD allergy banner (medical_allergy only, §9 / rule #1)

/// Always rendered before any insight content, in both modes, never suppressed,
/// and entirely independent of the soft suspect/avoid pass (the two passes are
/// never merged). Fires even if the same food is also in Avoid.
struct CapAllergyBanner: View {
    @Environment(\.theme) private var theme
    let alerts: [AllergyAlert]

    var body: some View {
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                ForEach(alerts, id: \.foodName) { alert in
                    HStack(spacing: theme.metrics.space2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Contains \(alert.foodName), flagged as an allergy.")
                            .font(theme.typography.body(weight: .semibold))
                    }
                    .foregroundStyle(theme.colors.error)
                }
            }
            .padding(theme.metrics.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.error.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - LAYER 2 soft flag (calm, informational, never an alarm)

struct CapSoftFlag: View {
    @Environment(\.theme) private var theme
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: theme.metrics.space2) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.colors.primary)
            Text(text)
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(theme.metrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface,
                    in: RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Built-in fallback summary (used only when no presenter is injected)

/// A minimal, honest per-photo summary. Reads the shared Phase-0 join helpers so
/// it never invents nutrition numbers (rule #2) and keeps Survive non-clinical
/// (rule #4). The LOUD allergy banner is rendered above by CapResultScreen.
struct CapFallbackSummary: View {
    @Environment(\.theme) private var theme
    let response: RecognitionResponse
    let mode: AppMode

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            Text("Meal logged")
                .font(theme.typography.display(28))
                .foregroundStyle(theme.colors.primary)

            if mode == .thrive { thrive } else { survive }
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
                Text("3 P's: \(insights.threePs.count)/3" + (insights.threePs.allThree ? " checked" : ""))
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
