import Foundation

public enum Topic: String, Codable, CaseIterable, Sendable, Hashable {
    case anxiety, hope, love, forgiveness, strength, guidance
    case peace, doubt, purpose, gratitude, grief, worth
}

/// A translation the feed can render a card in. Raw values are the exact
/// keys used in `feed_verses.json`'s per-verse `translations` object.
public enum Translation: String, Codable, CaseIterable, Sendable, Hashable {
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

public struct Verse: Identifiable, Hashable, Sendable {
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

extension Verse: Codable {
    enum CodingKeys: String, CodingKey {
        case id, reference, book, chapter, verse, translations, context, topics, tier
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        reference = try container.decode(String.self, forKey: .reference)
        book = try container.decode(String.self, forKey: .book)
        chapter = try container.decode(Int.self, forKey: .chapter)
        verse = try container.decode(Int.self, forKey: .verse)
        context = try container.decode(String.self, forKey: .context)
        topics = try container.decode([Topic].self, forKey: .topics)
        tier = try container.decode(Int.self, forKey: .tier)

        // Decode translations as a dictionary with Translation enum keys
        let translationsContainer = try container.nestedContainer(keyedBy: TranslationKey.self, forKey: .translations)
        var translations: [Translation: TranslationText] = [:]
        for key in translationsContainer.allKeys {
            guard let translation = Translation(rawValue: key.stringValue) else {
                let context = DecodingError.Context(
                    codingPath: decoder.codingPath + [TranslationKey(stringValue: key.stringValue)!],
                    debugDescription: "Unknown translation key: \(key.stringValue)"
                )
                throw DecodingError.dataCorrupted(context)
            }
            let translationText = try translationsContainer.decode(TranslationText.self, forKey: key)
            translations[translation] = translationText
        }
        self.translations = translations
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(reference, forKey: .reference)
        try container.encode(book, forKey: .book)
        try container.encode(chapter, forKey: .chapter)
        try container.encode(verse, forKey: .verse)
        try container.encode(context, forKey: .context)
        try container.encode(topics, forKey: .topics)
        try container.encode(tier, forKey: .tier)

        // Encode translations dictionary with string keys
        var translationsContainer = container.nestedContainer(keyedBy: TranslationKey.self, forKey: .translations)
        for (translation, text) in translations {
            let key = TranslationKey(stringValue: translation.rawValue)!
            try translationsContainer.encode(text, forKey: key)
        }
    }

    private struct TranslationKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }
}

public struct FeedContent: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let verses: [Verse]
}
