# Audio Listening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Podcast-style playback of bundled episodes in a new Listen tab, with background audio and the system Now Playing player on the Lock Screen and Dynamic Island.

**Architecture:** Pure catalog/resume/formatting logic lives in `BibleFeedKit` (TDD). The app target gets an `AudioPlayer` singleton wrapping `AVPlayer`, which also drives `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` — iOS renders the Dynamic Island and Lock Screen player from that. SwiftUI adds a Listen tab, a mini-player in `.tabViewBottomAccessory`, and a full-screen player sheet.

**Tech Stack:** Swift 6, SwiftUI (iOS 26.4), AVFoundation, MediaPlayer, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-29-audio-listen-design.md`

## Global Constraints

- iOS deployment target stays **26.4**. No new targets, no widget-extension changes.
- All user-facing strings are **English**.
- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; closures that iOS may call off the main thread (`MPMediaItemArtwork` request handler, remote command handlers, KVO) must be created in a `nonisolated` context and hop to the main actor explicitly.
- The Xcode project uses file-system synchronized groups: new files under `BibleApp/BibleApp/` join the app target automatically. Do not edit `project.pbxproj`.
- Package tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- Skip back **15 s**, skip forward **30 s**. Resume rules: restart when saved < **5 s** or within **30 s** of the end; finished at **≥ 95 %**. Positions saved every **5 s**.
- The working tree holds the user's uncommitted resource reorganisation (staged and unstaged). **Commit only this plan's files**, always with an explicit pathspec: `/usr/bin/git commit -m "…" -- <paths>`. Never `git add -A`, never commit `Resources/audio/test.mp3` or `Resources/json/*`.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

Build command used throughout (run from the repo root):

```bash
xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'generic/platform=iOS Simulator' -quiet build
```

---

### Task 1: Episode catalog, resume policy and time formatting (BibleFeedKit)

**Files:**
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/Episode.swift`
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/ResumePolicy.swift`
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/PlaybackTime.swift`
- Test: `packages/BibleFeedKit/Tests/BibleFeedKitTests/EpisodeTests.swift`
- Test: `packages/BibleFeedKit/Tests/BibleFeedKitTests/ResumePolicyTests.swift`

**Interfaces:**
- Produces:
  - `public struct Episode: Codable, Identifiable, Hashable, Sendable { id: String; title: String; subtitle: String; file: String; durationSeconds: Double }` with a memberwise `public init`.
  - `public enum EpisodeCatalog { static func decode(_ data: Data) throws -> [Episode] }`
  - `public enum ResumePolicy { static func startPosition(saved: Double?, duration: Double) -> Double; static func isFinished(position: Double, duration: Double) -> Bool; static func fraction(position: Double, duration: Double) -> Double }`
  - `public enum PlaybackTime { static func format(_ seconds: Double) -> String }`

- [ ] **Step 1: Write the failing tests**

`packages/BibleFeedKit/Tests/BibleFeedKitTests/EpisodeTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleFeedKit

@Test func catalogDecodesEpisodes() throws {
    let json = """
    {"episodes": [{"id": "test", "title": "Test Episode", "subtitle": "Sample",
                   "file": "test.mp3", "durationSeconds": 1469.136}]}
    """
    let episodes = try EpisodeCatalog.decode(Data(json.utf8))
    #expect(episodes == [Episode(id: "test", title: "Test Episode", subtitle: "Sample",
                                 file: "test.mp3", durationSeconds: 1469.136)])
}

@Test func catalogWithoutEpisodesKeyThrows() {
    #expect(throws: (any Error).self) {
        try EpisodeCatalog.decode(Data(#"{"items": []}"#.utf8))
    }
}

@Test func catalogEpisodeMissingFieldThrows() {
    let json = #"{"episodes": [{"id": "test", "title": "T", "subtitle": "S", "file": "a.mp3"}]}"#
    #expect(throws: (any Error).self) {
        try EpisodeCatalog.decode(Data(json.utf8))
    }
}

@Test func playbackTimeFormatsMinutesAndHours() {
    #expect(PlaybackTime.format(0) == "0:00")
    #expect(PlaybackTime.format(9.9) == "0:09")
    #expect(PlaybackTime.format(65) == "1:05")
    #expect(PlaybackTime.format(1469.136) == "24:29")
    #expect(PlaybackTime.format(3600) == "1:00:00")
    #expect(PlaybackTime.format(3725) == "1:02:05")
}

@Test func playbackTimeShowsNegativeAndNonFiniteAsZero() {
    #expect(PlaybackTime.format(-3) == "0:00")
    #expect(PlaybackTime.format(.nan) == "0:00")
    #expect(PlaybackTime.format(.infinity) == "0:00")
}
```

`packages/BibleFeedKit/Tests/BibleFeedKitTests/ResumePolicyTests.swift`:

```swift
import Testing
@testable import BibleFeedKit

@Test func noSavedPositionStartsAtZero() {
    #expect(ResumePolicy.startPosition(saved: nil, duration: 100) == 0)
}

@Test func positionUnderFiveSecondsStartsAtZero() {
    #expect(ResumePolicy.startPosition(saved: 4.9, duration: 100) == 0)
}

@Test func positionFromFiveSecondsResumes() {
    #expect(ResumePolicy.startPosition(saved: 5, duration: 100) == 5)
}

@Test func positionJustBeforeTheLastThirtySecondsResumes() {
    #expect(ResumePolicy.startPosition(saved: 69.9, duration: 100) == 69.9)
}

@Test func positionInTheLastThirtySecondsStartsAtZero() {
    #expect(ResumePolicy.startPosition(saved: 70, duration: 100) == 0)
    #expect(ResumePolicy.startPosition(saved: 100, duration: 100) == 0)
}

@Test func zeroDurationStartsAtZero() {
    #expect(ResumePolicy.startPosition(saved: 10, duration: 0) == 0)
}

@Test func finishedFromNinetyFivePercent() {
    #expect(!ResumePolicy.isFinished(position: 94.9, duration: 100))
    #expect(ResumePolicy.isFinished(position: 95, duration: 100))
    #expect(ResumePolicy.isFinished(position: 100, duration: 100))
}

@Test func zeroDurationIsNeverFinished() {
    #expect(!ResumePolicy.isFinished(position: 0, duration: 0))
}

@Test func fractionIsClamped() {
    #expect(ResumePolicy.fraction(position: 25, duration: 100) == 0.25)
    #expect(ResumePolicy.fraction(position: -5, duration: 100) == 0)
    #expect(ResumePolicy.fraction(position: 150, duration: 100) == 1)
    #expect(ResumePolicy.fraction(position: 10, duration: 0) == 0)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/BibleFeedKit && swift test --filter "EpisodeTests|ResumePolicyTests"`
Expected: build FAILS with "cannot find 'EpisodeCatalog' in scope" (and similar for `ResumePolicy`, `PlaybackTime`).

- [ ] **Step 3: Implement**

`packages/BibleFeedKit/Sources/BibleFeedKit/Episode.swift`:

```swift
import Foundation

/// One listenable audio episode bundled with the app.
public struct Episode: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    /// Bundle file name including its extension, e.g. "test.mp3".
    public let file: String
    public let durationSeconds: Double

    public init(id: String, title: String, subtitle: String, file: String, durationSeconds: Double) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.file = file
        self.durationSeconds = durationSeconds
    }
}

/// Reads `episodes.json`: `{"episodes": [Episode]}`.
public enum EpisodeCatalog {
    private struct Root: Decodable {
        let episodes: [Episode]
    }

    public static func decode(_ data: Data) throws -> [Episode] {
        try JSONDecoder().decode(Root.self, from: data).episodes
    }
}
```

`packages/BibleFeedKit/Sources/BibleFeedKit/ResumePolicy.swift`:

```swift
/// Where an episode picks up again, and when it counts as heard.
public enum ResumePolicy {
    /// Positions this early aren't worth resuming.
    public static let minimumResume: Double = 5
    /// Positions this close to the end restart the episode instead.
    public static let restartWindow: Double = 30
    public static let finishedFraction: Double = 0.95

    public static func startPosition(saved: Double?, duration: Double) -> Double {
        guard let saved, saved >= minimumResume, saved < duration - restartWindow else { return 0 }
        return saved
    }

    public static func isFinished(position: Double, duration: Double) -> Bool {
        duration > 0 && position >= duration * finishedFraction
    }

    public static func fraction(position: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}
```

`packages/BibleFeedKit/Sources/BibleFeedKit/PlaybackTime.swift`:

```swift
/// Clock-style labels for playback positions: "4:05", or "1:02:05" from an hour.
public enum PlaybackTime {
    public static func format(_ seconds: Double) -> String {
        let total = seconds.isFinite ? Int(max(seconds, 0)) : 0
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let secs = total % 60
        let paddedSeconds = secs < 10 ? "0\(secs)" : "\(secs)"
        if hours > 0 {
            let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(paddedMinutes):\(paddedSeconds)"
        }
        return "\(minutes):\(paddedSeconds)"
    }
}
```

- [ ] **Step 4: Run the whole package suite**

Run: `cd packages/BibleFeedKit && swift test`
Expected: all tests PASS (existing suites plus the new ones).

- [ ] **Step 5: Commit**

```bash
/usr/bin/git add packages/BibleFeedKit/Sources/BibleFeedKit/Episode.swift packages/BibleFeedKit/Sources/BibleFeedKit/ResumePolicy.swift packages/BibleFeedKit/Sources/BibleFeedKit/PlaybackTime.swift packages/BibleFeedKit/Tests/BibleFeedKitTests/EpisodeTests.swift packages/BibleFeedKit/Tests/BibleFeedKitTests/ResumePolicyTests.swift
/usr/bin/git commit -m "Add Episode catalog, ResumePolicy and PlaybackTime

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- packages/BibleFeedKit
```

---

### Task 2: Bundled episode library, progress store, artwork and background mode

**Files:**
- Create: `BibleApp/BibleApp/Resources/audio/episodes.json`
- Create: `BibleApp/BibleApp/Audio/EpisodeLibrary.swift`
- Create: `BibleApp/BibleApp/Audio/PlaybackProgressStore.swift`
- Create: `BibleApp/BibleApp/Assets.xcassets/AudioArtwork.imageset/Contents.json` and `artwork.png` (copy of `AppIcon.appiconset/512.png`)
- Modify: `BibleApp/BibleApp/Info.plist` (add `UIBackgroundModes`)

**Interfaces:**
- Consumes: `Episode`, `EpisodeCatalog.decode` (Task 1).
- Produces:
  - `struct EpisodeLibrary { let episodes: [Episode]; static let bundled: EpisodeLibrary; static func fileURL(for episode: Episode, in bundle: Bundle = .main) -> URL? }`
  - `struct PlaybackProgressStore { init(defaults: UserDefaults = .standard); func position(for episodeID: String) -> Double?; func save(_ seconds: Double, for episodeID: String) }`
  - Image asset named `AudioArtwork`.

- [ ] **Step 1: Add the catalog**

`BibleApp/BibleApp/Resources/audio/episodes.json`:

```json
{
  "episodes": [
    {
      "id": "test",
      "title": "Test Episode",
      "subtitle": "Sample narration",
      "file": "test.mp3",
      "durationSeconds": 1469.136
    }
  ]
}
```

- [ ] **Step 2: Add `EpisodeLibrary`**

`BibleApp/BibleApp/Audio/EpisodeLibrary.swift`:

```swift
import Foundation
import BibleFeedKit

/// The episodes listed in the bundled `episodes.json` whose audio file is
/// actually in the bundle.
struct EpisodeLibrary {
    let episodes: [Episode]

    static let bundled = EpisodeLibrary(bundle: .main)

    init(bundle: Bundle) {
        guard let url = bundle.url(forResource: "episodes", withExtension: "json") else {
            assertionFailure("episodes.json is missing from the bundle")
            episodes = []
            return
        }
        do {
            let all = try EpisodeCatalog.decode(Data(contentsOf: url))
            episodes = all.filter { episode in
                let found = Self.fileURL(for: episode, in: bundle) != nil
                assert(found, "\(episode.file) is missing from the bundle")
                return found
            }
        } catch {
            assertionFailure("episodes.json failed to decode: \(error)")
            episodes = []
        }
    }

    static func fileURL(for episode: Episode, in bundle: Bundle = .main) -> URL? {
        let name = (episode.file as NSString).deletingPathExtension
        let ext = (episode.file as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: ext)
    }
}
```

- [ ] **Step 3: Add `PlaybackProgressStore`**

`BibleApp/BibleApp/Audio/PlaybackProgressStore.swift`:

```swift
import Foundation

/// How far into each episode the listener got, in seconds. Written every few
/// seconds while playing, so it lives in `UserDefaults` rather than SwiftData.
struct PlaybackProgressStore {
    private let defaults: UserDefaults
    private let key = "audio.positions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func position(for episodeID: String) -> Double? {
        positions[episodeID]
    }

    func save(_ seconds: Double, for episodeID: String) {
        var all = positions
        all[episodeID] = seconds
        defaults.set(all, forKey: key)
    }

    private var positions: [String: Double] {
        defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }
}
```

- [ ] **Step 4: Add the artwork asset**

```bash
mkdir -p BibleApp/BibleApp/Assets.xcassets/AudioArtwork.imageset
cp BibleApp/BibleApp/Assets.xcassets/AppIcon.appiconset/512.png BibleApp/BibleApp/Assets.xcassets/AudioArtwork.imageset/artwork.png
```

`BibleApp/BibleApp/Assets.xcassets/AudioArtwork.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "artwork.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 5: Enable background audio**

In `BibleApp/BibleApp/Info.plist`, insert directly before `<key>NSUserTrackingUsageDescription</key>`:

```xml
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
	</array>
```

- [ ] **Step 6: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **` (or no output with `-quiet` and exit code 0).

- [ ] **Step 7: Commit**

```bash
/usr/bin/git add BibleApp/BibleApp/Resources/audio/episodes.json BibleApp/BibleApp/Audio BibleApp/BibleApp/Assets.xcassets/AudioArtwork.imageset BibleApp/BibleApp/Info.plist
/usr/bin/git commit -m "Add the bundled episode library, progress store and background audio mode

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- BibleApp/BibleApp/Resources/audio/episodes.json BibleApp/BibleApp/Audio BibleApp/BibleApp/Assets.xcassets/AudioArtwork.imageset BibleApp/BibleApp/Info.plist
```

---

### Task 3: `AudioPlayer` with Now Playing and remote commands

**Files:**
- Create: `BibleApp/BibleApp/Audio/AudioPlayer.swift`

**Interfaces:**
- Consumes: `Episode`, `ResumePolicy` (Task 1); `EpisodeLibrary.fileURL(for:)`, `PlaybackProgressStore`, `AudioArtwork` asset (Task 2).
- Produces: `@Observable final class AudioPlayer` with
  - `static let shared: AudioPlayer`
  - read-only `current: Episode?`, `isPlaying: Bool`, `elapsed: Double`, `duration: Double`
  - `var alertMessage: String?`
  - `func play(_ episode: Episode)`, `func resume()`, `func pause()`, `func togglePlayPause()`, `func skip(by seconds: Double)`, `func seek(to seconds: Double)`

- [ ] **Step 1: Write the player**

`BibleApp/BibleApp/Audio/AudioPlayer.swift`:

```swift
import AVFoundation
import MediaPlayer
import UIKit
import os
import BibleFeedKit

/// Plays bundled episodes, keeps going in the background, and publishes
/// them to the system Now Playing player — which is what the Lock Screen,
/// Control Center and the Dynamic Island show.
@Observable
final class AudioPlayer {
    static let shared = AudioPlayer()

    private(set) var current: Episode?
    private(set) var isPlaying = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    var alertMessage: String?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let progress = PlaybackProgressStore()
    @ObservationIgnored private let artwork = UIImage(named: "AudioArtwork").map(AudioPlayer.makeArtwork)
    @ObservationIgnored private let log = Logger(subsystem: "com.trailbyte.bible", category: "audio")
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var lastSavedElapsed: Double = 0
    @ObservationIgnored private var didConfigureSession = false
    @ObservationIgnored private var resumeAfterInterruption = false

    private init() {
        Self.registerRemoteCommands()
        observeSystemEvents()
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                       queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    // MARK: - Controls

    /// Loads `episode` at its resume position and plays it. If it is already
    /// loaded, just resumes.
    func play(_ episode: Episode) {
        if current?.id == episode.id {
            resume()
            return
        }
        guard let url = EpisodeLibrary.fileURL(for: episode) else {
            alertMessage = "Couldn't play this episode."
            return
        }
        saveProgress()
        let item = AVPlayerItem(url: url)
        observeStatus(of: item)
        player.replaceCurrentItem(with: item)
        current = episode
        duration = episode.durationSeconds
        let start = ResumePolicy.startPosition(saved: progress.position(for: episode.id),
                                               duration: duration)
        elapsed = start
        lastSavedElapsed = start
        if start > 0 {
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        resume()
    }

    func resume() {
        guard current != nil else { return }
        activateSession()
        if duration > 0, elapsed >= duration - 0.5 {
            // Finished earlier: play again from the start.
            elapsed = 0
            player.seek(to: .zero)
        }
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        saveProgress()
        updateNowPlaying()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func skip(by seconds: Double) {
        seek(to: elapsed + seconds)
    }

    func seek(to seconds: Double) {
        guard current != nil else { return }
        let target = min(max(seconds, 0), duration)
        elapsed = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        saveProgress()
        updateNowPlaying()
    }

    // MARK: - Playback events

    private func tick(_ seconds: Double) {
        guard isPlaying, seconds.isFinite else { return }
        elapsed = seconds
        if abs(seconds - lastSavedElapsed) >= 5 {
            saveProgress()
        }
    }

    private func itemDidEnd(_ item: ObjectIdentifier?) {
        guard item == player.currentItem.map(ObjectIdentifier.init) else { return }
        isPlaying = false
        elapsed = duration
        saveProgress()
        updateNowPlaying()
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
                duration = seconds
                updateNowPlaying()
            }
        case .failed:
            fail()
        default:
            break
        }
    }

    private func fail() {
        player.pause()
        isPlaying = false
        alertMessage = "Couldn't play this episode."
        updateNowPlaying()
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?,
                                    options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            // The system has already paused the player.
            resumeAfterInterruption = isPlaying
            isPlaying = false
            saveProgress()
            updateNowPlaying()
        case .ended:
            if resumeAfterInterruption, options.contains(.shouldResume) {
                resume()
            }
            resumeAfterInterruption = false
        default:
            break
        }
    }

    // MARK: - Setup

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            if !didConfigureSession {
                try session.setCategory(.playback, mode: .spokenAudio)
                didConfigureSession = true
            }
            try session.setActive(true)
        } catch {
            log.error("Audio session activation failed: \(error.localizedDescription)")
        }
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            let status = item.status
            Task { @MainActor in AudioPlayer.shared.itemStatusChanged(status) }
        }
    }

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                           object: nil, queue: .main) { [weak self] note in
            let item = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.itemDidEnd(item) }
        }
        center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                           object: nil, queue: .main) { [weak self] note in
            let item = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, item == self.player.currentItem.map(ObjectIdentifier.init) else { return }
                self.fail()
            }
        }
        center.addObserver(forName: AVAudioSession.interruptionNotification,
                           object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = AVAudioSession.InterruptionOptions(
                rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated { self?.handleInterruption(type, options: options) }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification,
                           object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            guard reason == .oldDeviceUnavailable else { return }
            // Headphones unplugged: stop rather than play out loud.
            MainActor.assumeIsolated { self?.pause() }
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveProgress() }
        }
    }

    /// Lock Screen, Dynamic Island, Control Center and headphone buttons.
    /// Handlers may run off the main thread, so they are built here, outside
    /// the main actor, and hop onto it.
    nonisolated private static func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor @Sendable (AudioPlayer) -> Void) {
            command.addTarget { _ in
                Task { @MainActor in action(AudioPlayer.shared) }
                return .success
            }
        }
        on(center.playCommand) { $0.resume() }
        on(center.pauseCommand) { $0.pause() }
        on(center.togglePlayPauseCommand) { $0.togglePlayPause() }
        center.skipBackwardCommand.preferredIntervals = [15]
        on(center.skipBackwardCommand) { $0.skip(by: -15) }
        center.skipForwardCommand.preferredIntervals = [30]
        on(center.skipForwardCommand) { $0.skip(by: 30) }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            Task { @MainActor in AudioPlayer.shared.seek(to: position) }
            return .success
        }
    }

    /// Built outside the main actor: iOS calls the request handler on a
    /// background queue.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // MARK: - Private

    private func saveProgress() {
        guard let current else { return }
        progress.save(elapsed, for: current.id)
        lastSavedElapsed = elapsed
    }

    /// Only called on state changes; iOS advances the elapsed time on its own
    /// from the playback rate.
    private func updateNowPlaying() {
        guard let current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: "Bible App",
            MPMediaItemPropertyAlbumTitle: current.subtitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: success. If Swift 6 isolation diagnostics appear on a notification/KVO/remote-command closure, keep the rule from Global Constraints: extract `Sendable` values (`UInt`, enums, `ObjectIdentifier`) outside, then hop with `MainActor.assumeIsolated` (main-queue observers) or `Task { @MainActor in … }` (anything else). Do not silence with `@preconcurrency` or `nonisolated(unsafe)`.

- [ ] **Step 3: Commit**

```bash
/usr/bin/git add BibleApp/BibleApp/Audio/AudioPlayer.swift
/usr/bin/git commit -m "Add AudioPlayer with background playback and system Now Playing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- BibleApp/BibleApp/Audio/AudioPlayer.swift
```

---

### Task 4: Listen tab, mini-player and player sheet

**Files:**
- Create: `BibleApp/BibleApp/Views/ListenView.swift`
- Create: `BibleApp/BibleApp/Views/MiniPlayerView.swift`
- Create: `BibleApp/BibleApp/Views/PlayerView.swift`
- Modify: `BibleApp/BibleApp/ContentView.swift`

**Interfaces:**
- Consumes: `AudioPlayer.shared` API (Task 3); `EpisodeLibrary.bundled`, `PlaybackProgressStore` (Task 2); `ResumePolicy`, `PlaybackTime` (Task 1).
- Produces: `ListenView(onOpenPlayer: () -> Void)`, `MiniPlayerView(onOpen: () -> Void)`, `PlayerView()`; `RootTab.listen`.

- [ ] **Step 1: `ListenView`**

`BibleApp/BibleApp/Views/ListenView.swift`:

```swift
import SwiftUI
import BibleFeedKit

/// The Listen tab: bundled episodes and how far each has been heard.
struct ListenView: View {
    let onOpenPlayer: () -> Void

    private let episodes = EpisodeLibrary.bundled.episodes
    private let audio = AudioPlayer.shared
    private let progress = PlaybackProgressStore()

    var body: some View {
        NavigationStack {
            Group {
                if episodes.isEmpty {
                    ContentUnavailableView("No episodes",
                                           systemImage: "headphones",
                                           description: Text("Audio episodes could not be loaded."))
                } else {
                    List(episodes) { episode in
                        Button {
                            audio.play(episode)
                            onOpenPlayer()
                        } label: {
                            EpisodeRow(episode: episode,
                                       position: position(of: episode),
                                       isCurrent: audio.current?.id == episode.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Listen")
        }
    }

    /// The live position for the loaded episode, the saved one otherwise.
    private func position(of episode: Episode) -> Double {
        if audio.current?.id == episode.id { return audio.elapsed }
        return progress.position(for: episode.id) ?? 0
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let position: Double
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCurrent ? "speaker.wave.2.fill" : "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.headline)
                Text(episode.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                detail
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var detail: some View {
        let duration = episode.durationSeconds
        if ResumePolicy.isFinished(position: position, duration: duration) {
            Label("Played", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if position > 0 {
            HStack(spacing: 8) {
                ProgressView(value: ResumePolicy.fraction(position: position, duration: duration))
                    .frame(maxWidth: 120)
                Text("\(PlaybackTime.format(duration - position)) left")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(PlaybackTime.format(duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: `MiniPlayerView`**

`BibleApp/BibleApp/Views/MiniPlayerView.swift`:

```swift
import SwiftUI
import BibleFeedKit

/// The loaded episode above the tab bar, on every tab.
struct MiniPlayerView: View {
    let onOpen: () -> Void

    private let audio = AudioPlayer.shared

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image("AudioArtwork")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(audio.current?.title ?? "")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Open player")
            Button {
                audio.togglePlayPause()
            } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .padding(.trailing, 4)
    }
}
```

- [ ] **Step 3: `PlayerView`**

`BibleApp/BibleApp/Views/PlayerView.swift`:

```swift
import SwiftUI
import BibleFeedKit

/// Full-screen player for the loaded episode.
struct PlayerView: View {
    private let audio = AudioPlayer.shared
    /// Where the slider is while being dragged; seeking waits for release.
    @State private var scrubPosition: Double?

    private var shownPosition: Double { scrubPosition ?? audio.elapsed }

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Image("AudioArtwork")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .frame(maxWidth: 280)
                .shadow(radius: 16, y: 8)
            VStack(spacing: 6) {
                Text(audio.current?.title ?? "")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(audio.current?.subtitle ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            scrubber
            controls
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .presentationDragIndicator(.visible)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { shownPosition }, set: { scrubPosition = $0 }),
                   in: 0...max(audio.duration, 1)) { editing in
                if !editing, let target = scrubPosition {
                    audio.seek(to: target)
                    scrubPosition = nil
                }
            }
            .accessibilityLabel("Playback position")
            HStack {
                Text(PlaybackTime.format(shownPosition))
                Spacer()
                Text("-" + PlaybackTime.format(audio.duration - shownPosition))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 44) {
            Button {
                audio.skip(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
            }
            .accessibilityLabel("Back 15 seconds")
            Button {
                audio.togglePlayPause()
            } label: {
                Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
            }
            .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
            Button {
                audio.skip(by: 30)
            } label: {
                Image(systemName: "goforward.30")
            }
            .accessibilityLabel("Forward 30 seconds")
        }
        .font(.system(size: 30))
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 4: Wire into `ContentView`**

In `BibleApp/BibleApp/ContentView.swift`:

Replace the enum:

```swift
private enum RootTab: Hashable {
    case feed
    case saved
    case listen
}
```

Add after `@State private var didCompleteFirstActivation = false`:

```swift
    @State private var isPlayerPresented = false
    private let audio = AudioPlayer.shared
```

Replace the `TabView { … }` block (from `TabView(selection: $selectedTab) {` through its closing `}` before `.onChange(of: selectedTab)`) with:

```swift
                    TabView(selection: $selectedTab) {
                        FeedView(store: store, state: state)
                            .tabItem { Label("Feed", systemImage: "book") }
                            .tag(RootTab.feed)
                        LibraryView(store: store, state: state)
                            .tabItem { Label("Saved", systemImage: "bookmark") }
                            .tag(RootTab.saved)
                        ListenView { isPlayerPresented = true }
                            .tabItem { Label("Listen", systemImage: "headphones") }
                            .tag(RootTab.listen)
                    }
                    .tabViewBottomAccessory(isEnabled: audio.current != nil) {
                        MiniPlayerView { isPlayerPresented = true }
                    }
                    .sheet(isPresented: $isPlayerPresented) {
                        PlayerView()
                    }
                    .alert("Playback",
                           isPresented: Binding(get: { audio.alertMessage != nil },
                                                set: { if !$0 { audio.alertMessage = nil } })) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(audio.alertMessage ?? "")
                    }
```

(the existing `.onChange(of: selectedTab)` and `.onOpenURL` modifiers stay attached after these).

If `tabViewBottomAccessory(isEnabled:content:)` is unavailable in the SDK, use `.tabViewBottomAccessory { if audio.current != nil { MiniPlayerView { … } } }` and note it in the report.

- [ ] **Step 5: Build**

Run the build command. Expected: success.

- [ ] **Step 6: Commit**

```bash
/usr/bin/git add BibleApp/BibleApp/Views/ListenView.swift BibleApp/BibleApp/Views/MiniPlayerView.swift BibleApp/BibleApp/Views/PlayerView.swift BibleApp/BibleApp/ContentView.swift
/usr/bin/git commit -m "Add the Listen tab, mini-player and player sheet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- BibleApp/BibleApp/Views/ListenView.swift BibleApp/BibleApp/Views/MiniPlayerView.swift BibleApp/BibleApp/Views/PlayerView.swift BibleApp/BibleApp/ContentView.swift
```

---

### Task 5: Skip ads while audio is playing

**Files:**
- Modify: `BibleApp/BibleApp/Ads/AdsCoordinator.swift` (`showAppOpenAdIfEligible`, `tabDidChange`)

**Interfaces:**
- Consumes: `AudioPlayer.shared.isPlaying` (Task 3).

- [ ] **Step 1: Gate both triggers**

Replace the two methods:

```swift
    /// Called when the app becomes active, either at cold start or after
    /// returning from the background. Skipped while an episode is playing,
    /// since an ad with sound would cut into it.
    func showAppOpenAdIfEligible() {
        guard isOnboardingComplete, !AudioPlayer.shared.isPlaying,
              let rootViewController = RootViewController.current() else { return }
        appOpenAd.showIfEligible(from: rootViewController)
    }

    /// Called every time the user switches tabs in the root nav bar.
    /// Skipped while an episode is playing.
    func tabDidChange() {
        guard isOnboardingComplete, !AudioPlayer.shared.isPlaying,
              let rootViewController = RootViewController.current() else { return }
        interstitialAd.showIfEligible(from: rootViewController)
    }
```

- [ ] **Step 2: Build**

Run the build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
/usr/bin/git add BibleApp/BibleApp/Ads/AdsCoordinator.swift
/usr/bin/git commit -m "Skip app-open and interstitial ads while audio is playing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- BibleApp/BibleApp/Ads/AdsCoordinator.swift
```

---

### Task 6: Manual verification in the Simulator

No code unless a defect is found (fix it in the relevant file, rebuild, commit with a pathspec).

- [ ] **Step 1:** Build and launch on the iPhone 17 Pro Simulator (iOS 26.4). Simulator taps need `duration: 0.15`.
- [ ] **Step 2:** Listen tab shows “Test Episode”, “Sample narration”, `24:29`.
- [ ] **Step 3:** Tap it: player sheet opens and audio plays; elapsed time advances; ⏪15 / 30⏩ and dragging the slider move the position.
- [ ] **Step 4:** Dismiss the sheet: the mini-player shows on Listen, Feed and Saved; play/pause works; tapping it reopens the player. Switching tabs while playing shows no interstitial.
- [ ] **Step 5:** Lock (⌘L): the Lock Screen shows the Now Playing player with title, artwork and scrubber; play/pause and skip work from there.
- [ ] **Step 6:** Pause at a position past 5 s, terminate the app, relaunch: the Listen row shows a progress bar and “… left”; tapping resumes from the saved position.
- [ ] **Step 7:** `cd packages/BibleFeedKit && swift test` passes.
