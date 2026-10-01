import SwiftUI
import WidgetKit

@main
struct BibleAppWidgetsBundle: WidgetBundle {
    var body: some Widget {
        VerseOfTheDayWidget()
        ReadingSessionLiveActivity()
        ListeningLiveActivity()
    }
}
