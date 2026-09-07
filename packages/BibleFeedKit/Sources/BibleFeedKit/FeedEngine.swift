import Foundation

public struct FeedQueue: Equatable, Sendable {
    public let verses: [Verse]
    public let isReplay: Bool

    public init(verses: [Verse], isReplay: Bool) {
        self.verses = verses
        self.isReplay = isReplay
    }
}

public struct FeedEngine: Sendable {
    private let verses: [Verse]

    /// Verse array order must be stable across calls for seeded reproducibility.
    /// `shuffled(using:)` permutes from the current array position, so identical seeds with different input order produce different results.
    /// This assumption is satisfied in practice when verses come from JSONDecoder, which preserves JSON array source order.
    public init(verses: [Verse]) {
        self.verses = verses
    }

    /// Score is tier weight plus a bonus when the verse matches a chosen topic.
    /// Tier 1 weighs 3, tier 2 weighs 2, tier 3 weighs 1.
    static func score(_ verse: Verse, selectedTopics: Set<Topic>) -> Int {
        let tierWeight = max(0, 4 - verse.tier)
        let topicBonus = verse.topics.contains(where: selectedTopics.contains) ? 2 : 0
        return tierWeight + topicBonus
    }

    public func queue(selectedTopics: Set<Topic>,
                      seen: Set<String>,
                      saved: Set<String>,
                      seed: UInt64) -> FeedQueue {
        let unseen = verses.filter { !seen.contains($0.id) }
        return FeedQueue(verses: rank(unseen, selectedTopics: selectedTopics, seed: seed),
                         isReplay: false)
    }

    private func rank(_ pool: [Verse],
                      selectedTopics: Set<Topic>,
                      seed: UInt64) -> [Verse] {
        var generator = SeededGenerator(seed: seed)
        var bands: [Int: [Verse]] = [:]
        for verse in pool {
            bands[Self.score(verse, selectedTopics: selectedTopics), default: []].append(verse)
        }
        return bands.keys.sorted(by: >).flatMap { key in
            bands[key]!.shuffled(using: &generator)
        }
    }
}
