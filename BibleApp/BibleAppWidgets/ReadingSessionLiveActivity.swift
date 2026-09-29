import ActivityKit
import SwiftUI
import WidgetKit

struct ReadingSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingSessionAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            let isDone = context.isStale || context.state.isComplete
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.reference)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(endDate: context.attributes.endDate, isDone: isDone)
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.text)
                            .font(.system(.callout, design: .serif))
                            .lineLimit(2)
                        if !isDone {
                            SessionControls(isSaved: context.state.isSaved)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "book.fill")
            } compactTrailing: {
                Countdown(endDate: context.attributes.endDate, isDone: isDone)
                    .frame(maxWidth: 44)
            } minimal: {
                Countdown(endDate: context.attributes.endDate, isDone: isDone)
            }
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<ReadingSessionAttributes>

    var body: some View {
        let isDone = context.isStale || context.state.isComplete
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isDone {
                    Label("Session complete · \(versesLabel(context.state.versesRead))",
                          systemImage: "checkmark.circle.fill")
                } else {
                    Label("Reflection · \(versesLabel(context.state.versesRead))",
                          systemImage: "timer")
                    Spacer()
                    Countdown(endDate: context.attributes.endDate, isDone: false)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if !isDone {
                Text(context.state.text)
                    .font(.system(.body, design: .serif))
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }

            Text(context.state.reference)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isDone ? .tertiary : .secondary)

            if !isDone {
                SessionControls(isSaved: context.state.isSaved)
            }
        }
        .padding(16)
    }
}

/// Counts down to the session end without the app having to push updates.
private struct Countdown: View {
    let endDate: Date
    let isDone: Bool

    var body: some View {
        if isDone || endDate <= .now {
            Image(systemName: "checkmark")
        } else {
            Text(timerInterval: Date.now...endDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Filled in once the Lock Screen intents exist.
private struct SessionControls: View {
    let isSaved: Bool

    var body: some View {
        EmptyView()
    }
}

private func versesLabel(_ count: Int) -> String {
    count == 1 ? "1 verse" : "\(count) verses"
}

private extension ReadingSessionAttributes {
    static let preview = ReadingSessionAttributes(endDate: .now.addingTimeInterval(450))
}

private extension ReadingSessionAttributes.ContentState {
    static let short = Self(verseID: "PSA.46.10", reference: "Psalm 46:10",
                            text: "Be still, and know that I am God: I will be exalted among the heathen, I will be exalted in the earth.",
                            versesRead: 3, isSaved: false, isComplete: false)
    static let long = Self(verseID: "EPH.1.3", reference: "Ephesians 1:3",
                           text: "Blessed be the God and Father of our Lord Jesus Christ, who hath blessed us with all spiritual blessings in heavenly places in Christ: According as he hath chosen us in him before the foundation of the world, that we…",
                           versesRead: 1, isSaved: true, isComplete: false)
    static let complete = Self(verseID: "PSA.46.10", reference: "Psalm 46:10",
                               text: "Be still, and know that I am God.",
                               versesRead: 5, isSaved: false, isComplete: true)
}

#Preview("Lock Screen", as: .content, using: ReadingSessionAttributes.preview) {
    ReadingSessionLiveActivity()
} contentStates: {
    ReadingSessionAttributes.ContentState.short
    ReadingSessionAttributes.ContentState.long
    ReadingSessionAttributes.ContentState.complete
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: ReadingSessionAttributes.preview) {
    ReadingSessionLiveActivity()
} contentStates: {
    ReadingSessionAttributes.ContentState.short
    ReadingSessionAttributes.ContentState.long
}

#Preview("Compact", as: .dynamicIsland(.compact), using: ReadingSessionAttributes.preview) {
    ReadingSessionLiveActivity()
} contentStates: {
    ReadingSessionAttributes.ContentState.short
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: ReadingSessionAttributes.preview) {
    ReadingSessionLiveActivity()
} contentStates: {
    ReadingSessionAttributes.ContentState.short
}
