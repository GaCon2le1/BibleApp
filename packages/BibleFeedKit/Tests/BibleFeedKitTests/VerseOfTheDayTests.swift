import Foundation
import Testing
@testable import BibleFeedKit

@Suite struct VerseOfTheDayTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func verses(_ count: Int, tier: Int = 1) -> [VerseIndexEntry] {
        (0..<count).map {
            VerseIndexEntry(id: "V.\($0)", reference: "Ref \($0)", book: "V", chapter: 1,
                            verse: $0, topics: [], tier: tier, shard: 0)
        }
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: 15))!
    }

    @Test func emptyListReturnsNil() {
        #expect(VerseOfTheDay.entry(in: [], on: date(1), calendar: calendar) == nil)
    }

    @Test func sameDayIsStableAcrossTimes() {
        let list = verses(50)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 1))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 23))!
        #expect(VerseOfTheDay.entry(in: list, on: morning, calendar: calendar)
                == VerseOfTheDay.entry(in: list, on: night, calendar: calendar))
    }

    @Test func consecutiveDaysDiffer() {
        let list = verses(50)
        let picks = (1...10).compactMap { VerseOfTheDay.entry(in: list, on: date($0), calendar: calendar)?.id }
        #expect(Set(picks).count == 10)
    }

    @Test func wrapsAroundSmallLists() {
        let list = verses(3)
        let picks = (1...9).compactMap { VerseOfTheDay.entry(in: list, on: date($0), calendar: calendar)?.id }
        #expect(picks.count == 9)
        #expect(Set(picks).count == 3)
    }

    @Test func prefersTierOneButFallsBack() {
        let mixed = verses(5, tier: 1) + (5..<20).map {
            VerseIndexEntry(id: "V.\($0)", reference: "Ref", book: "V", chapter: 1,
                            verse: $0, topics: [], tier: 2, shard: 0)
        }
        for day in 1...20 {
            #expect(VerseOfTheDay.entry(in: mixed, on: date(day), calendar: calendar)?.tier == 1)
        }
        #expect(VerseOfTheDay.entry(in: verses(4, tier: 3), on: date(1), calendar: calendar) != nil)
    }
}
