import SwiftUI
import BibleFeedKit

struct VerseCard: View {
    let verse: Verse
    let translation: Translation
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            Text(verse.translations[translation]?.displayText ?? "")
                .font(.system(.title2, design: .serif))
                .lineSpacing(6)

            Text(verse.reference)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Divider()

            Text(verse.context)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Spacer()

            HStack {
                ForEach(verse.topics, id: \.self) { topic in
                    Text(topic.rawValue.capitalized)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                Spacer()
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
