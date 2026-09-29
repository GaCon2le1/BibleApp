import Testing
@testable import BibleFeedKit

@Test func noSavedPositionStartsAtZero() {
    #expect(ResumePolicy.startPosition(saved: nil, duration: 100) == 0)
}

@Test func positionUnderFiveSecondsStartsAtZero() {
    #expect(ResumePolicy.startPosition(saved: 4.9, duration: 100) == 0)
}

@Test func positionFromFiveSecondsResumes() {
    #expect(ResumePolicy.startPosition(saved: 5, duration: 100) == 5)
}

@Test func positionJustBeforeTheLastThirtySecondsResumes() {
    #expect(ResumePolicy.startPosition(saved: 69.9, duration: 100) == 69.9)
}

@Test func positionInTheLastThirtySecondsStartsAtZero() {
    #expect(ResumePolicy.startPosition(saved: 70, duration: 100) == 0)
    #expect(ResumePolicy.startPosition(saved: 100, duration: 100) == 0)
}

@Test func zeroDurationStartsAtZero() {
    #expect(ResumePolicy.startPosition(saved: 10, duration: 0) == 0)
}

@Test func finishedFromNinetyFivePercent() {
    #expect(!ResumePolicy.isFinished(position: 94.9, duration: 100))
    #expect(ResumePolicy.isFinished(position: 95, duration: 100))
    #expect(ResumePolicy.isFinished(position: 100, duration: 100))
}

@Test func zeroDurationIsNeverFinished() {
    #expect(!ResumePolicy.isFinished(position: 0, duration: 0))
}

@Test func fractionIsClamped() {
    #expect(ResumePolicy.fraction(position: 25, duration: 100) == 0.25)
    #expect(ResumePolicy.fraction(position: -5, duration: 100) == 0)
    #expect(ResumePolicy.fraction(position: 150, duration: 100) == 1)
    #expect(ResumePolicy.fraction(position: 10, duration: 0) == 0)
}
