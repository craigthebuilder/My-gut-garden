//
//  SrvTimelineView.swift
//  MyGutGarden, Module E. The "Timeline" tab (Batch E).
//
//  A read-only, chronological list of the user's OWN observations about their
//  food list, what they started checking, eased back in, cleared, or set aside.
//  Non-clinical framing: these are notes worth raising with a dietitian, never an
//  app diagnosis or a meter (rules #4/#8).
//

import SwiftUI

struct SrvTimelineView: View {
    @Environment(\.theme) private var theme
    @Bindable var foodStore: FoodStatusStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                let events = foodStore.timelineEvents()
                if events.isEmpty {
                    Card {
                        Text("As you add and try foods, your notes will line up here.")
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(events) { event in
                        Card {
                            HStack(spacing: theme.metrics.space3) {
                                Image(systemName: event.systemImage)
                                    .foregroundStyle(theme.colors.primary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.summary)
                                        .font(theme.typography.body())
                                        .foregroundStyle(theme.colors.textPrimary)
                                    Text(event.date.formatted(.dateTime.weekday(.wide).month().day()))
                                        .font(theme.typography.caption())
                                        .foregroundStyle(theme.colors.textSecondary)
                                }
                                Spacer()
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(event.summary), \(event.date.formatted(.dateTime.month().day()))")
                    }
                    Text("These are your own observations, worth raising with a dietitian.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.top, theme.metrics.space2)
                }
            }
            .padding(theme.metrics.space4)
        }
    }
}
