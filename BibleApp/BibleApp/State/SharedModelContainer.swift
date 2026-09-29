import SwiftData

/// One store shared by the UI and by Lock Screen intents, which can run
/// with no scene attached. Uses the same default location as the previous
/// `.modelContainer(for: UserState.self)`, so existing data carries over.
enum SharedModelContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: UserState.self)
        } catch {
            fatalError("Could not create the model container: \(error)")
        }
    }()
}
