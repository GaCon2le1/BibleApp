import ActivityKit
import Foundation
import SwiftData
import BibleFeedKit

/// Runs the timed reflection session: starts the Live Activity, answers its
/// Lock Screen buttons, and cleans up after expiry or dismissal. The
/// session is kept on disk so a button tap still works after the app has
/// been terminated.
@Observable
final class ReadingSessionController {
    static let shared = ReadingSessionController()

    private(set) var activeEndDate: Date?
    var alertMessage: String?

    private let store = ContentStore()
    private let fileURL = URL.applicationSupportDirectory.appending(path: "reading-session.json")
    @ObservationIgnored private var tail: Task<Void, Never>?

    private init() {
        activeEndDate = PersistedSession.load(from: fileURL)?.queue.endDate
    }

    func start(minutes: Int, ids: [String]) async {
        await serialized { await self.startSession(minutes: minutes, ids: ids) }
    }

    func next() async {
        await serialized { await self.advanceSession() }
    }

    func toggleSaved() async {
        await serialized { await self.toggleSavedVerse() }
    }

    func end() async {
        await serialized { await self.endSession(dismissal: .default) }
    }

    /// Run on launch and on every return to the foreground. Finishes a
    /// session that expired or was swiped away, and ends stray activities.
    func reconcile() async {
        await serialized { await self.reconcileSession() }
    }

    // MARK: - Operations

    private func startSession(minutes: Int, ids: [String]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            alertMessage = "Turn on Live Activities for this app in Settings to use reflection sessions."
            return
        }
        await endSession(dismissal: .immediate)

        let endDate = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        guard var queue = SessionQueue(ids: Array(ids.prefix(200)), endDate: endDate),
              let state = await loadState(for: &queue) else {
            alertMessage = "Couldn't load verses for this session."
            return
        }
        do {
            let activity = try Activity.request(
                attributes: ReadingSessionAttributes(endDate: endDate),
                content: ActivityContent(state: state, staleDate: endDate),
                pushType: nil)
            persist(PersistedSession(activityID: activity.id, queue: queue))
        } catch {
            alertMessage = "Couldn't start the session. \(error.localizedDescription)"
        }
    }

    private func advanceSession() async {
        guard var session = PersistedSession.load(from: fileURL) else { return }
        guard !session.queue.isExpired(now: .now) else {
            await endSession(dismissal: .default)
            return
        }
        userState?.markSeen(session.queue.current)
        saveContext()
        guard session.queue.advance(),
              let state = await loadState(for: &session.queue) else {
            await endSession(dismissal: .default)
            return
        }
        persist(session)
        await activity(for: session)?.update(
            ActivityContent(state: state, staleDate: session.queue.endDate))
    }

    private func toggleSavedVerse() async {
        guard let session = PersistedSession.load(from: fileURL),
              let activity = activity(for: session),
              let userState else { return }
        userState.toggleSaved(session.queue.current)
        saveContext()
        var state = activity.content.state
        state.isSaved = userState.savedSet.contains(session.queue.current)
        await activity.update(ActivityContent(state: state, staleDate: session.queue.endDate))
    }

    private func reconcileSession() async {
        let session = PersistedSession.load(from: fileURL)
        for activity in Activity<ReadingSessionAttributes>.activities
        where activity.id != session?.activityID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let session else {
            activeEndDate = nil
            return
        }
        let live = activity(for: session)
        let isLive = live.map { $0.activityState == .active } ?? false
        if session.queue.isExpired(now: .now) || !isLive {
            finish(session)
            await live?.end(nil, dismissalPolicy: .immediate)
        } else {
            activeEndDate = session.queue.endDate
        }
    }

    // MARK: - Private

    private var context: ModelContext { SharedModelContainer.shared.mainContext }

    private var userState: UserState? {
        try? context.fetch(FetchDescriptor<UserState>()).first
    }

    private func endSession(dismissal: ActivityUIDismissalPolicy) async {
        guard let session = PersistedSession.load(from: fileURL) else { return }
        finish(session)
        guard let activity = activity(for: session) else { return }
        var state = activity.content.state
        state.isComplete = true
        await activity.end(ActivityContent(state: state, staleDate: nil),
                           dismissalPolicy: dismissal)
    }

    /// Counts the last verse as read and forgets the session.
    private func finish(_ session: PersistedSession) {
        userState?.markSeen(session.queue.current)
        saveContext()
        PersistedSession.delete(at: fileURL)
        activeEndDate = nil
    }

    private func persist(_ session: PersistedSession) {
        do {
            try session.save(to: fileURL)
            activeEndDate = session.queue.endDate
        } catch {
            assertionFailure("Could not save the reading session: \(error)")
        }
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            assertionFailure("Could not save user state: \(error)")
        }
    }

    /// Runs `operation` after every earlier call has finished, so a burst of
    /// Lock Screen taps is applied one at a time.
    private func serialized(_ operation: @escaping () async -> Void) async {
        let previous = tail
        let current = Task {
            await previous?.value
            await operation()
        }
        tail = current
        await current.value
    }

    private func activity(for session: PersistedSession) -> Activity<ReadingSessionAttributes>? {
        Activity<ReadingSessionAttributes>.activities.first { $0.id == session.activityID }
    }

    /// Builds the Lock Screen state for the queue's current verse, moving
    /// past verses whose content fails to load, up to three tries.
    private func loadState(for queue: inout SessionQueue) async -> ReadingSessionAttributes.ContentState? {
        if store.index.isEmpty { store.load() }
        let translation = userState?.preferredTranslation ?? .kjv
        for _ in 0..<3 {
            let id = queue.current
            if let entry = store.entry(for: id),
               let content = await store.content(for: [id])[id] {
                let text = content.translations[translation]?.displayText
                    ?? content.translations[.kjv]?.displayText ?? ""
                return ReadingSessionAttributes.ContentState(
                    verseID: id,
                    reference: entry.reference,
                    text: VerseSnippet.truncate(text),
                    versesRead: queue.versesRead,
                    isSaved: userState?.savedSet.contains(id) ?? false,
                    isComplete: false)
            }
            guard queue.advance() else { return nil }
        }
        return nil
    }
}
