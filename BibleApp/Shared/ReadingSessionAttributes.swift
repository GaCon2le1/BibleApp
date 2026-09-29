import ActivityKit
import Foundation

/// Live Activity data for a timed reflection session. Compiled into both the
/// app and the widget extension.
nonisolated struct ReadingSessionAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var verseID: String
        var reference: String
        /// Already shortened with `VerseSnippet.truncate`.
        var text: String
        var versesRead: Int
        var isSaved: Bool
        /// Set when the session was ended by the app; expiry is detected
        /// through `staleDate` instead.
        var isComplete: Bool
    }

    var endDate: Date
}
