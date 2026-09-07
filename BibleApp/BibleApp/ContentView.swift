import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var states: [UserState]
    @State private var store = ContentStore()

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
                    FeedView(store: store, state: state)
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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: UserState.self, inMemory: true)
}
