import Testing
import Foundation
@testable import BibleFeedKit

private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func day(_ day: Int) -> Date {
    DateComponents(calendar: calendar, timeZone: calendar.timeZone,
                   year: 2026, month: 9, day: day).date!
}

@Test func noActivityIsZero() {
    #expect(StreakCalculator.currentStreak(
        activeDays: [], today: day(10), calendar: calendar) == 0)
}

@Test func todayOnlyIsOne() {
    #expect(StreakCalculator.currentStreak(
        activeDays: [day(10)], today: day(10), calendar: calendar) == 1)
}

@Test func consecutiveDaysEndingTodayCount() {
    #expect(StreakCalculator.currentStreak(
        activeDays: [day(8), day(9), day(10)],
        today: day(10), calendar: calendar) == 3)
}

@Test func gapBreaksTheStreak() {
    #expect(StreakCalculator.currentStreak(
        activeDays: [day(5), day(6), day(9), day(10)],
        today: day(10), calendar: calendar) == 2)
}

@Test func streakSurvivesATodayWithNoActivityYet() {
    // Yesterday counted, today has not started. The streak is still alive.
    #expect(StreakCalculator.currentStreak(
        activeDays: [day(8), day(9)],
        today: day(10), calendar: calendar) == 2)
}

@Test func aFullMissedDayBreaksIt() {
    #expect(StreakCalculator.currentStreak(
        activeDays: [day(7), day(8)],
        today: day(10), calendar: calendar) == 0)
}

@Test func timesOfDayDoNotMatter() {
    let morning = calendar.date(byAdding: .hour, value: 7, to: day(10))!
    let evening = calendar.date(byAdding: .hour, value: 22, to: day(9))!
    #expect(StreakCalculator.currentStreak(
        activeDays: [evening, morning], today: morning, calendar: calendar) == 2)
}
