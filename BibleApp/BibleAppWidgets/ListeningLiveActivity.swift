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
                    // Keeps the first letters clear of the island's rounded
                    // bottom corners.
                    .padding(.horizontal, 12)
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
