import Testing
@testable import BibleFeedKit

private func verse(_ id: String, tier: Int, topics: [Topic] = [.hope]) -> VerseIndexEntry {
    VerseIndexEntry(id: id, reference: id, book: "PSA", chapter: 1, verse: 1,
                     topics: topics, tier: tier, shard: 0)
}

@Test func higherTierComesFirst() {
    let engine = FeedEngine(verses: [
        verse("c", tier: 3), verse("a", tier: 1), verse("b", tier: 2)
    ])
    let q = engine.queue(selectedTopics: [], seen: [], saved: [], seed: 1)
    #expect(q.verses.map(\.id) == ["a", "b", "c"])
    #expect(q.isReplay == false)
}

@Test func selectedTopicOutranksTier() {
    // tier 3 with a selected topic scores 1 + 2 = 3, beating tier 2 scoring 2.
    let engine = FeedEngine(verses: [
        verse("tier2", tier: 2, topics: [.grief]),
        verse("tier3match", tier: 3, topics: [.anxiety])
    ])
    let q = engine.queue(selectedTopics: [.anxiety], seen: [], saved: [], seed: 1)
    #expect(q.verses.map(\.id) == ["tier3match", "tier2"])
}

@Test func sameSeedGivesSameOrder() {
    let verses = (1...20).map { verse("v\($0)", tier: 2) }
    let engine = FeedEngine(verses: verses)
    let a = engine.queue(selectedTopics: [], seen: [], saved: [], seed: 42)
    let b = engine.queue(selectedTopics: [], seen: [], saved: [], seed: 42)
    #expect(a.verses.map(\.id) == b.verses.map(\.id))
}

@Test func differentSeedsReorderWithinBand() {
    let verses = (1...20).map { verse("v\($0)", tier: 2) }
    let engine = FeedEngine(verses: verses)
    let a = engine.queue(selectedTopics: [], seen: [], saved: [], seed: 1)
    let b = engine.queue(selectedTopics: [], seen: [], saved: [], seed: 2)
    #expect(a.verses.map(\.id) != b.verses.map(\.id))
}

@Test func shufflingLosesNoVerses() {
    let verses = (1...50).map { verse("v\($0)", tier: ($0 % 3) + 1) }
    let engine = FeedEngine(verses: verses)
    let q = engine.queue(selectedTopics: [.hope], seen: [], saved: [], seed: 7)
    #expect(Set(q.verses.map(\.id)) == Set(verses.map(\.id)))
    #expect(q.verses.count == 50)
}

@Test func seenVersesAreExcluded() {
    let engine = FeedEngine(verses: [
        verse("a", tier: 1), verse("b", tier: 1), verse("c", tier: 1)
    ])
    let q = engine.queue(selectedTopics: [], seen: ["a", "c"], saved: [], seed: 1)
    #expect(q.verses.map(\.id) == ["b"])
    #expect(q.isReplay == false)
}

@Test func exhaustedPoolReplaysWithSavedFirst() {
    let engine = FeedEngine(verses: [
        verse("a", tier: 3), verse("b", tier: 1), verse("c", tier: 2)
    ])
    let q = engine.queue(selectedTopics: [], seen: ["a", "b", "c"],
                         saved: ["a"], seed: 1)
    #expect(q.isReplay == true)
    #expect(q.verses.first?.id == "a")
    #expect(q.verses.count == 3)
}

@Test func exhaustedPoolReplaysAllSavedBeforeAllUnsaved() {
    let engine = FeedEngine(verses: [
        verse("a", tier: 1), verse("b", tier: 2),
        verse("c", tier: 3), verse("d", tier: 1)
    ])
    let q = engine.queue(selectedTopics: [], seen: ["a", "b", "c", "d"],
                         saved: ["a", "c"], seed: 1)
    #expect(q.isReplay == true)
    #expect(Set(q.verses.prefix(2).map(\.id)) == ["a", "c"])
    #expect(Set(q.verses.suffix(2).map(\.id)) == ["b", "d"])
}

@Test func exhaustedPoolWithNoSavedStillReplaysEverything() {
    let engine = FeedEngine(verses: [verse("a", tier: 1), verse("b", tier: 2)])
    let q = engine.queue(selectedTopics: [], seen: ["a", "b"], saved: [], seed: 1)
    #expect(q.isReplay == true)
    #expect(Set(q.verses.map(\.id)) == ["a", "b"])
}

@Test func emptyLibraryProducesEmptyQueue() {
    let engine = FeedEngine(verses: [])
    let q = engine.queue(selectedTopics: [], seen: [], saved: [], seed: 1)
    #expect(q.verses.isEmpty)
    #expect(q.isReplay == false)
}
