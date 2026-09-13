import Testing
import Foundation
@testable import BibleFeedKit

@Test func topicHasTwelveCases() {
    #expect(Topic.allCases.count == 12)
}

@Test func translationHasThreeCases() {
    #expect(Translation.allCases.count == 3)
}
