import Foundation

public enum Topic: String, Codable, CaseIterable, Sendable, Hashable {
    case anxiety, hope, love, forgiveness, strength, guidance
    case peace, doubt, purpose, gratitude, grief, worth
}

/// A translation the feed can render a card in. Raw values are the exact
/// keys used in `feed_verses.json`'s per-verse `translations` object.
public enum Translation: String, Codable, CaseIterable, Sendable, Hashable, CodingKeyRepresentable {
    case kjv = "KJV"
    case bsb = "BSB"
    case cpdv = "CPDV"

    /// Display name for the Settings/Library picker.
    public var displayName: String {
        switch self {
        case .kjv: return "King James Version"
        case .bsb: return "Berean Standard Bible"
        case .cpdv: return "Catholic Public Domain Version"
        }
    }
}

public struct TranslationText: Codable, Hashable, Sendable {
    public let text: String
    public let displayText: String

    public init(text: String, displayText: String) {
        self.text = text
        self.displayText = displayText
    }
}

public struct Verse: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let reference: String
    public let book: String
    public let chapter: Int
    public let verse: Int
    public let translations: [Translation: TranslationText]
    public let context: String
    public let topics: [Topic]
    public let tier: Int

    public init(id: String, reference: String, book: String, chapter: Int,
                verse: Int, translations: [Translation: TranslationText],
                context: String, topics: [Topic], tier: Int) {
        self.id = id
        self.reference = reference
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.translations = translations
        self.context = context
        self.topics = topics
        self.tier = tier
    }
}

public struct FeedContent: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let verses: [Verse]
}
