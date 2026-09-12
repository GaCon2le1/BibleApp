import Foundation

/// The heavy, on-demand-loaded half of a verse: translation text and
/// context. Decoded from a `ContentShard` file only when a verse needs to be
/// displayed.
public struct VerseContent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let translations: [Translation: TranslationText]
    public let context: String

    public init(id: String, translations: [Translation: TranslationText], context: String) {
        self.id = id
        self.translations = translations
        self.context = context
    }
}

public struct ContentShard: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let verses: [VerseContent]
}
