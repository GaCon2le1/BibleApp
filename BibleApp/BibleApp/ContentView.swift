import SwiftUI
import SwiftData

private enum RootTab: Hashable {
    case feed
    case saved
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var states: [UserState]
    @State private var store = ContentStore()
    @State private var selectedTab: RootTab = .feed
    @State private var didCompleteFirstActivation = false
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
                        FeedView(store: store, state: state)
                            .tabItem { Label("Feed", systemImage: "book") }
                            .tag(RootTab.feed)
                        LibraryView(store: store, state: state)
                            .tabItem { Label("Saved", systemImage: "bookmark") }
                            .tag(RootTab.saved)
                    }
                    .onChange(of: selectedTab) { _, _ in
                        ads.tabDidChange()
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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard newPhase == .active else { return }
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
