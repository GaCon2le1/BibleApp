import ActivityKit
import BibleFeedKit

/// Owns the single Live Activity's lifecycle. Never blocks or fails
/// playback if Live Activities are unavailable or denied — checked once,
/// up front, per the design doc's error-handling table.
@MainActor
final class VerseActivityController {
    private var activity: Activity<VerseLyricsAttributes>?

    func start(entry: VerseIndexEntry, content: VerseContent, engine: AudioPlaybackEngine) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = contentState(entry: entry, content: content, engine: engine)
        do {
            activity = try Activity.request(
                attributes: VerseLyricsAttributes(),
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            // Not fatal: playback and the system Now Playing card continue
            // regardless (see design doc's error-handling table).
            activity = nil
        }
    }

    func update(entry: VerseIndexEntry, content: VerseContent, engine: AudioPlaybackEngine) {
        guard let activity else { return }
        let state = contentState(entry: entry, content: content, engine: engine)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }

    private func contentState(entry: VerseIndexEntry, content: VerseContent,
                               engine: AudioPlaybackEngine) -> VerseLyricsAttributes.ContentState {
        .init(
            verseText: content.translations[.kjv]?.displayText ?? "",
            reference: entry.reference,
            secondaryText: content.context,
            elapsedSeconds: engine.elapsed,
            durationSeconds: engine.duration,
            isPlaying: engine.isPlaying
        )
    }
}
