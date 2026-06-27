//
//  ThrPokedex.swift
//  MyGutGarden, Module C: the Thrive pokédex stack (SPEC §7, §8, §11a).
//
//  Tier-1 (everyone): Plant Garden + Rainbow. Tier-2 (earned, staggered):
//  Phytochemical, gated behind `appState.progression.isTier2Unlocked`. Cross:
//  Fermented Finds (celebrated in Thrive). The Microbial Guild Garden is a Tier-2
//  pokédex too, but it is MODULE D's surface and intentionally not rendered here.
//
//  Collected tiles show rarity outlines; not-yet-collected tiles grey out
//  (CollectibleTile handles the greying, the same neutral treatment §9 uses).
//

import SwiftUI
import Observation

// MARK: - Loader

@MainActor
@Observable
final class ThrPokedexModel {
    struct PlantEntry: Identifiable, Sendable {
        let id: String
        let name: String
        let rarity: RarityTier
        let collected: Bool
    }

    var plants: [PlantEntry] = []
    var collectedPlantCount = 0

    var phytochemicals: [ThrPhytochemicalRow] = []
    var collectedPhytoNames: Set<String> = []

    var fermentedFinds: [String] = []      // foods logged that carry live cultures

    var isLoaded = false

    func load(appState: AppState, latestMeal: ConfirmedMeal?) async {
        // Latest meal seeds "collected" sets so the demo/offline path looks alive.
        if let meal = latestMeal {
            let attrs = FoodAttributeJoin.surfacedAttributes(meal.response)
            collectedPhytoNames.formUnion(attrs.flatMap { $0.phytochemicals.map(\.name) })
            fermentedFinds = Array(Set(attrs.filter(\.isFermented).map(\.canonicalName))).sorted()
        }

        guard let repo = appState.repository else { isLoaded = true; return }

        let allPlants: [PlantRow] = (try? await repo.fetchPlants()) ?? []
        let owned: [UserPlantCollectionRow] = (try? await repo.select("user_plant_collection")) ?? []
        let phytos: [ThrPhytochemicalRow] = (try? await repo.select("phytochemicals", order: "class")) ?? []

        let ownedIds = Set(owned.map(\.plantId))
        plants = allPlants.map {
            PlantEntry(id: $0.id, name: $0.name, rarity: $0.rarityTier, collected: ownedIds.contains($0.id))
        }
        collectedPlantCount = plants.filter(\.collected).count
        phytochemicals = phytos
        isLoaded = true
    }
}

// MARK: - Hub

struct ThrPokedexView: View {
    @Environment(\.theme) private var theme
    let appState: AppState
    var latestMeal: ConfirmedMeal? = nil

    @State private var model = ThrPokedexModel()

    private var tier2Unlocked: Bool { appState.progression.isTier2Unlocked }

    var body: some View {
        ScrollView {
            VStack(spacing: theme.metrics.space4) {
                Card {
                    VStack(spacing: theme.metrics.space2) {
                        NavigationLink {
                            ThrPlantGardenView(model: model)
                        } label: {
                            ThrNavRow(icon: "leaf.fill", title: "Plant Garden",
                                      subtitle: collectedSubtitle)
                        }
                        Divider().overlay(theme.colors.divider)
                        NavigationLink {
                            ThrRainbowPokedexView(appState: appState, latestMeal: latestMeal)
                        } label: {
                            ThrNavRow(icon: "circle.hexagongrid.fill", title: "Rainbow",
                                      subtitle: "Six color groups, what each does")
                        }
                        Divider().overlay(theme.colors.divider)
                        NavigationLink {
                            ThrFermentedFindsView(model: model)
                        } label: {
                            ThrNavRow(icon: "drop.fill", title: "Fermented Finds",
                                      subtitle: fermentedSubtitle)
                        }
                        Divider().overlay(theme.colors.divider)
                        if tier2Unlocked {
                            NavigationLink {
                                ThrPhytochemicalPokedexView(appState: appState)
                            } label: {
                                ThrNavRow(icon: "atom", title: "Phytochemicals",
                                          subtitle: "Categories, compounds, and what each does")
                            }
                        } else {
                            ThrNavRow(icon: "atom", title: "Phytochemicals",
                                      subtitle: "Unlocks after your first full week",
                                      locked: true)
                        }
                    }
                }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Field guide")
        .task { await model.load(appState: appState, latestMeal: latestMeal) }
    }

    private var collectedSubtitle: String {
        model.collectedPlantCount > 0
            ? "\(model.collectedPlantCount) plants collected for life"
            : "Start your lifetime collection"
    }
    private var fermentedSubtitle: String {
        model.fermentedFinds.isEmpty ? "Probiotic foods you've logged" : "\(model.fermentedFinds.count) found"
    }
}

// MARK: - Plant Garden (Tier 1, lifetime collection with rarity)

struct ThrPlantGardenView: View {
    @Environment(\.theme) private var theme
    let model: ThrPokedexModel

    @State private var suggestion: ThrPokedexModel.PlantEntry?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    /// Only the plants the user has actually eaten (collected). Un-eaten plants
    /// are NOT shown as locked silhouettes, they arrive via "Suggest a plant".
    private var collected: [ThrPokedexModel.PlantEntry] { model.plants.filter(\.collected) }
    private var uneaten: [ThrPokedexModel.PlantEntry] { model.plants.filter { !$0.collected } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                if !uneaten.isEmpty {
                    SecondaryButton(title: "Suggest a plant to try", systemImage: "dice") {
                        suggestion = uneaten.randomElement()
                    }
                }
                if collected.isEmpty {
                    ThrEmptyState(icon: "leaf.fill",
                                  title: "Your garden's just getting started",
                                  message: "Snap a meal and the plants you eat fill this field guide, kept for life.")
                } else {
                    LazyVGrid(columns: columns, spacing: theme.metrics.space3) {
                        ForEach(collected) { plant in
                            CollectibleTile(name: plant.name, rarity: plant.rarity, collected: true) {
                                IllustrationPlaceholder(systemImage: "leaf.fill",
                                                        tint: plant.rarity.accent(theme))
                            }
                        }
                    }
                }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Plant Garden")
        .sheet(item: $suggestion) { plant in
            ThrPlantSuggestionSheet(plant: plant)
        }
    }
}

/// A gentle "try this next" reveal for a plant the user has never eaten. An
/// invitation to add variety, never a chore or a miss.
struct ThrPlantSuggestionSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let plant: ThrPokedexModel.PlantEntry

    var body: some View {
        VStack(spacing: theme.metrics.space4) {
            FieldGuideCard(
                eyebrow: "New to your garden",
                title: plant.name,
                subtitle: "You haven't eaten this one yet.",
                bodyText: "Slip it into a meal this week to add it to your lifetime collection.",
                rarity: plant.rarity
            ) {
                IllustrationPlaceholder(systemImage: "leaf.fill", tint: plant.rarity.accent(theme))
            }
            PrimaryButton(title: "Got it", action: { dismiss() })
        }
        .padding(theme.metrics.space5)
        .frame(maxWidth: .infinity)
        .background(theme.colors.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

// MARK: - Rainbow + Phytochemical pokédex
// (rich versions live in ThrFieldGuideDepth.swift, R3 Batch B)

// MARK: - Fermented Finds (cross-mode; celebrated in Thrive)

struct ThrFermentedFindsView: View {
    @Environment(\.theme) private var theme
    let model: ThrPokedexModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                Card {
                    HStack(spacing: theme.metrics.space4) {
                        StatPill(value: "\(model.fermentedFinds.count)", label: "fermented finds")
                        VStack(alignment: .leading, spacing: theme.metrics.space1) {
                            Text("Live cultures love company")
                                .font(theme.typography.body(weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                            Text("A daily fermented food keeps your probiotic P ticking.")
                                .font(theme.typography.caption())
                                .foregroundStyle(theme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if model.fermentedFinds.isEmpty {
                    ThrEmptyState(icon: "drop.fill",
                                  title: "No fermented finds yet",
                                  message: "Yogurt, kimchi, miso, kefir, log one to start the collection.")
                } else {
                    ForEach(model.fermentedFinds, id: \.self) { name in
                        Card {
                            HStack(spacing: theme.metrics.space3) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(theme.colors.success)
                                Text(name).font(theme.typography.body()).foregroundStyle(theme.colors.textPrimary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Fermented Finds")
    }
}

// MARK: - Shared empty state

struct ThrEmptyState: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: theme.metrics.space3) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(theme.colors.secondary)
            Text(title)
                .font(theme.typography.title())
                .foregroundStyle(theme.colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(theme.metrics.space5)
        .accessibilityElement(children: .combine)
    }
}
