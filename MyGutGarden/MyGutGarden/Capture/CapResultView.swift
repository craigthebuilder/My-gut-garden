//
//  CapResultView.swift
//  MyGutGarden, Module B insight hand-off (SPEC §11, Seams.ConfirmedMeal).
//
//  The meal is already auto-logged (Batch C). This screen surfaces, in strict order:
//    1. The LOUD allergy banner (rule #1) - ALWAYS rendered first, before any
//       insight content, from response.allergyAlerts (flag_tier=allergy).
//    2. A SOFT sensitivity notice inside the overview, from response.sensitivityFlags
//       (flag_tier=sensitivity). The food is still eaten + logged; calm, never an alarm.
//    3. The per-photo insight (Module C via the injected presenter; B never imports C).
//  Both flag tiers are server-computed and carried on `response`. A top-left ✕ exits.
//  Tokens only (rule #5).
//

import SwiftUI

struct CapResultScreen: View {
    @Environment(\.theme) private var theme
    @Bindable var model: CapCaptureModel
    let presenter: (any MealInsightPresenting)?

    @State private var editModel: CapEditMealModel?
    @State private var allergyAcknowledged = false

    /// The LOUD allergy gate blocks the overview until acknowledged (rule #1).
    private var showAllergyGate: Bool { !model.allergyAlerts.isEmpty && !allergyAcknowledged }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showAllergyGate {
                allergyGate                                                // BEFORE the overview
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.metrics.space5) {
                        CapAllergyBanner(alerts: model.allergyAlerts)      // persistent reminder at top
                        CapSensitivityNotice(flags: model.sensitivityFlags) // soft, in-overview
                        CapUnmatchedNote(names: model.unmatchedItems.map(\.visionName))
                        insight
                        actions
                    }
                    .padding(theme.metrics.space5)
                    .padding(.top, theme.metrics.space5)                   // clear the ✕
                }
            }
            dismissButton
        }
        .sheet(item: $editModel) { editor in
            CapEditMealView(model: editor) { editModel = nil }
        }
    }

    // MARK: LOUD allergy gate — shown BEFORE the overview, must be acknowledged (rule #1)

    private var allergyGate: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(theme.colors.error)
            Text("Allergy heads-up")
                .font(theme.typography.display(30))
                .foregroundStyle(theme.colors.error)
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                ForEach(model.allergyAlerts, id: \.foodName) { alert in
                    Text("Contains \(alert.foodName), flagged as an allergy.")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                }
            }
            Text("You added this to your allergy list. Double-check the dish before you eat.")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "I understand", systemImage: "checkmark") {
                allergyAcknowledged = true
            }
            Spacer()
        }
        .padding(theme.metrics.space5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.colors.error.opacity(0.08).ignoresSafeArea())
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

    // MARK: Insight + actions

    @ViewBuilder
    private var insight: some View {
        if let meal = model.confirmedMeal {
            if let presenter {
                presenter.insightView(for: meal)
            } else {
                CapFallbackSummary(response: meal.response)
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

// MARK: - Unmatched foods ("when unsure, flag it", SPEC §4)

/// The camera named these but the catalogue couldn't resolve them, so they are
/// NOT counted — say so instead of dropping them silently (owner testing find,
/// 2026-07-07: "the model identified purple sweet potato but the app didn't log
/// it"). The full vision result is stored on the meal, so the owner's
/// unmatched-gap query (TESTING_GUIDE.md) picks these up for catalogue fixes.
struct CapUnmatchedNote: View {
    @Environment(\.theme) private var theme
    let names: [String]

    var body: some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                HStack(spacing: theme.metrics.space2) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(theme.colors.secondary)
                    Text("Spotted, but new to us")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                }
                Text(names.joined(separator: ", "))
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textPrimary)
                Text("The catalogue doesn't know these yet, so they aren't counted. They've been noted — or add a close match yourself via \u{201C}Edit this meal\u{201D}.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(theme.metrics.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.secondary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - LOUD allergy banner (flag_tier=allergy only, §9 / rule #1)

/// Always rendered before any insight content, never suppressed, and entirely
/// independent of the soft sensitivity notice (the two tiers are never merged).
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

// MARK: - Soft sensitivity notice (calm, in-overview, never an alarm, §9)

/// A gentle heads-up for foods on the user's `sensitivity` list. The food is still
/// eaten + logged; this only reminds them they're keeping an eye on it. Warning
/// tint + a warning sign, never the LOUD error styling reserved for allergies.
struct CapSensitivityNotice: View {
    @Environment(\.theme) private var theme
    let flags: [SensitivityFlag]

    var body: some View {
        if !flags.isEmpty {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                ForEach(flags) { flag in
                    HStack(alignment: .top, spacing: theme.metrics.space2) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(theme.colors.warning)
                        Text("You're keeping an eye on \(flag.foodName). It's on your list.")
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(theme.metrics.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.warning.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Built-in fallback summary (used only when no presenter is injected)

/// A minimal, honest per-photo summary. Reads the shared Phase-0 join helpers so
/// it never invents nutrition numbers (rule #2). The LOUD allergy banner + the
/// soft sensitivity notice are rendered above by CapResultScreen.
struct CapFallbackSummary: View {
    @Environment(\.theme) private var theme
    let response: RecognitionResponse

    var body: some View {
        let insights = FoodAttributeJoin.thriveInsights(response)
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            Text("Meal logged")
                .font(theme.typography.display(28))
                .foregroundStyle(theme.colors.primary)

            Card {
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
    }
}
