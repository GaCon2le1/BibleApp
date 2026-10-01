import AppIntents
import WidgetKit

/// Tapped from the widget's bookmark button. Runs in the widget extension, so
/// it only records the request; the app applies it to `UserState` later.
nonisolated struct ToggleVerseSavedIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Verse"
    static let isDiscoverable = false

    @Parameter(title: "Verse ID") var verseID: String
    @Parameter(title: "Saved") var saved: Bool

    init() {}

    init(verseID: String, saved: Bool) {
        self.verseID = verseID
        self.saved = saved
    }

    func perform() async throws -> some IntentResult {
        VerseWidgetStore.setSavedOverride(verseID, saved: saved)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
