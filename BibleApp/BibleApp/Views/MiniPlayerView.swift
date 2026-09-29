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
