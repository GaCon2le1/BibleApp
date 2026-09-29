import Testing
@testable import BibleFeedKit

@Test func shortTextIsUnchanged() {
    #expect(VerseSnippet.truncate("Jesus wept.", limit: 220) == "Jesus wept.")
}

@Test func textExactlyAtLimitIsUnchanged() {
    let text = String(repeating: "a", count: 10)
    #expect(VerseSnippet.truncate(text, limit: 10) == text)
}

@Test func longTextIsCutAtAWordBoundary() {
    #expect(VerseSnippet.truncate("the quick brown fox", limit: 12) == "the quick…")
}

@Test func resultNeverExceedsTheLimit() {
    let text = String(repeating: "word ", count: 100)
    let result = VerseSnippet.truncate(text, limit: 220)
    #expect(result.count <= 220)
    #expect(result.hasSuffix("…"))
}

@Test func textWithoutSpacesIsHardCut() {
    #expect(VerseSnippet.truncate("abcdefghij", limit: 5) == "abcd…")
}

@Test func graphemeClustersAreNeverSplit() {
    let family = "👨‍👩‍👧‍👦"
    let text = String(repeating: family, count: 10)
    #expect(VerseSnippet.truncate(text, limit: 5) == String(repeating: family, count: 4) + "…")
}
