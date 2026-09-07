import SwiftUI
import BibleFeedKit

struct LibraryView: View {
    let store: ContentStore
    let state: UserState

    @Environment(\.dismiss) private var dismiss
    @State private var filter: Topic?

    private var saved: [Verse] {
        let savedSet = state.savedSet
        return store.verses
            .filter { savedSet.contains($0.id) }
            .filter { filter == nil || $0.topics.contains(filter!) }
    }

    private var availableTopics: [Topic] {
        let savedSet = state.savedSet
        let topics = store.verses
            .filter { savedSet.contains($0.id) }
            .flatMap(\.topics)
        return Array(Set(topics)).sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if state.savedIDs.isEmpty {
                    ContentUnavailableView("Nothing saved yet",
                                           systemImage: "bookmark",
                                           description: Text("Tap the bookmark on a verse to keep it here."))
                } else {
                    List {
                        if !availableTopics.isEmpty {
                            Section {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 8) {
                                        FilterChip(title: "All", isOn: filter == nil) { filter = nil }
                                        ForEach(availableTopics, id: \.self) { topic in
                                            FilterChip(title: topic.rawValue.capitalized,
                                                       isOn: filter == topic) { filter = topic }
                                        }
                                    }
                                }
                                .scrollIndicators(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        }
                        ForEach(saved) { verse in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verse.displayText)
                                    .font(.system(.body, design: .serif))
                                Text(verse.reference)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    state.toggleSaved(verse.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit topics") {
                        state.reopenTopicPicker()
                        dismiss()
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(isOn ? Color.accentColor : Color(.secondarySystemBackground))
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .clipShape(Capsule())
    }
}
