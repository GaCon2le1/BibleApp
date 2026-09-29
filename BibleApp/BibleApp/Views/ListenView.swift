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
