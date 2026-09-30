import ActivityKit
import Foundation
import os
import BibleFeedKit

/// Owns the lyrics Live Activity for the playing episode. Updates are
/// coalesced: while one is being sent, only the newest pending state is kept.
final class LyricsActivityController {
    static let shared = LyricsActivityController()

    private var activity: Activity<ListeningAttributes>?
    private var lastState: ListeningAttributes.ContentState?
    private var pending: ListeningAttributes.ContentState?
    private var isSending = false
    private let log = Logger(subsystem: "com.trailbyte.bible", category: "lyrics")

    private init() {}

    /// Shows `episode`'s card, replacing any other. Must run while the app is
    /// in the foreground, which is when the listener starts an episode.
    func start(episode: Episode, state: ListeningAttributes.ContentState) {
        if let activity, activity.attributes.episodeID == episode.id,
           activity.activityState == .active {
            update(state)
            return
        }
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: ListeningAttributes(episodeID: episode.id, episodeTitle: episode.title),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil)
            lastState = state
        } catch {
            log.error("Couldn't start the lyrics activity: \(error.localizedDescription)")
        }
    }

    func update(_ state: ListeningAttributes.ContentState) {
        guard activity != nil, state != lastState else { return }
        lastState = state
        pending = state
        guard !isSending else { return }
        isSending = true
        Task {
            while let next = pending, let activity {
                pending = nil
                await activity.update(ActivityContent(state: next, staleDate: nil))
            }
            isSending = false
        }
    }

    func end() {
        guard let ending = activity else { return }
        activity = nil
        lastState = nil
        pending = nil
        Task { await ending.end(nil, dismissalPolicy: .immediate) }
    }

    /// Ends cards left over from a previous launch, which can no longer
    /// follow any audio.
    func endStray() {
        for stray in Activity<ListeningAttributes>.activities where stray.id != activity?.id {
            Task { await stray.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
