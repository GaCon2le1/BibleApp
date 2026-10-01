import SwiftUI
import SwiftData

private enum RootTab: Hashable {
    case feed
    case saved
    case listen
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var states: [UserState]
    @State private var store = ContentStore()
    @State private var selectedTab: RootTab = .feed
    @State private var pinnedVerseID: String?
    @State private var didCompleteFirstActivation = false
    @State private var isPlayerPresented = false
    private let audio = AudioPlayer.shared
    let ads: AdsCoordinator

    var body: some View {
        Group {
            if store.loadFailed {
                ContentUnavailableView {
                    Label("Content unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The verse library could not be loaded.")
                } actions: {
                    Button("Try again") { store.load() }
                }
            } else if let state = states.first {
                if state.hasCompletedOnboarding {
                    TabView(selection: $selectedTab) {
                        FeedView(store: store, state: state, pinnedID: pinnedVerseID)
                            .tabItem { Label("Feed", systemImage: "book") }
                            .tag(RootTab.feed)
                        LibraryView(store: store, state: state)
                            .tabItem { Label("Saved", systemImage: "bookmark") }
                            .tag(RootTab.saved)
                        ListenView { isPlayerPresented = true }
                            .tabItem { Label("Listen", systemImage: "headphones") }
                            .tag(RootTab.listen)
                    }
                    .tabViewBottomAccessory(isEnabled: audio.current != nil) {
                        MiniPlayerView { isPlayerPresented = true }
                    }
                    .sheet(isPresented: $isPlayerPresented) {
                        PlayerView()
                    }
                    .alert("Playback",
                           isPresented: Binding(get: { audio.alertMessage != nil },
                                                set: { if !$0 { audio.alertMessage = nil } })) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(audio.alertMessage ?? "")
                    }
                    .onChange(of: selectedTab) { _, _ in
                        ads.tabDidChange()
                    }
                    .onOpenURL { url in
                        guard url.scheme == "bibleapp" else { return }
                        switch url.host {
                        case "feed": selectedTab = .feed
                        case "listen": selectedTab = .listen
                        case "verse":
                            let id = url.lastPathComponent
                            if !id.isEmpty, id != "/" {
                                pinnedVerseID = id
                                selectedTab = .feed
                            }
                        default: break
                        }
                    }
                } else {
                    OnboardingView(state: state)
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            store.load()
            if states.isEmpty {
                context.insert(UserState())
            }
        }
        .onChange(of: states.first?.hasCompletedOnboarding) { _, completed in
            ads.setOnboardingComplete(completed ?? false)
        }
        .task {
            await ReadingSessionController.shared.reconcile()
            LyricsActivityController.shared.endStray()
        }
        .task(id: "\(store.index.count)-\(states.first?.preferredTranslationRaw ?? "")") {
            guard !store.index.isEmpty, let state = states.first else { return }
            await VerseWidgetUpdater.refresh(store: store, translation: state.preferredTranslation)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard newPhase == .active else { return }
            Task { await ReadingSessionController.shared.reconcile() }
            if let state = states.first {
                Task { await VerseWidgetUpdater.refresh(store: store, translation: state.preferredTranslation) }
            }
            let isColdStart = !didCompleteFirstActivation
            didCompleteFirstActivation = true
            guard isColdStart || oldPhase == .background else { return }
            ads.showAppOpenAdIfEligible()
        }
    }
}

#Preview {
    ContentView(ads: AdsCoordinator())
        .modelContainer(for: UserState.self, inMemory: true)
}
