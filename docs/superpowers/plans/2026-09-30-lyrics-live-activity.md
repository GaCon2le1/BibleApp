# Lyrics Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show previous / current / next transcript lines in a Live Activity of their own, next to the system Now Playing player, which goes back to showing the episode title.

**Architecture:** `BibleFeedKit` computes a three-line `LyricWindow` for a playback time. `AudioPlayer` sends it to a new `LyricsActivityController`, which owns one `Activity<ListeningAttributes>`. The widget extension renders it.

**Tech Stack:** Swift 6, ActivityKit, WidgetKit, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-30-lyrics-live-activity-design.md`

## Global Constraints

- Branch `feature/audio-listen`; commit only this plan's files with `/usr/bin/git commit -m "…" -- <paths>`. Never commit audio files or `Resources/json/*`.
- App target is `MainActor` by default; the widget extension is not. Types in `Shared/` are `nonisolated struct`.
- UI strings English. Tap URL `bibleapp://listen`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

Build: `xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'generic/platform=iOS Simulator' -quiet build`

---

### Task 1: `Transcript.index(at:)` and `window(at:)`

**Files:** Modify `packages/BibleFeedKit/Sources/BibleFeedKit/Transcript.swift`, `packages/BibleFeedKit/Tests/BibleFeedKitTests/TranscriptTests.swift`.

**Produces:** `public struct LyricWindow: Equatable, Sendable { previous, current, next: String? }`, `Transcript.index(at:) -> Int?`, `Transcript.window(at:) -> LyricWindow`.

- [ ] **Step 1: Failing tests** — append to `TranscriptTests.swift`:

```swift
@Test func indexFollowsLineStarts() {
    #expect(transcript.index(at: 1) == nil)
    #expect(transcript.index(at: 2) == 0)
    #expect(transcript.index(at: 6) == 1)
    #expect(transcript.index(at: 99) == 2)
}

@Test func windowBeforeTheFirstLineShowsItAsNext() {
    #expect(transcript.window(at: 0) == LyricWindow(previous: nil, current: nil, next: "Một"))
}

@Test func windowInTheMiddleHasBothNeighbours() {
    #expect(transcript.window(at: 6) == LyricWindow(previous: "Một", current: "Hai", next: "Ba"))
}

@Test func windowAtTheFirstAndLastLines() {
    #expect(transcript.window(at: 2) == LyricWindow(previous: nil, current: "Một", next: "Hai"))
    #expect(transcript.window(at: 99) == LyricWindow(previous: "Hai", current: "Ba", next: nil))
}

@Test func windowOfEmptyTranscriptIsEmpty() {
    #expect(Transcript(lines: []).window(at: 5) == LyricWindow(previous: nil, current: nil, next: nil))
}
```

- [ ] **Step 2:** `cd packages/BibleFeedKit && swift test --filter TranscriptTests` → FAIL (no `index`, `LyricWindow`).

- [ ] **Step 3: Implement** — in `Transcript.swift` replace `line(at:)` with:

```swift
    /// Position in `lines` of the line being spoken at `seconds`: the last
    /// one that has started, so a line stays up through the pause after it.
    /// Nil before the first line.
    public func index(at seconds: Double) -> Int? {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].start <= seconds {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low == 0 ? nil : low - 1
    }

    /// The line being spoken at `seconds`; nil before the first line.
    public func line(at seconds: Double) -> TranscriptLine? {
        index(at: seconds).map { lines[$0] }
    }

    /// The spoken line with the lines either side of it, for the lyrics card.
    public func window(at seconds: Double) -> LyricWindow {
        guard let index = index(at: seconds) else {
            return LyricWindow(previous: nil, current: nil, next: lines.first?.text)
        }
        return LyricWindow(previous: index > 0 ? lines[index - 1].text : nil,
                           current: lines[index].text,
                           next: index + 1 < lines.count ? lines[index + 1].text : nil)
    }
```

and add at the end of the file:

```swift
/// Three consecutive transcript lines around the playback position.
public struct LyricWindow: Equatable, Sendable {
    public let previous: String?
    public let current: String?
    public let next: String?

    public init(previous: String?, current: String?, next: String?) {
        self.previous = previous
        self.current = current
        self.next = next
    }
}
```

- [ ] **Step 4:** `cd packages/BibleFeedKit && swift test` → all PASS.
- [ ] **Step 5:** Commit `packages/BibleFeedKit` plus this plan and its spec.

---

### Task 2: `ListeningAttributes`, the widget, and `LyricsActivityController`

**Files:** Create `BibleApp/Shared/ListeningAttributes.swift`, `BibleApp/BibleAppWidgets/ListeningLiveActivity.swift`, `BibleApp/BibleApp/LiveActivity/LyricsActivityController.swift`; modify `BibleApp/BibleAppWidgets/BibleAppWidgetsBundle.swift`.

**Produces:** `ListeningAttributes { episodeID: String; episodeTitle: String; ContentState { previous, current, next: String?; isPlaying: Bool } }`; `LyricsActivityController.shared` with `start(episode: Episode, state: ListeningAttributes.ContentState)`, `update(_ state:)`, `end()`, `endStray()`.

- [ ] **Step 1:** `BibleApp/Shared/ListeningAttributes.swift`:

```swift
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
```

- [ ] **Step 2:** `BibleApp/BibleAppWidgets/ListeningLiveActivity.swift`:

```swift
import ActivityKit
import SwiftUI
import WidgetKit

/// The lyrics card: transcript lines of the playing episode, shown next to
/// the system Now Playing player, which handles playback controls.
struct ListeningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ListeningAttributes.self) { context in
            LyricsLockScreenView(context: context)
                .widgetURL(Self.listenURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.episodeTitle, systemImage: "quote.bubble.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PlaybackIndicator(isPlaying: context.state.isPlaying)
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.current ?? context.attributes.episodeTitle)
                            .font(.system(.body, design: .serif).weight(.semibold))
                            .lineLimit(2)
                        if let next = context.state.next {
                            Text(next)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "quote.bubble.fill")
            } compactTrailing: {
                PlaybackIndicator(isPlaying: context.state.isPlaying)
            } minimal: {
                Image(systemName: "quote.bubble.fill")
            }
            .widgetURL(Self.listenURL)
        }
    }

    /// Tapping the card opens the app on the Listen tab.
    private static let listenURL = URL(string: "bibleapp://listen")
}

private struct LyricsLockScreenView: View {
    let context: ActivityViewContext<ListeningAttributes>

    var body: some View {
        let state = context.state
        VStack(spacing: 6) {
            Text(state.previous ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(state.current ?? context.attributes.episodeTitle)
                .font(.system(.body, design: .serif).weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(state.next ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct PlaybackIndicator: View {
    let isPlaying: Bool

    var body: some View {
        Image(systemName: isPlaying ? "waveform" : "pause.fill")
            .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
}

private extension ListeningAttributes {
    static let preview = ListeningAttributes(episodeID: "test", episodeTitle: "Test Episode")
}

private extension ListeningAttributes.ContentState {
    static let playing = Self(previous: "and just get in a comfortable spot",
                              current: "and just take a moment in the quiet.",
                              next: "Just kind of shut everything else out.",
                              isPlaying: true)
    static let long = Self(previous: "I'm gonna read through some scripture.",
                           current: "But right now, just focus on getting your mind quiet and let everything else fall away",
                           next: nil,
                           isPlaying: false)
    static let beforeFirstLine = Self(previous: nil, current: nil,
                                      next: "I'm going to invite you to close your eyes",
                                      isPlaying: true)
}

#Preview("Lock Screen", as: .content, using: ListeningAttributes.preview) {
    ListeningLiveActivity()
} contentStates: {
    ListeningAttributes.ContentState.playing
    ListeningAttributes.ContentState.long
    ListeningAttributes.ContentState.beforeFirstLine
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: ListeningAttributes.preview) {
    ListeningLiveActivity()
} contentStates: {
    ListeningAttributes.ContentState.playing
    ListeningAttributes.ContentState.long
}

#Preview("Compact", as: .dynamicIsland(.compact), using: ListeningAttributes.preview) {
    ListeningLiveActivity()
} contentStates: {
    ListeningAttributes.ContentState.playing
    ListeningAttributes.ContentState.long
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: ListeningAttributes.preview) {
    ListeningLiveActivity()
} contentStates: {
    ListeningAttributes.ContentState.playing
}
```

- [ ] **Step 3:** `BibleAppWidgetsBundle.swift` body becomes:

```swift
        ReadingSessionLiveActivity()
        ListeningLiveActivity()
```

- [ ] **Step 4:** `BibleApp/BibleApp/LiveActivity/LyricsActivityController.swift`:

```swift
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
```

- [ ] **Step 5:** Build → success. Commit the four files.

---

### Task 3: Drive the card from `AudioPlayer`; Now Playing back to the episode title; Listen deep link

**Files:** Modify `BibleApp/BibleApp/Audio/AudioPlayer.swift`, `BibleApp/BibleApp/ContentView.swift`.

- [ ] **Step 1: `AudioPlayer`**
  - Add `@ObservationIgnored private let lyrics = LyricsActivityController.shared`.
  - In `play(_:)`, after `currentLine = transcript?.line(at: start)?.text`, add nothing; in `resume()` after `updateNowPlaying()` add `startOrUpdateLyrics()`; in `pause()` and `seek(to:)` after `updateNowPlaying()` add `publishLyrics()`.
  - In `play(_:)`, just before the final `resume()`, add `lyrics.end()` when `transcript == nil`:
    ```swift
            if transcript == nil {
                lyrics.end()
            }
    ```
  - `refreshLine()` becomes:
    ```swift
        /// Follows the transcript to `elapsed`, updating the lyrics card only
        /// when the line changes.
        private func refreshLine() {
            let line = transcript?.line(at: elapsed)?.text
            guard line != currentLine else { return }
            currentLine = line
            publishLyrics()
        }
    ```
  - Handle pause from interruptions: in `handleInterruption` `.began` branch, after `updateNowPlaying()` add `publishLyrics()`.
  - In `itemDidEnd`, after `updateNowPlaying()` add `lyrics.end()`.
  - Add:
    ```swift
        /// Starts the card for the loaded episode if needed, else updates it.
        private func startOrUpdateLyrics() {
            guard let current, transcript != nil else { return }
            lyrics.start(episode: current, state: lyricsState())
        }

        private func publishLyrics() {
            guard transcript != nil else { return }
            lyrics.update(lyricsState())
        }

        private func lyricsState() -> ListeningAttributes.ContentState {
            let window = transcript?.window(at: elapsed)
            return ListeningAttributes.ContentState(previous: window?.previous,
                                                    current: window?.current,
                                                    next: window?.next,
                                                    isPlaying: isPlaying)
        }
    ```
  - In `updateNowPlaying()`, revert the title/artist to:
    ```swift
                MPMediaItemPropertyTitle: current.title,
                MPMediaItemPropertyArtist: "Bible App",
    ```
    (remove the karaoke comment).
  - Update the `currentLine` doc comment to: `/// The transcript line being spoken, for the player and lyrics card.`
- [ ] **Step 2: `ContentView`** — in `.onOpenURL`, handle `listen`:
    ```swift
                    .onOpenURL { url in
                        guard url.scheme == "bibleapp" else { return }
                        switch url.host {
                        case "feed": selectedTab = .feed
                        case "listen": selectedTab = .listen
                        default: break
                        }
                    }
    ```
    and in the launch `.task`, after the reading-session reconcile: `LyricsActivityController.shared.endStray()`.
- [ ] **Step 3:** Build → success; `swift test` passes. Commit both files.

---

### Task 4: Verify

- [ ] Simulator: play the test episode, lock; confirm via `log show` that `ListeningAttributes` updates are sent on line changes, and that the Now Playing title stays "Test Episode". Screenshot the Lock Screen (the Simulator renders Live Activities).
- [ ] Real iPhone (when connected): Lock Screen shows player + lyrics card following the voice while locked; island shows both; tapping the card opens Listen.
