import SwiftUI
import SwiftData

@main
struct BibleAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: UserState.self)
    }
}
