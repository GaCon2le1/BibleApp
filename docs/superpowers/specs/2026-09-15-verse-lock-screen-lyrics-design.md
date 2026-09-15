# Verse Read-Aloud + Lock Screen Lyrics — Design

Date: 2026-09-15
Status: Draft

## Problem

The app is scroll-to-read only — `feed_scroll-feed-design.md` explicitly listed
"audio" as out of scope for v1. The owner now wants a read-aloud mode where
the currently-playing verse also appears on the iOS Lock Screen and Dynamic
Island while the phone is locked, in the style of lyrics apps (e.g.
Dynamic-Lyrics): large current line, small secondary line underneath,
play/pause/next controls, all reachable without unlocking the device.

Two decisions were made up front by the owner:

- Voice source is pre-recorded/AI-quality narration, not on-device
  `AVSpeechSynthesizer` TTS.
- Scope is full Lock Screen **and** Dynamic Island, not a Lock-Screen-only cut.

Two problems specific to this codebase, not present in a typical music app:

1. **No bilingual text exists.** The "second line under the lyric" in
   Dynamic-Lyrics-style apps is normally a translated language. This app's
   `Translation` cases (KJV/BSB/CPDV) are three English Bible *versions*, not
   two languages — showing two of them stacked would read as redundant, not
   as a translation pair.
2. **No backend, no CDN, nothing loaded over the network** — every existing
   design in this repo (`bible-scroll-feed`, `json-content-pagination`)
   commits to shipping content fully bundled in the app. Audio should follow
   the same discipline rather than introducing the app's first network
   dependency.

## Decisions

| Question | Decision |
|---|---|
| Narration source | Generated once at build time by a narration API (ElevenLabs or equivalent), vendored as bundled `.m4a` files — not on-device TTS, not a runtime API call, not CDN-hosted |
| Which translation is narrated | KJV only for v1, matching the existing "Why KJV" rationale (iconic, recognizable wording) — Listen mode always plays/shows KJV text regardless of `state.preferredTranslation` |
| "Lyric line" granularity | One verse = one audio clip = one Live Activity update. No word-level or sub-verse highlighting in v1 |
| The stacked "second line" | Reuses the existing curated `context` field (plain-English explanation) as the secondary line under the verse text — gives the bilingual-style layout real content instead of a redundant translation |
| Not every verse needs narration | `audio_index.json` lists exactly which ids have a clip; a card for an id absent from it has no Listen button. Lets narration be produced incrementally without blocking the feature |
| Where playback starts | A play control on `VerseCard`; starts at the visible card and walks forward through the feed's current `queue`, auto-scrolling `FeedView` to follow |
| Background continuation | `AVAudioSession(.playback)` background mode + `MPRemoteCommandCenter`/`MPNowPlayingInfoCenter` for the standard system controls; the custom Live Activity is updated in-process while the app stays alive (background audio keeps it alive) |
| Live Activity updates after the app is killed | Out of scope for v1 — no push-to-start/push-to-update server. Documented as a known limitation, not silently glossed over |
| New Xcode target | Yes: a Widget Extension, `BibleAppWidgets`, added to `BibleApp.xcodeproj`. `VerseLyricsAttributes` is one shared Swift file with dual target membership (app + extension) — not a new local package, since it is a single small type |
| Hosting/downloading audio | None. Every clip ships in the app bundle, exactly like `feed_shard_*.json` today |

### Why not on-device TTS after all, given the cost

The owner chose narration quality over $0 infra cost. This means the audio
pipeline is a one-time production cost (600 short clips through a paid API),
not a per-user runtime cost — closer in spirit to how `data/source/BSB.json`
and `data/source/CPDV.json` were vendored once, not fetched live.

### Why KJV-only narration, not all three translations

Narrating BSB and CPDV too would triple both the one-time production cost and
the bundle size, for translations the original design already treats as
secondary ("KJV keeps the iconic form"). Scoping Listen mode to KJV keeps v1's
audio bundle around 600 clips instead of 1,800, and sidesteps a version
mismatch bug class entirely: a user with `preferredTranslation = .cpdv` would
otherwise see CPDV text while hearing KJV narration if audio only ever
existed for KJV. Making Listen mode explicitly KJV-only (visible in the UI as
a small label) removes that mismatch instead of hiding it.

## Architecture

Extends the existing three-layer architecture (Content / Engine / UI) with
one addition to each layer, plus a fourth: a Widget Extension.

- **Content** — `BibleApp/BibleApp/Resources/Audio/<id>.m4a` (AAC, mono,
  ~32 kbps, ~10–20s each) + `BibleApp/BibleApp/Resources/audio_index.json`.
  Built once by `tools/build_audio.py`, vendored like the translation source
  files, not regenerated on every `build_feed.py` run.
- **Engine** (`BibleFeedKit`, still no SwiftUI/AVFoundation/ActivityKit
  import — stays headless-testable) — `VerseAudioEntry` and `AudioIndex`,
  pure data types mirroring `VerseIndexEntry`/`FeedIndex`.
- **UI/Runtime** (`BibleApp` target) — `AudioPlaybackEngine` (AVPlayer +
  Now Playing + Remote Commands) and `VerseActivityController` (owns the
  `Activity<VerseLyricsAttributes>` lifecycle), both driven by the feed's
  existing `VerseIndexEntry` queue. `FeedView`/`VerseCard` gain a Listen
  entry point.
- **Widget Extension** (`BibleAppWidgets`, new target) — `VerseLiveActivity`,
  the Lock Screen + Dynamic Island SwiftUI layouts. Contains no business
  logic; it only renders whatever `ContentState` the app last pushed.

```
Resources/Audio/*.m4a + audio_index.json
              │
              ▼
   AudioPlaybackEngine (AVPlayer, AVAudioSession .playback)
   ├─► MPNowPlayingInfoCenter + MPRemoteCommandCenter   (system Lock Screen "Now Playing" card)
   └─► VerseActivityController ──ActivityKit──► BibleAppWidgets  (custom Lock Screen + Dynamic Island lyrics UI)
              │
              ▼
        FeedView auto-scrolls to the verse currently narrating
```

The two Lock Screen surfaces are deliberately both present: the system Now
Playing card is what iOS shows automatically the moment `AVAudioSession` is
active and `MPNowPlayingInfoCenter` is populated — free, standard, always
correct. The Live Activity is the custom "lyrics" look from the reference
screenshot, additive on top.

## Data model

`BibleApp/BibleApp/Resources/audio_index.json`:

```json
{
  "schemaVersion": 1,
  "contentVersion": "2026-09-15.1",
  "entries": [
    { "id": "PSA.23.1", "durationMs": 8200 }
  ]
}
```

`packages/BibleFeedKit/Sources/BibleFeedKit/VerseAudioEntry.swift` (new):

```swift
public struct VerseAudioEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let durationMs: Int
}

public struct AudioIndex: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let entries: [VerseAudioEntry]
}
```

`durationMs` exists so the Live Activity can show a progress bar the instant
playback starts, before `AVPlayerItem` finishes loading its own asset
duration asynchronously — not used for anything authoritative (the player's
own end-of-item notification is still what triggers advancing to the next
verse, not a timer against `durationMs`).

`VerseLyricsAttributes` (new, dual target membership — see Decisions):

```swift
import ActivityKit

public struct VerseLyricsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var verseText: String       // KJV displayText — the large line
        public var reference: String       // "Psalms 23:1"
        public var secondaryText: String   // context, truncated — the small line
        public var elapsedSeconds: Double
        public var durationSeconds: Double
        public var isPlaying: Bool
    }
}
```

No static (non-varying) attributes are needed — every field the widget
renders changes as playback advances.

## Content pipeline

`tools/build_audio.py` (new), run manually and infrequently, unlike
`build_feed.py` which runs on every content change:

1. Reads `data/curation/selection.json` for the 600 ids and
   `BibleApp/BibleApp/Resources/feed_index.json` /
   `feed_shard_*.json` for each id's KJV `displayText` (via the existing
   `ShardStore`-shaped shard files, read directly as JSON in Python — no new
   Swift dependency).
2. For each id not already present in `audio_index.json` (idempotent/
   resumable — a partial run can be re-run to pick up where it left off, and
   a manual quality re-take is done by deleting that id's line and re-running
   for just that id), calls the narration API once, writes
   `Resources/Audio/<id>.m4a`, and records `durationMs` by probing the
   written file (`ffprobe`, or the API's own reported duration if available).
3. Rewrites `audio_index.json` sorted by id, `contentVersion` bumped.

Requires a `NARRATION_API_KEY` environment variable; never committed, never
logged. Network access and the paid API call happen only when this script is
run by a maintainer — the shipped app makes no such calls at runtime.

`tools/validate_audio.py` (new), run alongside the existing
`tools/validate_feed.py`, and safe to run repeatedly with no network access:

- Every `audio_index.json` id exists in `feed_index.json`.
- Every id's `Resources/Audio/<id>.m4a` file exists on disk.
- `durationMs` is in a sane range (1,000–60,000) — catches a truncated or
  silent render.
- No id appears twice.

## Runtime components

| Component | Responsibility | Depends on |
|---|---|---|
| `AudioPlaybackEngine` | Owns `AVPlayer`, `AVAudioSession`, Remote Command Center, Now Playing info; sequences through a `[VerseIndexEntry]` queue starting at a given position | `ContentStore` (for audio file URLs + KJV text), `AVFoundation`, `MediaPlayer` |
| `VerseActivityController` | Starts/updates/ends the Live Activity; observes `AudioPlaybackEngine` | `AudioPlaybackEngine`, `ActivityKit` |
| `BibleAppWidgets` (`VerseLiveActivity`) | Lock Screen view + Dynamic Island compact/minimal/expanded regions | `VerseLyricsAttributes` only — no other app code |
| `FeedView` (extended) | Auto-scrolls to `AudioPlaybackEngine.currentVerseID`; shows a persistent mini-player while Listen mode is active | `AudioPlaybackEngine` |
| `VerseCard` (extended) | Play button, hidden when the card's id has no audio | `ContentStore.hasAudio(for:)` |

`AudioPlaybackEngine` and `VerseActivityController` never import SwiftUI
themselves beyond `@Observable`; they are plain runtime objects owned by
`ContentView`/`FeedView`, matching how `ContentStore` and `UserState` are
already owned and passed down today.

## Xcode project changes

- New target: **Widget Extension**, product name `BibleAppWidgets`, added via
  Xcode's own "File → New → Target" (hand-editing `project.pbxproj` for a new
  target is not attempted — too easy to produce a file Xcode itself then
  fails to open correctly). Embeds in the `BibleApp` target automatically.
- App Group capability added to both `BibleApp` and `BibleAppWidgets` targets
  (`group.<bundle-id>.bibleapp`) — required by Xcode's Live Activity template
  wiring even though this design pushes `ContentState` in-process and does
  not otherwise share files between the two targets.
- `BibleApp/BibleApp/Info.plist`: add `NSSupportsLiveActivities = YES`.
- `BibleApp/BibleApp/BibleApp.xcodeproj` build settings: enable Background
  Modes → **Audio, AirPlay, and Picture in Picture** on the `BibleApp`
  target.
- No entitlement or capability changes needed for `MPNowPlayingInfoCenter`/
  `MPRemoteCommandCenter` — those require only the background audio mode
  above, already covering both.

## Error handling

| Failure | Behavior |
|---|---|
| `audio_index.json` missing/corrupt at launch | Same as `feed_index.json` today: `assertionFailure` in debug, Listen mode simply unavailable in release (feature degrades away, rest of the app is unaffected) |
| A specific id's `.m4a` file is missing despite being in the index | Recoverable — `AudioPlaybackEngine` skips to the next verse in the queue, does not stop playback |
| User has denied Live Activities (Settings → this app off) | Playback and the system Now Playing card still work fully; `VerseActivityController.start()` simply no-ops after checking `ActivityAuthorizationInfo().areActivitiesEnabled` — never blocks or crashes playback |
| App fully suspended/killed mid-playback | Expected iOS behavior: audio stops, the Live Activity freezes at its last pushed state until the app relaunches or the system's own ~8h Live Activity lifetime cap expires. Documented, not solved, in v1 |
| Phone call / other audio interruption | `AVAudioSession` interruption notification pauses playback; resumes automatically only on the "should resume" system hint, otherwise leaves it paused with the Live Activity's `isPlaying` flag updated to match |

## Testing

- `BibleFeedKit`: Codable round-trip test for `VerseAudioEntry`/`AudioIndex`,
  mirroring the existing `VerseIndexEntryTests` pattern.
- Python: `tools/test_build_audio.py` (manifest shape, resumability — a
  second run with one new id only appends that one entry) and
  `tools/test_validate_audio.py` (every check in the table above, both the
  pass and the fail case, using fixtures under `tools/fixtures/`, matching
  how `tools/test_validate_feed.py` already works).
- On-device manual QA (requires Xcode/macOS, not reproducible in a
  build-less environment): Listen starts/stops/auto-advances; Lock Screen
  Now Playing card appears and its controls work; Live Activity appears,
  updates per verse, ends on stop; Dynamic Island compact and expanded
  regions render correctly on a real iPhone 14 Pro+; playback survives
  locking the screen; a phone call interrupts and the state recovers
  correctly; AirPods route change keeps playing.

## Out of scope for v1

Word-level/sub-verse lyric highlighting · narration for BSB/CPDV · push-to-
update Live Activities once the app process is killed · any network-hosted
or on-demand-downloaded audio · per-user narration speed/voice choice ·
Apple Watch companion · sharing "now playing verse" as an image (already
separately out of scope per the original scroll-feed design) · narrating the
`context` field itself (it is shown as text only, under the spoken verse).
