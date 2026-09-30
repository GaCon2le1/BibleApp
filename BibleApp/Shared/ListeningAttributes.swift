import ActivityKit
import Foundation

/// Live Activity data for the transcript lines of the playing episode.
/// Compiled into both the app and the widget extension.
nonisolated struct ListeningAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var previous: String?
        var current: String?
        var next: String?
        var isPlaying: Bool
    }

    var episodeID: String
    var episodeTitle: String
}
