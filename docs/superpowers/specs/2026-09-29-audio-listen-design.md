# Audio Listening (Listen tab + Now Playing) — Design

Date: 2026-09-29
Status: Approved

## Problem

The app only offers reading. We want long-form listening — sermon or Bible
explainer episodes of ~25 minutes — that keeps playing with the screen
locked and is controllable from the Dynamic Island and Lock Screen, like a
podcast app. A test episode (`Resources/audio/test.mp3`, 24.5 min, mono
24 kHz, 128 kbps, 23 MB) has been added.

## Decisions

| Question | Decision |
|---|---|
| Role of audio | Podcast-style episodes: play / pause / seek, keep playing in the background |
| Source | Bundled in the app under `Resources/audio/`, described by `episodes.json`. No streaming or downloads |
| UI | Third tab “Listen” with the episode list; a mini-player in `.tabViewBottomAccessory` on every tab while an episode is loaded; tapping it opens a full-screen player sheet |
| Dynamic Island / Lock Screen | System Now Playing (`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`). No custom Live Activity |
| Resume | Per-episode position saved in `UserDefaults` |
| Ads | App-open and interstitial ads are skipped while audio is playing |
| Language | UI strings in English, matching the rest of the app |

Rejected alternatives:
- **Custom Live Activity with `AudioPlaybackIntent`** — iOS shows the system
  Now Playing player anyway once audio plays, so the island would show two
  activities; dropping Now Playing instead loses AirPods, CarPlay and the
  standard Lock Screen scrubber.
- **Storing positions in SwiftData `UserState`** — written every few
  seconds; `UserDefaults` is cheaper and needs no model change.

## Architecture

### `BibleFeedKit` (pure, unit-tested)

- `Episode: Codable, Identifiable, Hashable, Sendable` — `id`, `title`,
  `subtitle`, `file` (bundle file name including extension),
  `durationSeconds: Double`.
- `EpisodeCatalog` — `static func decode(_ data: Data) throws -> [Episode]`
  from `{"episodes": [...]}`.
- `ResumePolicy`
  - `startPosition(saved:duration:) -> Double`: returns 0 when `saved` is
    nil, below 5 s, or within 30 s of the end; otherwise `saved`.
  - `isFinished(position:duration:) -> Bool`: `position >= 0.95 * duration`
    (false when `duration <= 0`).
  - `fraction(position:duration:) -> Double`: clamped to 0...1.

### App target

- `Audio/EpisodeLibrary` — loads `episodes.json` from the bundle and
  resolves each episode's file URL; episodes whose file is missing are
  dropped (with an `assertionFailure` in debug).
- `Audio/PlaybackProgressStore` — `[episodeID: seconds]` in `UserDefaults`
  under `audio.positions`; `position(for:)`, `save(_:for:)`.
- `Audio/AudioPlayer` — `@Observable @MainActor` singleton wrapping
  `AVPlayer`.
  - State: `current: Episode?`, `isPlaying`, `elapsed`, `duration`.
  - API: `play(_ episode:)` (resumes per `ResumePolicy`, or toggles if it is
    already current), `togglePlayPause()`, `skip(by:)`, `seek(to:)`.
  - `AVAudioSession` category `.playback`, mode `.spokenAudio`, activated on
    first play.
  - Now Playing: title, artist “Bible App”, artwork (`AudioArtwork` asset,
    falling back to no artwork), duration, elapsed time, rate. Refreshed on
    play / pause / seek / item change — not every tick; iOS extrapolates from
    the rate.
  - Remote commands: play, pause, togglePlayPause, skipBackward (15 s),
    skipForward (30 s), changePlaybackPosition.
  - Periodic time observer every 0.5 s updates `elapsed`; position saved
    every 5 s, on pause, on seek, and when the app goes to the background.
  - End of item: pause, save the full duration (so the list shows ✓), keep
    the episode loaded.
  - Interruption began → paused; ended with `.shouldResume` → play. Route
    change `.oldDeviceUnavailable` (headphones unplugged) → pause.
- Views
  - `ListenView` — `NavigationStack` list of episodes: title, subtitle,
    remaining time or a progress bar, ✓ when finished; the current episode
    shows a speaker icon. Tapping a row plays it and opens the player.
  - `MiniPlayerView` — title and a play/pause button, inside
    `.tabViewBottomAccessory`, shown only when `current != nil`. Tapping
    opens the player.
  - `PlayerView` — sheet: artwork, title, subtitle, `Slider` for seeking
    (commits on release), elapsed / remaining labels, ⏪15 ▶︎/⏸ 30⏩.
- `ContentView` — adds the `.listen` tab (`headphones` icon), the bottom
  accessory and the player sheet.
- `AdsCoordinator` — `showAppOpenAdIfEligible()` and `tabDidChange()` return
  early when `AudioPlayer.shared.isPlaying`.
- `Info.plist` — `UIBackgroundModes = [audio]`.

## Error handling

- `episodes.json` missing or invalid → Listen tab shows
  `ContentUnavailableView` “No episodes”.
- `AVPlayerItem` fails (`status == .failed`) → `isPlaying = false` and a
  short alert “Couldn't play this episode.”
- `AVAudioSession` activation throws → logged; playback is still attempted.

## Out of scope

Playback speed, sleep timer, streaming or downloads, per-episode artwork,
transcripts, chapters, CarPlay-specific UI, sync of listening with streaks.

## Testing

**Unit tests (`BibleFeedKit`, TDD)** — catalog decoding (valid, missing
key → throws), `ResumePolicy` boundaries (nil, 4.9 s, 5 s, 30 s before the
end, exactly at the end, zero duration), `isFinished` at 95 %, `fraction`
clamping.

**Manual (Simulator, iPhone 17 Pro)**
1. Listen tab lists the test episode with its duration.
2. Play: mini-player appears on Feed and Saved; player sheet seeks and
   skips.
3. Lock (⌘L): Lock Screen Now Playing shows title and scrubber; play/pause
   and ±skip work; Dynamic Island shows the player (device or Simulator with
   a Dynamic Island).
4. Kill and relaunch: the episode resumes from the saved position.
5. While playing, switch tabs: no interstitial ad appears.
