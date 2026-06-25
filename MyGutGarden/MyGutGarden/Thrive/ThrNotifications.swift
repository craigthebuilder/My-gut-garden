//
//  ThrNotifications.swift
//  MyGutGarden — Module C: gain-framed Thrive nudges (SPEC §11a, DESIGN.md
//  "Writing"). Thin copy layer over the shared `NotificationScheduler`.
//
//  Every nudge attaches to a POSITIVE outcome — plants toward 30, completing the
//  3 P's, keeping the "is it working?" picture sharp — never restriction (rule
//  #7). GUILD nudges ("your Arsenal is hungry") are Module D's; nothing here
//  references guilds, bacteria, or districts.
//

import Foundation

@MainActor
enum ThrNotifications {

    private enum ID {
        static let plantNudge = "thr.plant-nudge"
        static let threeP = "thr.three-p"
        static let moodCheck = "thr.mood-check"
        static let rareCelebration = "thr.rare-find"
        static let all = [plantNudge, threeP, moodCheck, rareCelebration]
    }

    /// "27/30 plants — 3 to go before Sunday resets." Only fires when there's
    /// genuine headroom (and never frames the gap as failure).
    static func schedulePlantNudge(uniqueThisWeek: Int,
                                   target: Int = GameConfig.shared.weeklyPlantTarget,
                                   at date: DateComponents) {
        let remaining = max(0, target - uniqueThisWeek)
        guard remaining > 0 else { return }
        NotificationScheduler.schedule(
            id: ID.plantNudge,
            title: "Your garden",
            body: "\(uniqueThisWeek)/\(target) plants — \(remaining) to go before Sunday resets.",
            at: date
        )
    }

    /// "Prebiotic + Polyphenol done — one fermented food completes your 3 P's."
    /// Skips entirely when the day is already complete (no nagging).
    static func scheduleThreePNudge(threePs: ThreePs, at date: DateComponents) {
        guard !threePs.allThree else { return }
        var done: [String] = []
        if threePs.prebiotic { done.append("Prebiotic") }
        if threePs.probiotic { done.append("Probiotic") }
        if threePs.polyphenol { done.append("Polyphenol") }

        let missingFood: String
        if !threePs.probiotic { missingFood = "one fermented food" }
        else if !threePs.polyphenol { missingFood = "one colorful polyphenol" }
        else { missingFood = "one prebiotic fiber" }

        let lead = done.isEmpty ? "Three P's are waiting" : "\(done.joined(separator: " + ")) done"
        NotificationScheduler.schedule(
            id: ID.threeP,
            title: "Almost there",
            body: "\(lead) — \(missingFood) completes today's 3 P's.",
            at: date
        )
    }

    /// Gentle daily nudge for the optional mood tap (Thrive's one-tap burden, §12).
    static func scheduleMoodCheckReminder(at date: DateComponents) {
        NotificationScheduler.schedule(
            id: ID.moodCheck,
            title: "Quick check-in",
            body: "How did today feel? One tap keeps your “is it working?” picture sharp.",
            at: date
        )
    }

    /// A rare/legendary find earns a celebration nudge (rarity scales the moment,
    /// §13). Fired shortly after the meal that revealed it.
    static func celebrateRareFind(plant: String, rarity: RarityTier, afterSeconds: TimeInterval = 1) {
        guard rarity.triggersCelebration else { return }
        NotificationScheduler.scheduleIn(
            id: ID.rareCelebration,
            title: "\(rarity.label) find!",
            body: "\(plant) joined your field guide — a \(rarity.label.lowercased()) one. Nicely spotted.",
            seconds: afterSeconds
        )
    }

    static func cancelAll() {
        NotificationScheduler.cancel(ids: ID.all)
    }
}
