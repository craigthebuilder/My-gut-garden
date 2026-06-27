//
//  SrvResetView.swift
//  MyGutGarden, Module E. The low-residue reset (Batch E, 🔒 Fence 6).
//
//  The sharpest disordered-eating risk in the app, so the duty-of-care MACHINERY
//  ships in v1 while the clinical CONTENT is fenced (// RD-REVIEW-REQUIRED, seeded
//  in `reset_instructions`). Machinery that is NON-NEGOTIABLE here:
//    • user-initiated ONLY, reachable solely from Survive,
//    • a PERSISTENT (non-dismissible) clinician disclaimer naming high-risk groups,
//    • an always-visible, frictionless "Pause anytime" (no "are you sure?"),
//    • progress is RELIEF ONLY ("days feeling better"), never a restriction counter.
//  NEVER "carnivore", never a named condition/microbe, never "heal/fix/repair".
//

import SwiftUI

struct SrvResetView: View {
    @Environment(\.theme) private var theme
    @State private var model: SrvResetModel

    init(store: SrvStore) {
        _model = State(initialValue: SrvResetModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space4) {
                if let reset = model.reset, reset.phase != SrvResetPhase.graduated.rawValue, reset.endedAt == nil {
                    activeReset(reset)
                } else {
                    startScreen
                }
            }
            .padding(theme.metrics.space4)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("A fresh start")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    // MARK: Start screen

    private var startScreen: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space4) {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Text("Give your gut a break")
                    .font(theme.typography.display(26))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("A low-residue reset: for a little while we keep food very gentle to let things settle, then slowly rebuild and help you find what your gut can handle.")
                    .font(theme.typography.body())
                    .foregroundStyle(theme.colors.textSecondary)
            }

            clinicianDisclaimer   // PERSISTENT, non-dismissible (Fence 6 machinery)

            Text(SrvResetEngine.typicalDurationCopy)
                .font(theme.typography.caption())
                .foregroundStyle(theme.colors.textSecondary)

            PrimaryButton(title: "Start a fresh start", systemImage: "leaf") {
                Task { await model.start() }
            }
            if let error = model.errorMessage {
                Text(error).font(theme.typography.caption()).foregroundStyle(theme.colors.error)
            }
        }
    }

    /// Non-dismissible clinician disclaimer naming the high-risk groups (Fence 6).
    /// // RD-REVIEW-REQUIRED
    private var clinicianDisclaimer: some View {
        Card {
            HStack(alignment: .top, spacing: theme.metrics.space3) {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(theme.colors.error)
                Text("This is a personal experiment, not medical advice. If you have any health condition, especially IBD, an autoimmune condition, diabetes, or a history of disordered eating, or if you're pregnant, talk to your doctor first. This isn't right for everyone.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    // MARK: Active reset

    private func activeReset(_ reset: SurviveResetRow) -> some View {
        let phase = SrvResetPhase(rawValue: reset.phase) ?? .reset
        return VStack(alignment: .leading, spacing: theme.metrics.space4) {
            // Always-visible, frictionless Pause (no confirm). Fence 6 machinery.
            pauseBar(reset)

            if reset.pausedAt != nil {
                pausedNote
            } else {
                reliefCard
                phaseCard(phase)
                if SrvResetEngine.clinicianPromptNeeded(state: reset, now: Date()) {
                    clinicianCheckpoint
                }
                actions(reset, phase)
            }

            clinicianDisclaimer   // stays present throughout (persistent)
        }
    }

    private func pauseBar(_ reset: SurviveResetRow) -> some View {
        HStack {
            Text(reset.pausedAt != nil ? "Paused" : "In progress")
                .font(theme.typography.caption(weight: .medium))
                .foregroundStyle(theme.colors.textSecondary)
            Spacer()
            if reset.pausedAt != nil {
                Button("Resume") { Task { await model.resume() } }
                    .font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.primary)
            } else {
                Button("Pause anytime") { Task { await model.pause() } }
                    .font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.primary)
                    .accessibilityHint("Pauses right away, nothing is lost")
            }
        }
    }

    private var pausedNote: some View {
        Card {
            Text("Taking a break. Everything you've logged stays exactly where it is, resume whenever you're ready.")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// RELIEF ONLY. No day-counter, no compliance, no streak, no bar denominator.
    private var reliefCard: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space1) {
                Text(reliefHeadline)
                    .font(theme.typography.display(24))
                    .foregroundStyle(theme.colors.primary)
                Text("We're watching how you feel, not counting days. Off days carry no penalty.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private var reliefHeadline: String {
        let n = model.reliefDaysThisWeek
        return n == 0 ? "Settling in" : "You've had \(n) \(n == 1 ? "day" : "days") feeling better this week"
    }

    private func phaseCard(_ phase: SrvResetPhase) -> some View {
        Card {
            VStack(alignment: .leading, spacing: theme.metrics.space2) {
                Text(phase.title)
                    .font(theme.typography.title(18))
                    .foregroundStyle(theme.colors.textPrimary)
                ForEach(model.instructions(for: phase), id: \.id) { instruction in
                    VStack(alignment: .leading, spacing: theme.metrics.space1) {
                        Text(instruction.instructionCopy)
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textSecondary)
                        if !instruction.foodSuggestions.isEmpty {
                            Text("Gentle additions: \(instruction.foodSuggestions.joined(separator: ", "))")
                                .font(theme.typography.caption())
                                .foregroundStyle(theme.colors.secondary)
                        }
                    }
                }
                Text("Guidance your dietitian can tune.")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private var clinicianCheckpoint: some View {
        Card {
            HStack(alignment: .top, spacing: theme.metrics.space3) {
                Image(systemName: "stethoscope").foregroundStyle(theme.colors.warning)
                VStack(alignment: .leading, spacing: theme.metrics.space2) {
                    Text("It's been a couple of weeks and things haven't settled. This is a good moment to check in with a doctor or dietitian.")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textPrimary)
                    Button("Got it") { Task { await model.markClinicianPrompted() } }
                        .font(theme.typography.caption(weight: .semibold))
                        .foregroundStyle(theme.colors.primary)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ reset: SurviveResetRow, _ phase: SrvResetPhase) -> some View {
        if phase == .reset, SrvResetEngine.canAdvance(from: .reset, symptomFreeDays: model.reliefDaysThisWeek) {
            PrimaryButton(title: "I'm feeling better, add foods back", systemImage: "arrow.up.forward") {
                Task { await model.advanceToReintroduction() }
            }
        }
        if SrvResetEngine.graduationReady(state: reset) {
            PrimaryButton(title: "Move to Thrive", systemImage: "sun.max") {
                Task { await model.graduate() }
            }
        }
    }
}

// MARK: - Reset view-model

@MainActor
@Observable
final class SrvResetModel {
    private let store: SrvStore
    private(set) var reset: SurviveResetRow?
    private(set) var allInstructions: [ResetInstructionRow] = []
    var errorMessage: String?

    init(store: SrvStore) { self.store = store }

    /// RELIEF metric: days this week that read as "feeling good" (no symptom above
    /// mild), from the same merged daily aggregation that feeds the streak. This is
    /// the ONLY progress number the reset surfaces (GameConfig.resetProgressMetric).
    var reliefDaysThisWeek: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return store.mergedDailySymptoms()
            .filter { $0.date >= cutoff && SrvStreakEngine.outcome(for: $0.symptoms) == .feltGood }
            .count
    }

    func instructions(for phase: SrvResetPhase) -> [ResetInstructionRow] {
        allInstructions.filter { $0.phase == phase.rawValue }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func load() async {
        guard let repo = store.appState.repository else { return }
        reset = try? await repo.fetchSurviveReset()
        if let rows = try? await repo.fetchResetInstructions() { allInstructions = rows }
        await persistReliefDays()
    }

    func start() async {
        guard let repo = store.appState.repository, let uid = store.appState.profile?.id else {
            errorMessage = "Connect an account to start a reset."
            return
        }
        // Clean (re)start: clear any prior pause / end / graduation state so an
        // upsert over an old row begins fresh.
        let body: [String: PGValue] = [
            "user_id": .string(uid), "phase": .string(SrvResetPhase.reset.rawValue),
            "symptom_free_days": .int(reliefDaysThisWeek),
            "started_at": .date(Date()), "paused_at": .null, "ended_at": .null,
            "graduated_at": .null, "clinician_prompted_at": .null, "no_improvement_alerts": .int(0)
        ]
        await persist { try await repo.upsert("survive_reset", body, onConflict: "user_id") }
    }

    func pause() async { await patch(["paused_at": .date(Date())]) }
    func resume() async { await patch(["paused_at": .null]) }

    func advanceToReintroduction() async {
        await patch(["phase": .string(SrvResetPhase.reintroductionPhase.rawValue)])
    }

    func markClinicianPrompted() async {
        await patch(["clinician_prompted_at": .date(Date()), "no_improvement_alerts": .int((reset?.noImprovementAlerts ?? 0) + 1)])
    }

    func graduate() async {
        await patch(["phase": .string(SrvResetPhase.graduated.rawValue), "graduated_at": .date(Date())])
        // Carries Suspects + Avoid over, no row move. Routed through the SEPARATE
        // care channel (never a celebration).
        store.appState.survivePrompt(.graduateToThrive)
    }

    // MARK: Persistence

    /// Keep the stored relief count fresh so the engine's gates read true.
    private func persistReliefDays() async {
        guard reset != nil else { return }
        await patch(["symptom_free_days": .int(reliefDaysThisWeek)], reload: false)
    }

    private func patch(_ set: [String: PGValue], reload: Bool = true) async {
        guard let repo = store.appState.repository, let uid = store.appState.profile?.id else { return }
        var body = set
        body["updated_at"] = .date(Date())
        do {
            try await repo.update("survive_reset", set: body, filters: ["user_id": "eq.\(uid)"])
            if reload { reset = try? await repo.fetchSurviveReset() }
        } catch {
            errorMessage = "Couldn't update your reset. Try again."
        }
    }

    private func persist(_ work: () async throws -> Void) async {
        guard let repo = store.appState.repository else { return }
        do {
            try await work()
            reset = try? await repo.fetchSurviveReset()
        } catch {
            errorMessage = "Couldn't start your reset. Try again."
        }
    }
}
