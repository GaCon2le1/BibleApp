import ActivityKit
import SwiftUI
import WidgetKit

struct VerseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VerseLyricsAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "book.fill")
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBody(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "book.fill")
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
            } minimal: {
                Image(systemName: "book.fill")
            }
        }
    }
}

private struct LockScreenView: View {
    let state: VerseLyricsAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.reference)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(state.verseText)
                .font(.headline)
                .lineLimit(3)
            Text(state.secondaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if state.durationSeconds > 0 {
                ProgressView(value: state.elapsedSeconds, total: state.durationSeconds)
                    .tint(.white)
            }
        }
        .padding(16)
    }
}

private struct ExpandedBody: View {
    let state: VerseLyricsAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.reference)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(state.verseText)
                .font(.subheadline)
                .lineLimit(3)
        }
        .padding(.horizontal)
    }
}
