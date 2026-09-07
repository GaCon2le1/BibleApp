import Foundation

public enum Topic: String, Codable, CaseIterable, Sendable, Hashable {
    case anxiety, hope, love, forgiveness, strength, guidance
    case peace, doubt, purpose, gratitude, grief, worth
}

public struct Verse: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let reference: String
    public let book: String
    public let chapter: Int
    public let verse: Int
    public let text: String
    public let displayText: String
    public let context: String
    public let topics: [Topic]
    public let tier: Int

    public init(id: String, reference: String, book: String, chapter: Int,
                verse: Int, text: String, displayText: String, context: String,
                topics: [Topic], tier: Int) {
        self.id = id
        self.reference = reference
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.text = text
        self.displayText = displayText
        self.context = context
        self.topics = topics
        self.tier = tier
    }
}

public struct FeedContent: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let translation: String
    public let verses: [Verse]
}
