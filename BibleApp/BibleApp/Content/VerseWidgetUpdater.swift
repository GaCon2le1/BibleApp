import Foundation
import WidgetKit
import BibleFeedKit

enum VerseWidgetUpdater {
    /// Writes today's verse for the widget and reloads its timelines. Leaves
    /// the previous snapshot untouched if the verse text cannot be loaded.
    static func refresh(store: ContentStore, translation: Translation) async {
        guard let entry = VerseOfTheDay.entry(in: store.index, on: .now) else { return }
        let content = await store.content(for: [entry.id])[entry.id]
        guard let text = content?.translations[translation]?.displayText
                ?? content?.translations[.kjv]?.displayText,
              !text.isEmpty else { return }
        VerseWidgetStore.save(VerseWidgetSnapshot(id: entry.id,
                                                  reference: entry.reference,
                                                  text: text,
                                                  day: Calendar.current.startOfDay(for: .now)))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
