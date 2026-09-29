import ActivityKit
import AppIntents

// Live Activity intents always run in the app process. The widget extension
// compiles these only so its buttons can reference them.

nonisolated struct NextVerseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next Verse"

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await ReadingSessionController.shared.next()
        #endif
        return .result()
    }
}

nonisolated struct SaveVerseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Save Verse"

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await ReadingSessionController.shared.toggleSaved()
        #endif
        return .result()
    }
}

nonisolated struct EndSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Reflection Session"

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await ReadingSessionController.shared.end()
        #endif
        return .result()
    }
}
