# Lyrics Live Activity — Design

Date: 2026-09-30
Status: Approved

## Problem

Karaoke text currently replaces the Now Playing title, so the player shows
changing sentences instead of the episode name, and only one line fits. The
user wants the layout of lyrics apps: the system Now Playing player for
playback, plus a **separate** Live Activity card showing the previous,
current and next transcript lines (reference: "Dynamic-Lyrics" Lock Screen
screenshot).

## Decisions

| Question | Decision |
|---|---|
| Playback UI | Unchanged system Now Playing; title back to the episode title, artist "Bible App" |
| Text UI | New Live Activity `ListeningLiveActivity` in `BibleAppWidgets` |
| Lock Screen card | Previous line (caption, secondary), current line (serif, semibold, ≤2 lines, centered), next line (caption, secondary) |
| Dynamic Island | Compact: `quote.bubble.fill` / `waveform` or `pause.fill`. Minimal: `quote.bubble.fill`. Expanded: episode title, current line (≤2 lines), next line |
| Buttons | None — playback controls live in the Now Playing player |
| Tap | Opens the app on the Listen tab (`bibleapp://listen`) |
| Lifetime | Requested when an episode with a transcript starts playing (app is in the foreground then); updated on every line change and play/pause; ended (immediately) when the episode ends or another episode starts; stray activities are ended on launch |
| Island sharing | iOS decides which of the two activities gets the compact slot; the other shows as a minimal bubble. Accepted |

Rejected: keeping the line in the Now Playing title as well (duplicate text).

## Architecture

- `BibleFeedKit`: `Transcript.index(at:)` (binary search; `line(at:)` uses
  it) and `Transcript.window(at:) -> LyricWindow` with `previous`,
  `current`, `next: String?`. Before the first line: `next` is the first
  line. Empty transcript: all nil.
- `Shared/ListeningAttributes.swift`: `nonisolated struct
  ListeningAttributes: ActivityAttributes { episodeID, episodeTitle }`,
  `ContentState { previous, current, next: String?; isPlaying: Bool }`.
- `LiveActivity/LyricsActivityController.swift` (app, main actor):
  `start(episode:state:)`, `update(_:)` (drops a state equal to the last
  one sent; coalesces bursts so only the newest pending state is sent),
  `end()`, `endStray()`. Checks `areActivitiesEnabled`; failures are logged,
  never shown to the user.
- `AudioPlayer`: `publishLyrics()` builds the state from
  `transcript.window(at: elapsed)` and `isPlaying`; called from play/resume/
  pause/seek/line change. `play` starts the activity when the episode has a
  transcript, otherwise ends it. End of item ends it.
- `ContentView`: `bibleapp://listen` selects the Listen tab; launch `.task`
  calls `endStray()`.

## Error handling

Live Activities disabled, request refused (e.g. not foreground) or the user
swiped the card away: audio and Now Playing keep working; the card
reappears the next time an episode is started from the app.

## Out of scope

Buttons on the card, translations, per-word highlighting, push updates.

## Testing

- Swift tests for `index(at:)` and `window(at:)` (before first, middle,
  last, empty).
- Widget previews (Lock Screen, expanded, compact, minimal).
- Real iPhone: Lock Screen shows player + lyrics card; card follows the
  voice while locked; island shows both activities; tapping opens Listen.
