import ActivityKit
import Foundation

/// Shared between the BibleApp and BibleAppWidgets targets (dual target
/// membership — this file, not a framework, since it is the only type
/// either side needs from the other). No static attributes: every field the
/// widget renders changes as playback advances, so all of it lives in
/// ContentState.
public struct VerseLyricsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var verseText: String
        public var reference: String
        public var secondaryText: String
        public var elapsedSeconds: Double
        public var durationSeconds: Double
        public var isPlaying: Bool

        public init(verseText: String, reference: String, secondaryText: String,
                    elapsedSeconds: Double, durationSeconds: Double, isPlaying: Bool) {
            self.verseText = verseText
            self.reference = reference
            self.secondaryText = secondaryText
            self.elapsedSeconds = elapsedSeconds
            self.durationSeconds = durationSeconds
            self.isPlaying = isPlaying
        }
    }

    public init() {}
}
