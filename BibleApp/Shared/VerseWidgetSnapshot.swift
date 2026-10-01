import Foundation

/// What the verse-of-the-day widget shows. Written by the app, read by the
/// widget extension through the shared App Group.
struct VerseWidgetSnapshot: Codable, Equatable {
    let id: String
    let reference: String
    let text: String
    let day: Date
    let isSaved: Bool

    static let fallback = VerseWidgetSnapshot(
        id: "GEN.1.1",
        reference: "Genesis 1:1",
        text: "In the beginning God created the heaven and the earth.",
        day: .distantPast,
        isSaved: false)

    var url: URL { URL(string: "bibleapp://verse/\(id)")! }
}

enum VerseWidgetStore {
    static let groupID = "group.com.trailbyte.bible.widget"
    private static let key = "verseOfTheDaySnapshot"

    static func load() -> VerseWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(VerseWidgetSnapshot.self, from: data)
    }

    /// Save/unsave requests made from the widget. The extension cannot write
    /// the app's SwiftData store, so the app applies these when it next runs.
    private static let overridesKey = "verseWidgetSavedOverrides"

    static func savedOverrides() -> [String: Bool] {
        UserDefaults(suiteName: groupID)?.dictionary(forKey: overridesKey) as? [String: Bool] ?? [:]
    }

    static func setSavedOverride(_ id: String, saved: Bool) {
        var all = savedOverrides()
        all[id] = saved
        UserDefaults(suiteName: groupID)?.set(all, forKey: overridesKey)
    }

    static func clearSavedOverrides() {
        UserDefaults(suiteName: groupID)?.removeObject(forKey: overridesKey)
    }

    static func save(_ snapshot: VerseWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: groupID)?.set(data, forKey: key)
    }
}
