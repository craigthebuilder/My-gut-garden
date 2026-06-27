//
//  SrvAvoidView.swift
//  MyGutGarden, Module E. The "On pause" tab (Batch E).
//
//  "Foods you're setting aside for now", reversible, never a verdict. Every tile
//  carries a Revisit affordance, "setting aside" is a pause, not a sentence
//  (rules #4/#7). `avoid` is NOT an exclusion and is never merged with exclusions
//  (rule #1). Reached only via the user-tapped move-to-Avoid OFFER (see Re-intro).
//  BANNED: "your intolerances", any sensitivity score.
//

import SwiftUI

struct SrvAvoidView: View {
    @Environment(\.theme) private var theme
    @Bindable var foodStore: FoodStatusStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                let foods = foodStore.avoided()
                SectionHeader(title: foods.isEmpty ? "Nothing on pause"
                              : "\(foods.count) \(foods.count == 1 ? "food" : "foods") on pause")
                if foods.isEmpty {
                    Text("Foods you set aside show up here. You can always bring one back.")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                } else {
                    ForEach(foods, id: \.id) { s in
                        Card {
                            HStack(spacing: theme.metrics.space3) {
                                Image(systemName: "pause.circle").foregroundStyle(theme.colors.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(foodStore.foodName(s.foodId))
                                        .font(theme.typography.body(weight: .medium))
                                        .foregroundStyle(theme.colors.textPrimary)
                                    Text("Set aside for now")
                                        .font(theme.typography.caption())
                                        .foregroundStyle(theme.colors.textSecondary)
                                }
                                Spacer()
                                Button("Revisit") {
                                    Task { await foodStore.revisit(s) }
                                }
                                .font(theme.typography.caption(weight: .semibold))
                                .foregroundStyle(theme.colors.primary)
                                .accessibilityLabel("Revisit \(foodStore.foodName(s.foodId)), want to try this again")
                            }
                        }
                    }
                }
            }
            .padding(theme.metrics.space4)
        }
    }
}
