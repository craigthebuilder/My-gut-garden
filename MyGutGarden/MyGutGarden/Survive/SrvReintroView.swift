//
//  SrvReintroView.swift
//  MyGutGarden, Module E. The food-suspect Re-intro tab (Batch E; Fence 3).
//
//  Easing ONE food back in at a time. The bar is EVENT-DRIVEN and ADDITIVE: it
//  advances only on (meal-with-the-food AND felt-fine at a real serving), NEVER on
//  elapsed time (the legacy time-based SrvReintroEngine path is FODMAP-only and is
//  not inherited here). Reaching the goal is a GAIN, "you can enjoy it again",
//  never "you got through it". Restriction is never gamified (rule #7).
//
//  🔒 FENCE 3 (RD-REVIEW-REQUIRED): reintroMealsToPass + reintroMinPortionToCount
//  live in GameConfig; nothing clinical is invented here.
//

import SwiftUI

struct SrvReintroView: View {
    @Environment(\.theme) private var theme
    @Bindable var foodStore: FoodStatusStore

    @State private var logPortion: PortionTier = .serving
    @State private var offerDismissed = false

    private let config = GameConfig.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                if let cleared = foodStore.lastClearedFoodName { clearGain(cleared) }
                if let ch = foodStore.activeFoodChallenge {
                    activeCard(ch)
                    if let offerFood = foodStore.shouldOfferAvoid(), !offerDismissed {
                        avoidOffer(offerFood)
                    }
                } else {
                    emptyState
                }
                fenceNote
            }
            .padding(theme.metrics.space4)
        }
    }

    // MARK: Active challenge

    private func activeCard(_ ch: ReintroChallengeRow) -> some View {
        let name = foodStore.foodName(ch.foodId ?? "")   // food_suspect rows always carry food_id (DB CHECK)
        return Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                Text("Testing \(name)")
                    .font(theme.typography.title(18))
                    .foregroundStyle(theme.colors.textPrimary)

                ProgressView(value: Double(foodStore.challengeProgressPct()) / 100)
                    .tint(theme.colors.primary)
                Text("Building toward \(name), \(ch.mealsFeelingFineCount) of \(config.reintroMealsToPass) good meals.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)

                if foodStore.titrationFoodId == ch.foodId {
                    // Coarse-tier titration only, never grams (rule #3).
                    Label("That was a small taste. Try a normal serving next time, a bit more tells you more.",
                          systemImage: "arrow.up.circle")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.secondary)
                }

                Divider().background(theme.colors.divider)

                Text("Just ate \(name)? Log how it felt.")
                    .font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                portionPicker
                HStack(spacing: theme.metrics.space2) {
                    PrimaryButton(title: "Felt fine", systemImage: "checkmark") {
                        record(ch, feltFine: true)
                    }
                    SecondaryButton(title: "A bit rough", systemImage: "cloud") {
                        record(ch, feltFine: false)
                    }
                }

                Button("End this challenge for now") {
                    Task { await foodStore.endActiveChallenge() }
                }
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private var portionPicker: some View {
        HStack(spacing: theme.metrics.space2) {
            ForEach([PortionTier.trace, .serving, .lots], id: \.rawValue) { tier in
                let isOn = logPortion == tier
                Button { logPortion = tier } label: {
                    Text(tier.coarseLabel)
                        .font(theme.typography.caption(weight: isOn ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.metrics.space2)
                        .foregroundStyle(isOn ? theme.colors.surface : theme.colors.textSecondary)
                        .background(isOn ? theme.colors.primary : theme.colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall, style: .continuous))
                }
                .accessibilityLabel("Portion \(tier.coarseLabel)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func record(_ ch: ReintroChallengeRow, feltFine: Bool) {
        offerDismissed = false
        Task {
            await foodStore.recordReintroMeal(foodId: ch.foodId ?? "", mealId: nil, portion: logPortion, feltFine: feltFine)
        }
    }

    // MARK: Avoid offer (a user-tap question, fenced wording)

    private func avoidOffer(_ s: FoodSuspectRow) -> some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                // 🔒 FENCE 1/7 (RD-REVIEW-REQUIRED): never "cannot tolerate".
                Text("Everyone's gut is different, and yours doesn't seem to love \(foodStore.foodName(s.foodId)) right now. Want to set it aside for a while? You can always revisit it.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textPrimary)
                HStack(spacing: theme.metrics.space2) {
                    PrimaryButton(title: "Set aside for now") {
                        Task { await foodStore.moveToAvoid(s) }
                    }
                    SecondaryButton(title: "Keep checking") { offerDismissed = true }
                }
            }
        }
    }

    // MARK: Clear gain (additive, a food RETURNING)

    private func clearGain(_ name: String) -> some View {
        Card {
            HStack(spacing: theme.metrics.space3) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(theme.colors.safetyGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name) is back on the menu")
                        .font(theme.typography.body(weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("You've eaten \(name) and felt fine. Looks like you can enjoy it again.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Text("Nothing in re-intro right now")
                    .font(theme.typography.body(weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("When you're ready, pick a food from Checking and ease it back in, one at a time.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private var fenceNote: some View {
        Text("How many good meals it takes is a starting point your dietitian can tune.")
            .font(theme.typography.caption())
            .foregroundStyle(theme.colors.textSecondary)
    }
}

// MARK: - Coarse portion label (never grams, rule #3)

extension PortionTier {
    var coarseLabel: String {
        switch self {
        case .trace: "A taste"
        case .serving: "A serving"
        case .lots: "A lot"
        }
    }
}
