//
//  OnbGardener.swift
//  MyGutGarden, Module A — naming the gut gardener (owner, 2026-07-09).
//
//  The gardener is the app's guiding persona: it greets on the garden map,
//  fronts the setup tour, and signs the (still deterministic) guardian nudges.
//  The user names it in onboarding from a friendly shortlist, or types their
//  own. Persisted to users.gardener_name; the "Meet <name>" intro frame and
//  everywhere downstream read it back.
//

import Foundation
import SwiftUI

enum OnbGardener {
    static let defaultName = "Sprout"

    /// The suggested shortlist (owner's picks). The user may also type a custom name.
    static let suggestions = ["Sprout", "Bean", "Berry", "Root", "Oak"]

    /// Trim, cap length, and never allow empty (falls back to the default).
    static func sanitized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return defaultName }
        return String(trimmed.prefix(20))
    }
}

// MARK: - The naming step

struct OnbGardenerStep: View {
    @Environment(\.theme) private var theme
    @Bindable var vm: OnbViewModel

    var body: some View {
        OnbStepScaffold(
            title: "Meet your gut gardener",
            subtitle: "A friendly guide who'll help you feed your garden at a pace your gut is happy with. Give them a name — you can change it later."
        ) {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                seedling

                FlowChips(items: OnbGardener.suggestions,
                          isSelected: { vm.gardenerName == $0 },
                          onTap: { vm.gardenerName = $0 })

                VStack(alignment: .leading, spacing: theme.metrics.space1) {
                    Text("Or name your own")
                        .font(theme.typography.caption(weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                    TextField("Gardener's name", text: $vm.gardenerName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }
            }
        }
    }

    /// A little seedling that "introduces itself" with the chosen name.
    private var seedling: some View {
        HStack(spacing: theme.metrics.space3) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 40))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.colors.primary)
            Text("\u{201C}Hi, I'm \(OnbGardener.sanitized(vm.gardenerName)) \u{2014} let's grow.\u{201D}")
                .font(theme.typography.body(weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.metrics.space4)
        .background(theme.colors.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your gardener is named \(OnbGardener.sanitized(vm.gardenerName))")
    }
}

/// A simple wrapping row of selectable chips (the onboarding shortlist).
private struct FlowChips: View {
    @Environment(\.theme) private var theme
    let items: [String]
    let isSelected: (String) -> Bool
    let onTap: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: theme.metrics.space2) {
            ForEach(items, id: \.self) { item in
                OnbChip(label: item, isSelected: isSelected(item), action: { onTap(item) })
            }
        }
    }
}
