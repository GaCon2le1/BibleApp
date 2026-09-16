import AVFoundation
import MediaPlayer
import BibleFeedKit

/// Owns narrated playback end to end: the AVPlayer itself, the system Now
/// Playing card (MPNowPlayingInfoCenter), Lock Screen / Control Center
/// remote commands, and walking forward through the feed's current queue.
/// KJV-only in v1 — every clip it plays is the KJV narration regardless of
/// `UserState.preferredTranslation` (see the design doc's "Why KJV-only").
@MainActor
@Observable
final class AudioPlaybackEngine: NSObject {
    private(set) var currentVerseID: String?
    private(set) var isPlaying = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    /// Fires whenever playback moves to a new verse (including the first
    /// one `start` plays), so observers can update Now Playing info, the
    /// Live Activity, and feed auto-scroll without polling.
    var onVerseChanged: ((VerseIndexEntry) -> Void)?
    var onStopped: (() -> Void)?

    private let contentStore: ContentStore
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var queue: [VerseIndexEntry] = []
    private var position = 0

    init(contentStore: ContentStore) {
        self.contentStore = contentStore
        super.init()
        configureRemoteCommands()
    }

    func start(queue: [VerseIndexEntry], at index: Int) {
        guard queue.indices.contains(index) else { return }
        activateAudioSession()
        self.queue = queue
        self.position = index
        playCurrent()
    }

    func stop() {
        teardownCurrentItem()
        player = nil
        isPlaying = false
        currentVerseID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onStopped?()
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    func advance() {
        guard position + 1 < queue.count else { stop(); return }
        position += 1
        playCurrent()
    }

    func rewindToPrevious() {
        guard position > 0 else { return }
        position -= 1
        playCurrent()
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    private func playCurrent() {
        guard queue.indices.contains(position) else { return }
        let entry = queue[position]
        guard let url = contentStore.audioURL(for: entry.id) else {
            // No narration for this verse — skip it rather than stalling
            // Listen mode on a silent gap.
            advance()
            return
        }

        teardownCurrentItem()
        let item = AVPlayerItem(url: url)
        let newPlayer = player ?? AVPlayer()
        newPlayer.replaceCurrentItem(with: item)
        player = newPlayer
        currentVerseID = entry.id
        isPlaying = true
        newPlayer.play()
        observe(item: item, on: newPlayer)
        onVerseChanged?(entry)
        updateNowPlayingInfo()
    }

    private func observe(item: AVPlayerItem, on player: AVPlayer) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.elapsed = time.seconds
            self.duration = item.asset.duration.seconds.isFinite ? item.asset.duration.seconds : 0
        }
    }

    private func teardownCurrentItem() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        elapsed = 0
        duration = 0
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self, !self.isPlaying, self.player != nil else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isPlaying else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.advance()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.rewindToPrevious()
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let verseID = currentVerseID,
              let entry = queue.first(where: { $0.id == verseID }) else { return }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: entry.reference,
            MPMediaItemPropertyArtist: "BibleApp",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
