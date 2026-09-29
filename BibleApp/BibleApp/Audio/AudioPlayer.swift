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
