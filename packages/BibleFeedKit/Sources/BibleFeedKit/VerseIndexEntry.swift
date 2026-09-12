import Foundation

/// The lightweight metadata `FeedEngine` ranks on. Always fully loaded, since
/// ranking must see every verse's id/tier/topics at once. `shard` names which
/// content shard (see `ContentShard`) holds this verse's translations/context.
public struct VerseIndexEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let reference: String
    public let book: String
    public let chapter: Int
    public let verse: Int
    public let topics: [Topic]
    public let tier: Int
    public let shard: Int

    public init(id: String, reference: String, book: String, chapter: Int,
                verse: Int, topics: [Topic], tier: Int, shard: Int) {
        self.id = id
        self.reference = reference
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.topics = topics
        self.tier = tier
        self.shard = shard
    }
}

public struct FeedIndex: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let verses: [VerseIndexEntry]
}
