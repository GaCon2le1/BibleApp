import Testing
import Foundation
@testable import BibleFeedKit

private let endDate = Date(timeIntervalSince1970: 1_000)

@Test func emptyQueueIsRejected() {
    #expect(SessionQueue(ids: [], endDate: endDate) == nil)
}

@Test func startsAtTheFirstVerse() {
    let queue = SessionQueue(ids: ["A", "B"], endDate: endDate)!
    #expect(queue.current == "A")
    #expect(queue.versesRead == 1)
}

@Test func advanceMovesToTheNextVerse() {
    var queue = SessionQueue(ids: ["A", "B", "C"], endDate: endDate)!
    let result = queue.advance()
    #expect(result)
    #expect(queue.current == "B")
    #expect(queue.versesRead == 2)
}

@Test func advanceAtTheLastVerseReturnsFalseAndStays() {
    var queue = SessionQueue(ids: ["A", "B"], endDate: endDate)!
    let result1 = queue.advance()
    let result2 = queue.advance()
    #expect(result1)
    #expect(!result2)
    #expect(queue.current == "B")
    #expect(queue.versesRead == 2)
}

@Test func notExpiredBeforeEndDate() {
    let queue = SessionQueue(ids: ["A"], endDate: endDate)!
    #expect(!queue.isExpired(now: endDate.addingTimeInterval(-1)))
}

@Test func expiredExactlyAtEndDate() {
    let queue = SessionQueue(ids: ["A"], endDate: endDate)!
    #expect(queue.isExpired(now: endDate))
}

@Test func queueRoundTripsThroughCodable() throws {
    var queue = SessionQueue(ids: ["A", "B"], endDate: endDate)!
    _ = queue.advance()
    let data = try JSONEncoder().encode(queue)
    #expect(try JSONDecoder().decode(SessionQueue.self, from: data) == queue)
}
