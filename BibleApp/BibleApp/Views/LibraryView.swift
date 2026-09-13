import SwiftUI
import BibleFeedKit

struct LibraryView: View {
    let store: ContentStore
    let state: UserState

    @Environment(\.dismiss) private var dismiss
    @State private var filter: Topic?
    @State private var loadedContent: [String: VerseContent] = [:]

    private var savedEntries: [VerseIndexEntry] {
        let savedSet = state.savedSet
        return store.index
            .filter { savedSet.contains($0.id) }
            .filter { filter == nil || $0.topics.contains(filter!) }
    }

    private var availableTopics: [Topic] {
        let savedSet = state.savedSet
        let topics = store.index
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
                        ForEach(savedEntries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                if let content = loadedContent[entry.id] {
                                    Text(content.translations[state.preferredTranslation]?.displayText
                                         ?? content.translations[.kjv]?.displayText ?? "")
                                        .font(.system(.body, design: .serif))
                                } else {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.secondarySystemBackground))
                                        .frame(height: 18)
                                        .redacted(reason: .placeholder)
                                }
                                Text(entry.reference)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    state.toggleSaved(entry.id)
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
                    Menu {
                        ForEach(Translation.allCases, id: \.self) { translation in
                            Button {
                                state.setPreferredTranslation(translation)
                            } label: {
                                if translation == state.preferredTranslation {
                                    Label(translation.displayName, systemImage: "checkmark")
                                } else {
                                    Text(translation.displayName)
                                }
                            }
                        }
                    } label: {
                        Text(state.preferredTranslation.rawValue)
                    }
                    .font(.subheadline)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit topics") {
                        state.reopenTopicPicker()
                        dismiss()
                    }
                    .font(.subheadline)
                }
            }
            .task(id: savedEntries.map(\.id)) {
                let ids = savedEntries.map(\.id).filter { loadedContent[$0] == nil }
                guard !ids.isEmpty else { return }
                let content = await store.content(for: ids)
                for (id, value) in content {
                    loadedContent[id] = value
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
