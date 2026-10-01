import SwiftUI
import WidgetKit

struct VerseEntry: TimelineEntry {
    let date: Date
    let snapshot: VerseWidgetSnapshot
}

struct VerseProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerseEntry {
        VerseEntry(date: .now, snapshot: .fallback)
    }

    func getSnapshot(in context: Context, completion: @escaping (VerseEntry) -> Void) {
        completion(VerseEntry(date: .now, snapshot: VerseWidgetStore.load() ?? .fallback))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VerseEntry>) -> Void) {
        let entry = VerseEntry(date: .now, snapshot: VerseWidgetStore.load() ?? .fallback)
        let midnight = Calendar.current.nextDate(after: .now,
                                                 matching: DateComponents(hour: 0, minute: 5),
                                                 matchingPolicy: .nextTime)
            ?? .now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

struct VerseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VerseEntry

    var body: some View {
        content
            .widgetURL(entry.snapshot.url)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder private var content: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryInline:
            Text("\(s.reference) · \(s.text)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(s.reference).font(.caption.weight(.semibold))
                Text(s.text).font(.caption2).lineLimit(3)
            }
        case .systemMedium:
            VStack(alignment: .leading, spacing: 8) {
                Text(s.text)
                    .font(.system(.body, design: .serif))
                    .lineLimit(5)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(s.reference).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text(s.text)
                    .font(.system(.footnote, design: .serif))
                    .lineLimit(6)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(s.reference).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct VerseOfTheDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VerseOfTheDay", provider: VerseProvider()) { entry in
            VerseWidgetView(entry: entry)
        }
        .configurationDisplayName("Verse of the Day")
        .description("A new Bible verse every day.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
