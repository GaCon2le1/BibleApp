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
