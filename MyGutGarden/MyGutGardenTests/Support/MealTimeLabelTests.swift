//
//  MealTimeLabelTests.swift
//  MyGutGardenTests — time-derived meal names for check-in linking (owner ask,
//  2026-07-08: "the meal name should be like '11am breakfast', not the text or
//  an arbitrary 'meal 2'"). Pins the daypart boundaries and the duplicate-label
//  minute fallback so a grazing day never shows two identical entries.
//

import Foundation
import Testing
@testable import MyGutGarden

struct MealTimeLabelTests {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: hour, minute: minute))!
    }

    @Test func labelsReadLikeAPersonNamesMeals() {
        #expect(MealTimeLabel.label(for: date(11), calendar: cal) == "11am breakfast")
        #expect(MealTimeLabel.label(for: date(7, 30), calendar: cal) == "7am breakfast")
        #expect(MealTimeLabel.label(for: date(12), calendar: cal) == "12pm lunch")
        #expect(MealTimeLabel.label(for: date(13), calendar: cal) == "1pm lunch")
        #expect(MealTimeLabel.label(for: date(19), calendar: cal) == "7pm dinner")
        #expect(MealTimeLabel.label(for: date(23), calendar: cal) == "11pm late bite")
        #expect(MealTimeLabel.label(for: date(0), calendar: cal) == "12am late bite")
        #expect(MealTimeLabel.label(for: date(3), calendar: cal) == "3am late bite")
    }

    @Test func daypartBoundaries() {
        #expect(MealTimeLabel.daypart(hour: 4) == "breakfast")
        #expect(MealTimeLabel.daypart(hour: 11) == "breakfast")
        #expect(MealTimeLabel.daypart(hour: 12) == "lunch")
        #expect(MealTimeLabel.daypart(hour: 15) == "lunch")
        #expect(MealTimeLabel.daypart(hour: 16) == "dinner")
        #expect(MealTimeLabel.daypart(hour: 21) == "dinner")
        #expect(MealTimeLabel.daypart(hour: 22) == "late bite")
    }

    @Test func duplicateLabelsFallBackToMinutes() {
        let labels = MealTimeLabel.labels(
            for: [date(8, 5), date(8, 40), date(13, 0)], calendar: cal)
        #expect(labels == ["8:05am breakfast", "8:40am breakfast", "1pm lunch"])
    }

    @Test func uniqueLabelsStayCoarse() {
        let labels = MealTimeLabel.labels(for: [date(8), date(13), date(19)], calendar: cal)
        #expect(labels == ["8am breakfast", "1pm lunch", "7pm dinner"])
    }
}
