import SwiftUI
import BibleFeedKit

struct FeedView: View {
    let store: ContentStore
    let state: UserState

    @State private var queue: [VerseIndexEntry] = []
    @State private var loadedContent: [String: VerseContent] = [:]
    @State private var isReplay = false
    @State private var seenTasks: [String: Task<Void, Never>] = [:]
    @State private var showLibrary = false

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                if isReplay {
                    MilestoneCard(count: store.index.count)
                        .containerRelativeFrame(.vertical)
                }
                ForEach(Array(queue.enumerated()), id: \.element.id) { position, entry in
                    VerseCard(entry: entry,
                              content: loadedContent[entry.id],
                              translation: state.preferredTranslation,
                              isSaved: state.savedSet.contains(entry.id),
                              onSave: { state.toggleSaved(entry.id) })
                        .containerRelativeFrame(.vertical)
                        .onAppear {
                            startSeenTimer(entry)
                            loadContent(around: position)
                        }
                        .onDisappear { cancelSeenTimer(entry) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            HStack {
                Label("\(state.streak)", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.streak > 0 ? .orange : .secondary)
                Spacer()
                Button {
                    showLibrary = true
                } label: {
                    Image(systemName: "bookmark")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Saved verses")
            }
            .padding(.horizontal, 24)
            .safeAreaPadding(.top, 8)
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView(store: store, state: state)
        }
        .onAppear(perform: rebuild)
    }

    private func rebuild() {
        let engine = FeedEngine(verses: store.index)
        let result = engine.queue(selectedTopics: state.topics,
                                  seen: state.seenSet,
                                  saved: state.savedSet,
                                  seed: UInt64.random(in: 0...UInt64.max))
        queue = result.verses
        isReplay = result.isReplay
        loadContent(around: 0)
    }

    /// Fetches content for the card at `position` plus the next one, since
    /// the feed pages forward through `queue` in order.
    private func loadContent(around position: Int) {
        guard queue.indices.contains(position) else { return }
        let end = min(queue.count, position + 2)
        let ids = queue[position..<end].map(\.id).filter { loadedContent[$0] == nil }
        guard !ids.isEmpty else { return }
        Task {
            let content = await store.content(for: ids)
            for (id, value) in content {
                loadedContent[id] = value
            }
        }
    }

    /// A card counts as seen only after two seconds on screen, so a flick
    /// past does not consume it.
    private func startSeenTimer(_ entry: VerseIndexEntry) {
        guard seenTasks[entry.id] == nil else { return }
        seenTasks[entry.id] = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            state.markSeen(entry.id)
        }
    }

    private func cancelSeenTimer(_ entry: VerseIndexEntry) {
        seenTasks[entry.id]?.cancel()
        seenTasks[entry.id] = nil
    }
}

private struct MilestoneCard: View {
    let count: Int

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("You've read all \(count) verses")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Starting again with the ones you saved.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
