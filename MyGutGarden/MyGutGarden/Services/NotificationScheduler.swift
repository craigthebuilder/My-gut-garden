//
//  NotificationScheduler.swift
//  MyGutGarden, thin local-notification wrapper shared by C (Thrive, gain-framed)
//  and E (Survive, gentle). Copy is the caller's responsibility; Thrive copy is
//  gain-framed and Survive copy is calm (DESIGN.md "Writing", SPEC §11).
//

import Foundation
import UserNotifications

@MainActor
enum NotificationScheduler {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    static func schedule(id: String, title: String, body: String, at date: DateComponents) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func scheduleIn(id: String, title: String, body: String, seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
