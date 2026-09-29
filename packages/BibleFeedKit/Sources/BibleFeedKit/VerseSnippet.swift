import Foundation

/// Shortens verse text to fit the Lock Screen, whose Live Activity payload is
/// capped at about 4 KB. Works on `Character`s so an emoji or combined glyph
/// is never split in half.
public enum VerseSnippet {
    public static func truncate(_ text: String, limit: Int = 220) -> String {
        guard text.count > limit else { return text }
        // Leave room for the ellipsis so the result stays within `limit`.
        let head = text.prefix(limit - 1)
        let cut = head.lastIndex(where: \.isWhitespace).map { head[..<$0] } ?? head
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }
}
