import Foundation

/// One narrated verse: which id, and how long the clip runs. Always KJV in
/// v1 (see docs/superpowers/specs/2026-09-15-verse-lock-screen-lyrics-design.md)
/// — there is deliberately no `translation` field here to avoid implying
/// otherwise.
public struct VerseAudioEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let durationMs: Int

    public init(id: String, durationMs: Int) {
        self.id = id
        self.durationMs = durationMs
    }
}

public struct AudioIndex: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let entries: [VerseAudioEntry]
}
