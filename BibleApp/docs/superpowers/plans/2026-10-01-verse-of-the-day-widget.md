# Verse of the Day Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Home Screen + Lock Screen widget showing one Bible verse per day; tapping opens that verse in the Feed.

**Architecture:** The app picks the day's verse with a pure function in `BibleFeedKit`, writes a snapshot to App Group `UserDefaults`, and reloads widget timelines. The widget only reads the snapshot (hardcoded fallback if none). `bibleapp://verse/<id>` deep-links into the Feed, which pins that verse first.

**Tech Stack:** SwiftUI, WidgetKit, SwiftPM (`BibleFeedKit`, Swift Testing/XCTest as already used in the package), App Groups.

## Global Constraints

- Families: `systemSmall`, `systemMedium`, `accessoryRectangular`, `accessoryInline`.
- App Group id: `group.com.trailbyte.bible.widget`. URL scheme: `bibleapp` (already registered).
- `Shared/` and `BibleAppWidgets/` and `BibleApp/` are file-system-synchronized Xcode groups: new files there join their targets automatically. `Shared/` is in BOTH app and widget targets; the widget does NOT link `BibleFeedKit`, so Shared code must be Foundation-only.
- Project default actor isolation is `MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION`); mark Shared pure types/functions `nonisolated` if the compiler complains.
- Never overwrite a good snapshot with empty data.
- Use `/usr/bin/git` for git commands. Build: `xcodebuild -project BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
- Deviation from spec: the snapshot struct lives in `Shared/` (Foundation-only, no test target covers it), so its encode/decode is verified manually in Task 3 instead of by a unit test. The date→verse picker is unit-tested in the package.

---

### Task 1: Daily verse picker (BibleFeedKit)

**Files:**
- Create: `../packages/BibleFeedKit/Sources/BibleFeedKit/VerseOfTheDay.swift` (path relative to repo root `BibleApp/`: `packages/BibleFeedKit/...` one level above the Xcode project dir)
- Test: `../packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseOfTheDayTests.swift`

**Interfaces:**
- Produces: `VerseOfTheDay.entry(in verses: [VerseIndexEntry], on date: Date, calendar: Calendar = .current) -> VerseIndexEntry?`. Only tier-1 verses are eligible; falls back to all verses if none are tier 1. Stable within a calendar day, different across days, wraps, returns nil for an empty list.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import BibleFeedKit

@Suite struct VerseOfTheDayTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func verses(_ count: Int, tier: Int = 1) -> [VerseIndexEntry] {
        (0..<count).map {
            VerseIndexEntry(id: "V.\($0)", reference: "Ref \($0)", book: "V", chapter: 1,
                            verse: $0, topics: [], tier: tier, shard: 0)
        }
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: 15))!
    }

    @Test func emptyListReturnsNil() {
        #expect(VerseOfTheDay.entry(in: [], on: date(1), calendar: calendar) == nil)
    }

    @Test func sameDayIsStableAcrossTimes() {
        let list = verses(50)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 1))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 23))!
        #expect(VerseOfTheDay.entry(in: list, on: morning, calendar: calendar)
                == VerseOfTheDay.entry(in: list, on: night, calendar: calendar))
    }

    @Test func consecutiveDaysDiffer() {
        let list = verses(50)
        let picks = (1...10).compactMap { VerseOfTheDay.entry(in: list, on: date($0), calendar: calendar)?.id }
        #expect(Set(picks).count == 10)
    }

    @Test func wrapsAroundSmallLists() {
        let list = verses(3)
        let picks = (1...9).compactMap { VerseOfTheDay.entry(in: list, on: date($0), calendar: calendar)?.id }
        #expect(picks.count == 9)
        #expect(Set(picks).count == 3)
    }

    @Test func prefersTierOneButFallsBack() {
        let mixed = verses(5, tier: 1) + (5..<20).map {
            VerseIndexEntry(id: "V.\($0)", reference: "Ref", book: "V", chapter: 1,
                            verse: $0, topics: [], tier: 2, shard: 0)
        }
        for day in 1...20 {
            #expect(VerseOfTheDay.entry(in: mixed, on: date(day), calendar: calendar)?.tier == 1)
        }
        #expect(VerseOfTheDay.entry(in: verses(4, tier: 3), on: date(1), calendar: calendar) != nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ../packages/BibleFeedKit && swift test --filter VerseOfTheDayTests`
Expected: FAIL (`cannot find 'VerseOfTheDay' in scope`).

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Picks the verse shown by the widget for a given day. Deterministic: the
/// same calendar day always yields the same verse, and consecutive days walk
/// the eligible list with a stride coprime to its length so the order does
/// not follow the canon.
public enum VerseOfTheDay {
    public static func entry(in verses: [VerseIndexEntry],
                             on date: Date,
                             calendar: Calendar = .current) -> VerseIndexEntry? {
        let tierOne = verses.filter { $0.tier == 1 }
        let pool = tierOne.isEmpty ? verses : tierOne
        guard !pool.isEmpty else { return nil }

        let epoch = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let today = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: epoch, to: today).day ?? 0

        let count = pool.count
        var stride = 7919
        while gcd(stride, count) != 1 { stride += 1 }
        let index = (((days % count) * (stride % count)) % count + count) % count
        return pool[index]
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd ../packages/BibleFeedKit && swift test --filter VerseOfTheDayTests`
Expected: PASS (5 tests). If `consecutiveDaysDiffer` fails because the pool size shares structure with the stride, adjust the stride search only; do not weaken the test.

- [ ] **Step 5: Commit**

```bash
/usr/bin/git add ../packages/BibleFeedKit
/usr/bin/git commit -m "Add VerseOfTheDay picker to BibleFeedKit

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: App Group entitlements

**Files:**
- Create: `Config/BibleApp.entitlements`, `Config/BibleAppWidgets.entitlements` (outside the synced folders on purpose, so they are not bundled as resources)
- Modify: `BibleApp.xcodeproj/project.pbxproj` (add `CODE_SIGN_ENTITLEMENTS` to the 4 build configs)

**Interfaces:**
- Produces: both targets can open `UserDefaults(suiteName: "group.com.trailbyte.bible.widget")`.

- [ ] **Step 1: Create both entitlements files** (identical content)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.trailbyte.bible.widget</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Wire into pbxproj.** In `project.pbxproj`, in the two build configs whose `PRODUCT_BUNDLE_IDENTIFIER = com.trailbyte.bible.widget;` add the line `CODE_SIGN_ENTITLEMENTS = Config/BibleApp.entitlements;`; in the two with `PRODUCT_BUNDLE_IDENTIFIER = com.trailbyte.bible.widget.BibleAppWidgets;` add `CODE_SIGN_ENTITLEMENTS = Config/BibleAppWidgets.entitlements;` (place it next to `CODE_SIGN_STYLE`/`DEVELOPMENT_TEAM`). Use `Edit` with enough surrounding context to be unique per config.

- [ ] **Step 3: Build**

Run the build command from Global Constraints.
Expected: BUILD SUCCEEDED (simulator builds do not require the group to exist on the developer account).

- [ ] **Step 4: Commit**

```bash
/usr/bin/git add Config BibleApp.xcodeproj/project.pbxproj
/usr/bin/git commit -m "Add App Group entitlements for the widget

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Shared snapshot and store

**Files:**
- Create: `Shared/VerseWidgetSnapshot.swift`

**Interfaces:**
- Produces:
  - `struct VerseWidgetSnapshot: Codable, Equatable { let id: String; let reference: String; let text: String; let day: Date }`
  - `VerseWidgetSnapshot.fallback` (Genesis 1:1 KJV text, id `GEN.1.1`)
  - `enum VerseWidgetStore { static let groupID: String; static func load() -> VerseWidgetSnapshot?; static func save(_ s: VerseWidgetSnapshot) }`
  - `VerseWidgetSnapshot.url: URL` → `bibleapp://verse/<id>`

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// What the verse-of-the-day widget shows. Written by the app, read by the
/// widget extension through the shared App Group.
struct VerseWidgetSnapshot: Codable, Equatable {
    let id: String
    let reference: String
    let text: String
    let day: Date

    static let fallback = VerseWidgetSnapshot(
        id: "GEN.1.1",
        reference: "Genesis 1:1",
        text: "In the beginning God created the heaven and the earth.",
        day: .distantPast)

    var url: URL { URL(string: "bibleapp://verse/\(id)")! }
}

enum VerseWidgetStore {
    static let groupID = "group.com.trailbyte.bible.widget"
    private static let key = "verseOfTheDaySnapshot"

    static func load() -> VerseWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(VerseWidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: VerseWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: groupID)?.set(data, forKey: key)
    }
}
```

- [ ] **Step 2: Build** (command from Global Constraints). Expected: BUILD SUCCEEDED. Fix any actor-isolation diagnostics with `nonisolated`.

- [ ] **Step 3: Commit**

```bash
/usr/bin/git add Shared/VerseWidgetSnapshot.swift
/usr/bin/git commit -m "Add the shared verse widget snapshot and store

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: App writes the snapshot

**Files:**
- Create: `BibleApp/Content/VerseWidgetUpdater.swift`
- Modify: `BibleApp/ContentView.swift` (add a `.task(id:)` and a call in the `scenePhase` handler)

**Interfaces:**
- Consumes: `VerseOfTheDay.entry(in:on:)`, `ContentStore.content(for:)`, `VerseWidgetStore.save`.
- Produces: `VerseWidgetUpdater.refresh(store: ContentStore, translation: Translation) async`.

- [ ] **Step 1: Write the updater**

```swift
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
```

- [ ] **Step 2: Call it from `ContentView`.** After the existing `.task { await ReadingSessionController... }` modifier add:

```swift
        .task(id: "\(store.index.count)-\(states.first?.preferredTranslationRaw ?? "")") {
            guard !store.index.isEmpty, let state = states.first else { return }
            await VerseWidgetUpdater.refresh(store: store, translation: state.preferredTranslation)
        }
```

and inside `.onChange(of: scenePhase)` after `Task { await ReadingSessionController.shared.reconcile() }` add:

```swift
            if let state = states.first {
                Task { await VerseWidgetUpdater.refresh(store: store, translation: state.preferredTranslation) }
            }
```

- [ ] **Step 3: Build.** Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
/usr/bin/git add BibleApp/Content/VerseWidgetUpdater.swift BibleApp/ContentView.swift
/usr/bin/git commit -m "Write the verse of the day snapshot for the widget

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The widget

**Files:**
- Create: `BibleAppWidgets/VerseOfTheDayWidget.swift`
- Modify: `BibleAppWidgets/BibleAppWidgetsBundle.swift`

**Interfaces:**
- Consumes: `VerseWidgetStore.load()`, `VerseWidgetSnapshot.fallback`, `.url`.
- Produces: `VerseOfTheDayWidget: Widget` (kind `"VerseOfTheDay"`).

- [ ] **Step 1: Write the widget**

```swift
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
                                                 matchingPolicy: .nextTime) ?? .now.addingTimeInterval(6 * 3600)
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
```

- [ ] **Step 2: Register in the bundle**

```swift
    var body: some Widget {
        VerseOfTheDayWidget()
        ReadingSessionLiveActivity()
        ListeningLiveActivity()
    }
```

- [ ] **Step 3: Build.** Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
/usr/bin/git add BibleAppWidgets
/usr/bin/git commit -m "Add the verse of the day widget

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Deep link into the Feed

**Files:**
- Modify: `BibleApp/ContentView.swift` (state + `onOpenURL` branch + pass to `FeedView`)
- Modify: `BibleApp/Views/FeedView.swift` (new `pinnedID` input, put it first in the queue)

**Interfaces:**
- Consumes: URL `bibleapp://verse/<id>`.
- Produces: `FeedView(store:state:pinnedID:)` where `pinnedID: String?`.

- [ ] **Step 1: FeedView.** Add `let pinnedID: String?` after `let state: UserState`. In `rebuild()` replace `queue = result.verses` with:

```swift
        var verses = result.verses
        if let pinnedID, let pinned = store.entry(for: pinnedID) {
            verses.removeAll { $0.id == pinned.id }
            verses.insert(pinned, at: 0)
        }
        queue = verses
```

and set `visibleID = queue.first?.id` at the end of `rebuild()` when `pinnedID` is non-nil and `!isReplay`. Add on the `ScrollView` chain: `.onChange(of: pinnedID) { _, _ in rebuild() }`.

- [ ] **Step 2: ContentView.** Add `@State private var pinnedVerseID: String?`; construct `FeedView(store: store, state: state, pinnedID: pinnedVerseID)`; in `onOpenURL` add the case:

```swift
                        case "verse":
                            let id = url.lastPathComponent
                            if !id.isEmpty, id != "/" {
                                pinnedVerseID = id
                                selectedTab = .feed
                            }
```

- [ ] **Step 3: Build.** Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Verify in Simulator.** Build and launch on the booted simulator, then run `xcrun simctl openurl booted "bibleapp://verse/JHN.3.16"` (use any id present in `feed_index.json`). Expected: Feed opens on that verse first.

- [ ] **Step 5: Commit**

```bash
/usr/bin/git add BibleApp/ContentView.swift BibleApp/Views/FeedView.swift
/usr/bin/git commit -m "Open the Feed on a verse from the widget deep link

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Visual verification

- [ ] **Step 1:** Launch the app once in the Simulator (writes the snapshot). Add the widget (small, medium) to the Home Screen and the Lock Screen widgets in the Simulator; screenshot each family.
- [ ] **Step 2:** Tap the widget; confirm the Feed opens on the same verse.
- [ ] **Step 3:** Check that with the App Group missing on a real device the widget still shows the fallback verse (no crash).
- [ ] **Step 4:** Report the DEVELOPMENT_TEAM mismatch (`875TKZ94AW` app vs `A6U459NUFN` widget) to the user: device builds need both targets on one team with the App Group registered.
