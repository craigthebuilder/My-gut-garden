//
//  SrvPatternView.swift
//  MyGutGarden — Module E. READ-ONLY rendering of `pattern_assessments`
//  (SPEC §11b, §13; Fence 1) + the red-flag escalation card (SPEC §11b).
//
//  🔒 CRITICAL (CLAUDE.md rule #4): copy stays insight → experiment → "worth
//  raising with a GI." NEVER a diagnosis, a named condition/bug, or an
//  accumulating bad-guy meter. The structured experiment only appears once a
//  pattern is steady (consistent); tentative/emerging stay "still gathering."
//

import SwiftUI

struct SrvPatternCard: View {
    @Environment(\.theme) private var theme
    let presentation: SrvPatternPresentation

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                HStack {
                    SectionHeader(title: "What we're noticing")
                    Spacer()
                    Badge(text: presentation.confidenceLabel, tint: theme.colors.secondary)
                }

                // Insight — the lean, never a label.
                Text(presentation.insight)
                    .font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)

                if let experiment = presentation.experiment {
                    labeled("Try this", experiment, icon: "flask")
                    labeled("Then", presentation.routing, icon: "stethoscope")
                } else {
                    Text("Still gathering signal — keep logging and this will come into focus.")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textSecondary)
                }

                if let evidence = presentation.evidenceSummary {
                    Text(evidence)
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.top, theme.metrics.space1)
                }

                Text("A pattern, not a diagnosis — only a clinician can confirm what's going on.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func labeled(_ label: String, _ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: theme.metrics.space2) {
            Image(systemName: icon)
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.primary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(theme.typography.caption(weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                Text(text)
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textPrimary)
            }
        }
    }
}

/// "Still gathering signal" placeholder when no assessment exists yet (SPEC §13).
struct SrvGatheringSignalCard: View {
    @Environment(\.theme) private var theme
    let loggedDays: Int

    private var remaining: Int { max(0, GameConfig.shared.patternMinDays - loggedDays) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                SectionHeader(title: "What we're noticing")
                if remaining > 0 {
                    Text("\(remaining) more days of logs to spot your first pattern.")
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                } else {
                    Text("Still gathering signal — a pattern will surface as your logs settle.")
                        .font(theme.typography.body(weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                }
                Text("No rush. The more evenings you log, the clearer it gets.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }
}

/// Red-flag escalation — a calm care prompt, never a block (SPEC §6, §11b).
struct SrvRedFlagCard: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                Label(SrvRedFlags.title, systemImage: "cross.case")
                    .font(theme.typography.title(18))
                    .foregroundStyle(theme.colors.textPrimary)
                Text(SrvRedFlags.body)
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
                VStack(alignment: .leading, spacing: theme.metrics.space2) {
                    ForEach(SrvRedFlags.symptoms, id: \.self) { symptom in
                        HStack(alignment: .top, spacing: theme.metrics.space2) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(theme.colors.textSecondary)
                                .padding(.top, 7)
                            Text(symptom)
                                .font(theme.typography.body())
                                .foregroundStyle(theme.colors.textPrimary)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(SrvRedFlags.title + ". " + SrvRedFlags.body + " " + SrvRedFlags.symptoms.joined(separator: ". "))
    }
}
