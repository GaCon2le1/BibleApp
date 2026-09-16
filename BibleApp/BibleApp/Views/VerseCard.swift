import SwiftUI
import BibleFeedKit

struct VerseCard: View {
    let entry: VerseIndexEntry
    let content: VerseContent?
    let translation: Translation
    let isSaved: Bool
    let onSave: () -> Void
    let hasAudio: Bool
    let isNarrating: Bool
    let onListen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            Group {
                if let content {
                    Text(content.translations[translation]?.displayText
                         ?? content.translations[.kjv]?.displayText ?? "")
                        .font(.system(.title2, design: .serif))
                        .lineSpacing(6)
                        .transition(.opacity)
                } else {
                    SkeletonBlock(lines: 3)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: content)

            Text(entry.reference)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Divider()

            Group {
                if let content {
                    Text(content.context)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .transition(.opacity)
                } else {
                    SkeletonBlock(lines: 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: content)

            Spacer()

            HStack {
                ForEach(entry.topics, id: \.self) { topic in
                    Text(topic.rawValue.capitalized)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                Spacer()
                if hasAudio {
                    Button(action: onListen) {
                        Image(systemName: isNarrating ? "waveform" : "play.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel(isNarrating ? "Now narrating" : "Listen (KJV)")
                }
                Button(action: onSave) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.title3)
                }
                .accessibilityLabel(isSaved ? "Remove from saved" : "Save verse")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SkeletonBlock: View {
    let lines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<lines, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 16)
            }
        }
        .redacted(reason: .placeholder)
    }
}
