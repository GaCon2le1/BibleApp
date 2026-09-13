import Foundation

public enum Topic: String, Codable, CaseIterable, Sendable, Hashable {
    case anxiety, hope, love, forgiveness, strength, guidance
    case peace, doubt, purpose, gratitude, grief, worth
}

/// A translation the feed can render a card in. Raw values are the exact
/// keys used in the shipped content files' per-verse `translations` object.
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

