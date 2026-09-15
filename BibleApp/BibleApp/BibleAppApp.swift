import SwiftUI
import SwiftData

@main
struct BibleAppApp: App {
    @State private var ads = AdsCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(ads: ads)
                .task {
                    ads.start()
                    await ads.requestTrackingAuthorizationIfNeeded()
                }
        }
        .modelContainer(for: UserState.self)
    }
}
