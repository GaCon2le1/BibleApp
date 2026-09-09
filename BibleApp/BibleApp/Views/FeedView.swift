import SwiftUI
import BibleFeedKit

struct FeedView: View {
    let store: ContentStore
    let state: UserState

    @State private var queue: [Verse] = []
    @State private var isReplay = false
    @State private var seenTasks: [String: Task<Void, Never>] = [:]
    @State private var showLibrary = false

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                if isReplay {
                    MilestoneCard(count: store.verses.count)
                        .containerRelativeFrame(.vertical)
                }
                ForEach(queue) { verse in
                    VerseCard(verse: verse,
                              translation: .kjv,
                              isSaved: state.savedSet.contains(verse.id),
                              onSave: { state.toggleSaved(verse.id) })
                        .containerRelativeFrame(.vertical)
                        .onAppear { startSeenTimer(verse) }
                        .onDisappear { cancelSeenTimer(verse) }
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
        let engine = FeedEngine(verses: store.verses)
        let result = engine.queue(selectedTopics: state.topics,
                                  seen: state.seenSet,
                                  saved: state.savedSet,
                                  seed: UInt64.random(in: 0...UInt64.max))
        queue = result.verses
        isReplay = result.isReplay
    }

    /// A card counts as seen only after two seconds on screen, so a flick
    /// past does not consume it.
    private func startSeenTimer(_ verse: Verse) {
        guard seenTasks[verse.id] == nil else { return }
        seenTasks[verse.id] = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            state.markSeen(verse.id)
        }
    }

    private func cancelSeenTimer(_ verse: Verse) {
        seenTasks[verse.id]?.cancel()
        seenTasks[verse.id] = nil
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
