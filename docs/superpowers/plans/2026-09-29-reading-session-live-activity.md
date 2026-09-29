# Reading Session Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A timed reflection session (5/10/15 min) shown as a Live Activity on the Lock Screen and Dynamic Island, with the current Feed verse, a countdown, and Next / Save / End buttons.

**Architecture:** Pure session logic (`SessionQueue`, `PersistedSession`, `VerseSnippet`) lives in `BibleFeedKit` and is unit tested. A new `BibleAppWidgets` Widget Extension renders the Live Activity. Types needed by both targets (`ReadingSessionAttributes`, the three `LiveActivityIntent`s) live in a new `Shared/` folder compiled into both. Intents run in the app process and call `ReadingSessionController`, which drives ActivityKit, reads content through `ContentStore`, and mutates `UserState` through a shared `ModelContainer`.

**Tech Stack:** Swift 5 mode, SwiftUI, SwiftData, ActivityKit, WidgetKit, App Intents, Swift Testing (package tests), Xcode 26.4 synchronized folders.

**Spec:** `docs/superpowers/specs/2026-09-29-reading-session-live-activity-design.md`

## Global Constraints

- iOS deployment target stays **26.4** for the app and the new extension.
- All user-facing strings are **English**, matching the rest of the app.
- No server, no push (`pushType: nil`), no App Group. Intent `perform()` runs in the app process.
- At most **one** session at a time; starting a new one ends the old one first (with `.immediate` dismissal).
- Durations: **5, 10, 15** minutes. Up to **200** verse ids captured at start.
- Lock Screen verse text truncated to **220** characters (ellipsis included).
- Verse text uses `UserState.preferredTranslation`, falling back to `.kjv`.
- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; the extension does not. Every type in `Shared/` is declared `nonisolated struct`.
- Code in `Shared/` that must only run in the app is wrapped in `#if !WIDGET_EXTENSION`.
- Package tests use Swift Testing (`import Testing`, `@Test`, `#expect`) like the existing tests.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

All paths below are relative to the repo root `/Users/vietdo/Documents/GitHub/BibleApp`.

Build command used throughout (run from repo root):

```bash
xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'generic/platform=iOS Simulator' -quiet build
```

Expected on success: no `error:` lines and exit status 0.

---

## File Structure

| File | Target | Responsibility |
|---|---|---|
| `packages/BibleFeedKit/Sources/BibleFeedKit/VerseSnippet.swift` | package | Truncate verse text for the Lock Screen |
| `packages/BibleFeedKit/Sources/BibleFeedKit/SessionQueue.swift` | package | Session verse list, position, expiry |
| `packages/BibleFeedKit/Sources/BibleFeedKit/PersistedSession.swift` | package | Activity id + queue, saved as JSON |
| `BibleApp/Shared/ReadingSessionAttributes.swift` | app + ext | ActivityKit attributes and content state |
| `BibleApp/Shared/ReadingSessionIntents.swift` | app + ext | Next / Save / End `LiveActivityIntent`s |
| `BibleApp/BibleAppWidgets/BibleAppWidgetsBundle.swift` | ext | `@main` widget bundle |
| `BibleApp/BibleAppWidgets/ReadingSessionLiveActivity.swift` | ext | Lock Screen + Dynamic Island UI, previews |
| `BibleApp/BibleAppWidgets/Info.plist` | ext | `NSExtension` point identifier |
| `BibleApp/BibleApp/State/SharedModelContainer.swift` | app | Single `ModelContainer` for UI and intents |
| `BibleApp/BibleApp/LiveActivity/ReadingSessionController.swift` | app | Start / next / save / end / reconcile |
| `BibleApp/BibleApp/Views/ReflectionButton.swift` | app | ⏱ button, duration picker, active pill, alert |
| `BibleApp/BibleApp.xcodeproj/project.pbxproj` | — | New target, `Shared` group, embed phase |
| `BibleApp/BibleApp/Info.plist` | app | `NSSupportsLiveActivities` |
| `BibleApp/BibleApp/Content/ContentStore.swift` | app | Add `entry(for:)` |
| `BibleApp/BibleApp/BibleAppApp.swift` | app | Use `SharedModelContainer.shared` |
| `BibleApp/BibleApp/ContentView.swift` | app | Call `reconcile()` |
| `BibleApp/BibleApp/Views/FeedView.swift` | app | Track visible verse, host `ReflectionButton` |

---

### Task 1: `VerseSnippet.truncate`

**Files:**
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/VerseSnippet.swift`
- Test: `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseSnippetTests.swift`

**Interfaces:**
- Produces: `public enum VerseSnippet { public static func truncate(_ text: String, limit: Int = 220) -> String }` — returns `text` unchanged when `text.count <= limit`; otherwise at most `limit` `Character`s ending in `"…"`, cut at the last whitespace inside the first `limit - 1` characters (or hard-cut when there is none).

- [ ] **Step 1: Write the failing tests**

Create `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseSnippetTests.swift`:

```swift
import Testing
@testable import BibleFeedKit

@Test func shortTextIsUnchanged() {
    #expect(VerseSnippet.truncate("Jesus wept.", limit: 220) == "Jesus wept.")
}

@Test func textExactlyAtLimitIsUnchanged() {
    let text = String(repeating: "a", count: 10)
    #expect(VerseSnippet.truncate(text, limit: 10) == text)
}

@Test func longTextIsCutAtAWordBoundary() {
    #expect(VerseSnippet.truncate("the quick brown fox", limit: 12) == "the quick…")
}

@Test func resultNeverExceedsTheLimit() {
    let text = String(repeating: "word ", count: 100)
    let result = VerseSnippet.truncate(text, limit: 220)
    #expect(result.count <= 220)
    #expect(result.hasSuffix("…"))
}

@Test func textWithoutSpacesIsHardCut() {
    #expect(VerseSnippet.truncate("abcdefghij", limit: 5) == "abcd…")
}

@Test func graphemeClustersAreNeverSplit() {
    let family = "👨‍👩‍👧‍👦"
    let text = String(repeating: family, count: 10)
    #expect(VerseSnippet.truncate(text, limit: 5) == String(repeating: family, count: 4) + "…")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/BibleFeedKit && swift test --filter VerseSnippetTests`
Expected: build failure, `cannot find 'VerseSnippet' in scope`.

- [ ] **Step 3: Implement**

Create `packages/BibleFeedKit/Sources/BibleFeedKit/VerseSnippet.swift`:

```swift
import Foundation

/// Shortens verse text to fit the Lock Screen, whose Live Activity payload is
/// capped at about 4 KB. Works on `Character`s so an emoji or combined glyph
/// is never split in half.
public enum VerseSnippet {
    public static func truncate(_ text: String, limit: Int = 220) -> String {
        guard text.count > limit else { return text }
        // Leave room for the ellipsis so the result stays within `limit`.
        let head = text.prefix(limit - 1)
        let cut = head.lastIndex(where: \.isWhitespace).map { head[..<$0] } ?? head
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/BibleFeedKit && swift test --filter VerseSnippetTests`
Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add packages/BibleFeedKit/Sources/BibleFeedKit/VerseSnippet.swift packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseSnippetTests.swift
git commit -m "Add VerseSnippet for Lock Screen verse text

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `SessionQueue` and `PersistedSession`

**Files:**
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/SessionQueue.swift`
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/PersistedSession.swift`
- Test: `packages/BibleFeedKit/Tests/BibleFeedKitTests/SessionQueueTests.swift`
- Test: `packages/BibleFeedKit/Tests/BibleFeedKitTests/PersistedSessionTests.swift`

**Interfaces:**
- Produces:
  - `public struct SessionQueue: Codable, Equatable, Sendable`
    - `public init?(ids: [String], endDate: Date)` — `nil` when `ids` is empty
    - `public let ids: [String]`, `public let endDate: Date`, `public private(set) var position: Int`
    - `public var current: String` — `ids[position]`
    - `public var versesRead: Int` — `position + 1`
    - `public mutating func advance() -> Bool` — moves to the next id; returns `false` and leaves `position` unchanged at the last id
    - `public func isExpired(now: Date) -> Bool` — `now >= endDate`
  - `public struct PersistedSession: Codable, Equatable, Sendable`
    - `public init(activityID: String, queue: SessionQueue)`
    - `public let activityID: String`, `public var queue: SessionQueue`
    - `public static func load(from url: URL) -> PersistedSession?` — `nil` if missing or undecodable
    - `public func save(to url: URL) throws` — creates parent directories, writes atomically
    - `public static func delete(at url: URL)` — no-op if missing

- [ ] **Step 1: Write the failing `SessionQueue` tests**

Create `packages/BibleFeedKit/Tests/BibleFeedKitTests/SessionQueueTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleFeedKit

private let endDate = Date(timeIntervalSince1970: 1_000)

@Test func emptyQueueIsRejected() {
    #expect(SessionQueue(ids: [], endDate: endDate) == nil)
}

@Test func startsAtTheFirstVerse() {
    let queue = SessionQueue(ids: ["A", "B"], endDate: endDate)!
    #expect(queue.current == "A")
    #expect(queue.versesRead == 1)
}

@Test func advanceMovesToTheNextVerse() {
    var queue = SessionQueue(ids: ["A", "B", "C"], endDate: endDate)!
    #expect(queue.advance())
    #expect(queue.current == "B")
    #expect(queue.versesRead == 2)
}

@Test func advanceAtTheLastVerseReturnsFalseAndStays() {
    var queue = SessionQueue(ids: ["A", "B"], endDate: endDate)!
    #expect(queue.advance())
    #expect(!queue.advance())
    #expect(queue.current == "B")
    #expect(queue.versesRead == 2)
}

@Test func notExpiredBeforeEndDate() {
    let queue = SessionQueue(ids: ["A"], endDate: endDate)!
    #expect(!queue.isExpired(now: endDate.addingTimeInterval(-1)))
}

@Test func expiredExactlyAtEndDate() {
    let queue = SessionQueue(ids: ["A"], endDate: endDate)!
    #expect(queue.isExpired(now: endDate))
}

@Test func queueRoundTripsThroughCodable() throws {
    var queue = SessionQueue(ids: ["A", "B"], endDate: endDate)!
    _ = queue.advance()
    let data = try JSONEncoder().encode(queue)
    #expect(try JSONDecoder().decode(SessionQueue.self, from: data) == queue)
}
```

- [ ] **Step 2: Write the failing `PersistedSession` tests**

Create `packages/BibleFeedKit/Tests/BibleFeedKitTests/PersistedSessionTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleFeedKit

private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "PersistedSessionTests-\(UUID().uuidString)")
        .appending(path: "session.json")
}

private func sampleSession() -> PersistedSession {
    PersistedSession(activityID: "activity-1",
                     queue: SessionQueue(ids: ["A", "B"],
                                         endDate: Date(timeIntervalSince1970: 1_000))!)
}

@Test func savedSessionLoadsBack() throws {
    let url = temporaryURL()
    let session = sampleSession()
    try session.save(to: url)
    #expect(PersistedSession.load(from: url) == session)
}

@Test func missingFileLoadsNil() {
    #expect(PersistedSession.load(from: temporaryURL()) == nil)
}

@Test func corruptFileLoadsNil() throws {
    let url = temporaryURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    #expect(PersistedSession.load(from: url) == nil)
}

@Test func deleteRemovesTheFile() throws {
    let url = temporaryURL()
    try sampleSession().save(to: url)
    PersistedSession.delete(at: url)
    #expect(PersistedSession.load(from: url) == nil)
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/BibleFeedKit && swift test --filter "SessionQueueTests|PersistedSessionTests"`
Expected: build failure, `cannot find 'SessionQueue' in scope`.

- [ ] **Step 4: Implement `SessionQueue`**

Create `packages/BibleFeedKit/Sources/BibleFeedKit/SessionQueue.swift`:

```swift
import Foundation

/// The verses of one timed reflection session and how far the reader has
/// got. Captured from the Feed queue when the session starts.
public struct SessionQueue: Codable, Equatable, Sendable {
    public let ids: [String]
    public let endDate: Date
    public private(set) var position: Int

    public init?(ids: [String], endDate: Date) {
        guard !ids.isEmpty else { return nil }
        self.ids = ids
        self.endDate = endDate
        self.position = 0
    }

    public var current: String { ids[position] }

    /// Verses reached so far, counting the one on screen.
    public var versesRead: Int { position + 1 }

    /// Moves to the next verse. Returns false, leaving the position alone,
    /// when the current verse is the last one.
    public mutating func advance() -> Bool {
        guard position + 1 < ids.count else { return false }
        position += 1
        return true
    }

    public func isExpired(now: Date) -> Bool {
        now >= endDate
    }
}
```

- [ ] **Step 5: Implement `PersistedSession`**

Create `packages/BibleFeedKit/Sources/BibleFeedKit/PersistedSession.swift`:

```swift
import Foundation

/// The running session as written to disk, so a Lock Screen button can pick
/// it up again after the app has been terminated.
public struct PersistedSession: Codable, Equatable, Sendable {
    public let activityID: String
    public var queue: SessionQueue

    public init(activityID: String, queue: SessionQueue) {
        self.activityID = activityID
        self.queue = queue
    }

    public static func load(from url: URL) -> PersistedSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedSession.self, from: data)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 6: Run the whole package suite**

Run: `cd packages/BibleFeedKit && swift test`
Expected: all tests pass, including the 7 `SessionQueue` and 4 `PersistedSession` tests.

- [ ] **Step 7: Commit**

```bash
git add packages/BibleFeedKit/Sources/BibleFeedKit/SessionQueue.swift packages/BibleFeedKit/Sources/BibleFeedKit/PersistedSession.swift packages/BibleFeedKit/Tests/BibleFeedKitTests/SessionQueueTests.swift packages/BibleFeedKit/Tests/BibleFeedKitTests/PersistedSessionTests.swift
git commit -m "Add SessionQueue and PersistedSession for reading sessions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Widget extension target with the Live Activity UI (no buttons yet)

**Files:**
- Create: `BibleApp/Shared/ReadingSessionAttributes.swift`
- Create: `BibleApp/BibleAppWidgets/Info.plist`
- Create: `BibleApp/BibleAppWidgets/BibleAppWidgetsBundle.swift`
- Create: `BibleApp/BibleAppWidgets/ReadingSessionLiveActivity.swift`
- Modify: `BibleApp/BibleApp.xcodeproj/project.pbxproj` (via script)
- Modify: `BibleApp/BibleApp/Info.plist`

**Interfaces:**
- Produces:
  - `nonisolated struct ReadingSessionAttributes: ActivityAttributes` with `var endDate: Date` and
    `nonisolated struct ContentState: Codable, Hashable { var verseID: String; var reference: String; var text: String; var versesRead: Int; var isSaved: Bool; var isComplete: Bool }`
  - Target `BibleAppWidgets` (bundle id `com.trailbyte.bible.widget.BibleAppWidgets`), compilation condition `WIDGET_EXTENSION`, embedded in the app.
  - Synchronized folder `BibleApp/Shared/` compiled into **both** targets.
  - `ReadingSessionLiveActivity.swift` contains a `private struct SessionControls: View { let isSaved: Bool }` placeholder that renders `EmptyView()`; Task 5 fills it in.

- [ ] **Step 1: Create the shared attributes**

Create `BibleApp/Shared/ReadingSessionAttributes.swift`:

```swift
import ActivityKit
import Foundation

/// Live Activity data for a timed reflection session. Compiled into both the
/// app and the widget extension.
nonisolated struct ReadingSessionAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var verseID: String
        var reference: String
        /// Already shortened with `VerseSnippet.truncate`.
        var text: String
        var versesRead: Int
        var isSaved: Bool
        /// Set when the session was ended by the app; expiry is detected
        /// through `staleDate` instead.
        var isComplete: Bool
    }

    var endDate: Date
}
```

- [ ] **Step 2: Create the extension's Info.plist**

Create `BibleApp/BibleAppWidgets/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
</dict>
</plist>
```

- [ ] **Step 3: Create the widget bundle**

Create `BibleApp/BibleAppWidgets/BibleAppWidgetsBundle.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct BibleAppWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ReadingSessionLiveActivity()
    }
}
```

- [ ] **Step 4: Create the Live Activity UI**

Create `BibleApp/BibleAppWidgets/ReadingSessionLiveActivity.swift`:

```swift
import ActivityKit
import SwiftUI
import WidgetKit

struct ReadingSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingSessionAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            let isDone = context.isStale || context.state.isComplete
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.reference)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(endDate: context.attributes.endDate, isDone: isDone)
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.text)
                            .font(.system(.callout, design: .serif))
                            .lineLimit(2)
                        if !isDone {
                            SessionControls(isSaved: context.state.isSaved)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "book.fill")
            } compactTrailing: {
                Countdown(endDate: context.attributes.endDate, isDone: isDone)
                    .frame(maxWidth: 44)
            } minimal: {
                Countdown(endDate: context.attributes.endDate, isDone: isDone)
            }
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<ReadingSessionAttributes>

    var body: some View {
        let isDone = context.isStale || context.state.isComplete
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isDone {
                    Label("Session complete · \(versesLabel(context.state.versesRead))",
                          systemImage: "checkmark.circle.fill")
                } else {
                    Label("Reflection · \(versesLabel(context.state.versesRead))",
                          systemImage: "timer")
                    Spacer()
                    Countdown(endDate: context.attributes.endDate, isDone: false)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if !isDone {
                Text(context.state.text)
                    .font(.system(.body, design: .serif))
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }

            Text(context.state.reference)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isDone ? .tertiary : .secondary)

            if !isDone {
                SessionControls(isSaved: context.state.isSaved)
            }
        }
        .padding(16)
    }
}

/// Counts down to the session end without the app having to push updates.
private struct Countdown: View {
    let endDate: Date
    let isDone: Bool

    var body: some View {
        if isDone || endDate <= .now {
            Image(systemName: "checkmark")
        } else {
            Text(timerInterval: Date.now...endDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Filled in once the Lock Screen intents exist.
private struct SessionControls: View {
    let isSaved: Bool

    var body: some View {
        EmptyView()
    }
}

private func versesLabel(_ count: Int) -> String {
    count == 1 ? "1 verse" : "\(count) verses"
}

private extension ReadingSessionAttributes {
    static let preview = ReadingSessionAttributes(endDate: .now.addingTimeInterval(450))
}

private extension ReadingSessionAttributes.ContentState {
    static let short = Self(verseID: "PSA.46.10", reference: "Psalm 46:10",
                            text: "Be still, and know that I am God: I will be exalted among the heathen, I will be exalted in the earth.",
                            versesRead: 3, isSaved: false, isComplete: false)
    static let long = Self(verseID: "EPH.1.3", reference: "Ephesians 1:3",
                           text: "Blessed be the God and Father of our Lord Jesus Christ, who hath blessed us with all spiritual blessings in heavenly places in Christ: According as he hath chosen us in him before the foundation of the world, that we…",
                           versesRead: 1, isSaved: true, isComplete: false)
    static let complete = Self(verseID: "PSA.46.10", reference: "Psalm 46:10",
                               text: "Be still, and know that I am God.",
                               versesRead: 5, isSaved: false, isComplete: true)
}

#Preview("Lock Screen", as: .content, using: ReadingSessionAttributes.preview) {
    ReadingSessionLiveActivity()
} contentStates: {
    ReadingSessionAttributes.ContentState.short
    ReadingSessionAttributes.ContentState.long
    ReadingSessionAttributes.ContentState.complete
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: ReadingSessionAttributes.preview) {
    ReadingSessionLiveActivity()
} contentStates: {
    ReadingSessionAttributes.ContentState.short
    ReadingSessionAttributes.ContentState.long
}

#Preview("Compact", as: .dynamicIsland(.compact), using: ReadingSessionAttributes.preview) {
    ReadingSessionLiveActivity()
} contentStates: {
    ReadingSessionAttributes.ContentState.short
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: ReadingSessionAttributes.preview) {
    ReadingSessionLiveActivity()
} contentStates: {
    ReadingSessionAttributes.ContentState.short
}
```

- [ ] **Step 5: Enable Live Activities in the app's Info.plist**

In `BibleApp/BibleApp/Info.plist`, add these two lines directly after the `<false/>` that follows `GADIsAdManagerApp`:

```xml
	<key>NSSupportsLiveActivities</key>
	<true/>
```

- [ ] **Step 6: Add the target and `Shared` folder to the Xcode project**

Save this script as `$SCRATCH/add_widget_target.py` (any scratch path outside the repo) and run `python3 $SCRATCH/add_widget_target.py` from the repo root. Each replacement asserts its anchor exists exactly once, so a mismatch fails loudly instead of corrupting the project.

```python
from pathlib import Path

path = Path("BibleApp/BibleApp.xcodeproj/project.pbxproj")
text = path.read_text()

APP_TARGET = "A130C3CB304E714300DBEEFA"
PROJECT = "A130C3C4304E714300DBEEFA"
APPEX = "B2A100000000000000000001"
WIDGET_GROUP = "B2A100000000000000000002"
WIDGET_EXCEPTIONS = "B2A100000000000000000003"
WIDGET_TARGET = "B2A100000000000000000004"
WIDGET_SOURCES = "B2A100000000000000000005"
WIDGET_FRAMEWORKS = "B2A100000000000000000006"
WIDGET_RESOURCES = "B2A100000000000000000007"
WIDGET_CONFIG_LIST = "B2A100000000000000000008"
WIDGET_DEBUG = "B2A100000000000000000009"
WIDGET_RELEASE = "B2A10000000000000000000A"
EMBED_FILE = "B2A10000000000000000000B"
EMBED_PHASE = "B2A10000000000000000000C"
PROXY = "B2A10000000000000000000D"
DEPENDENCY = "B2A10000000000000000000E"
SHARED_GROUP = "B2A10000000000000000000F"


def replace_once(old, new):
    global text
    assert text.count(old) == 1, f"anchor not found exactly once: {old!r}"
    text = text.replace(old, new)


# Build file for embedding the extension.
replace_once(
    "/* End PBXBuildFile section */",
    f"\t\t{EMBED_FILE} /* BibleAppWidgets.appex in Embed Foundation Extensions */ = "
    f"{{isa = PBXBuildFile; fileRef = {APPEX} /* BibleAppWidgets.appex */; "
    f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n"
    "/* End PBXBuildFile section */",
)

# Container item proxy + copy-files phase sections (new).
replace_once(
    "/* Begin PBXFileReference section */",
    "/* Begin PBXContainerItemProxy section */\n"
    f"\t\t{PROXY} /* PBXContainerItemProxy */ = {{\n"
    "\t\t\tisa = PBXContainerItemProxy;\n"
    f"\t\t\tcontainerPortal = {PROJECT} /* Project object */;\n"
    "\t\t\tproxyType = 1;\n"
    f"\t\t\tremoteGlobalIDString = {WIDGET_TARGET};\n"
    "\t\t\tremoteInfo = BibleAppWidgets;\n"
    "\t\t};\n"
    "/* End PBXContainerItemProxy section */\n\n"
    "/* Begin PBXCopyFilesBuildPhase section */\n"
    f"\t\t{EMBED_PHASE} /* Embed Foundation Extensions */ = {{\n"
    "\t\t\tisa = PBXCopyFilesBuildPhase;\n"
    "\t\t\tbuildActionMask = 2147483647;\n"
    '\t\t\tdstPath = "";\n'
    "\t\t\tdstSubfolderSpec = 13;\n"
    "\t\t\tfiles = (\n"
    f"\t\t\t\t{EMBED_FILE} /* BibleAppWidgets.appex in Embed Foundation Extensions */,\n"
    "\t\t\t);\n"
    '\t\t\tname = "Embed Foundation Extensions";\n'
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
    "\t\t};\n"
    "/* End PBXCopyFilesBuildPhase section */\n\n"
    "/* Begin PBXFileReference section */",
)

# Product file reference.
replace_once(
    "/* End PBXFileReference section */",
    f"\t\t{APPEX} /* BibleAppWidgets.appex */ = {{isa = PBXFileReference; "
    'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; '
    "path = BibleAppWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; };\n"
    "/* End PBXFileReference section */",
)

# Keep the extension's Info.plist out of its sources.
replace_once(
    "/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */",
    f'\t\t{WIDGET_EXCEPTIONS} /* Exceptions for "BibleAppWidgets" folder in "BibleAppWidgets" target */ = {{\n'
    "\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n"
    "\t\t\tmembershipExceptions = (\n"
    "\t\t\t\tInfo.plist,\n"
    "\t\t\t);\n"
    f"\t\t\ttarget = {WIDGET_TARGET} /* BibleAppWidgets */;\n"
    "\t\t};\n"
    "/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */",
)

# Synchronized folders.
replace_once(
    "/* End PBXFileSystemSynchronizedRootGroup section */",
    f"\t\t{WIDGET_GROUP} /* BibleAppWidgets */ = {{\n"
    "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
    "\t\t\texceptions = (\n"
    f'\t\t\t\t{WIDGET_EXCEPTIONS} /* Exceptions for "BibleAppWidgets" folder in "BibleAppWidgets" target */,\n'
    "\t\t\t);\n"
    "\t\t\tpath = BibleAppWidgets;\n"
    '\t\t\tsourceTree = "<group>";\n'
    "\t\t};\n"
    f"\t\t{SHARED_GROUP} /* Shared */ = {{\n"
    "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
    "\t\t\tpath = Shared;\n"
    '\t\t\tsourceTree = "<group>";\n'
    "\t\t};\n"
    "/* End PBXFileSystemSynchronizedRootGroup section */",
)

# Extension frameworks phase.
replace_once(
    "/* End PBXFrameworksBuildPhase section */",
    f"\t\t{WIDGET_FRAMEWORKS} /* Frameworks */ = {{\n"
    "\t\t\tisa = PBXFrameworksBuildPhase;\n"
    "\t\t\tbuildActionMask = 2147483647;\n"
    "\t\t\tfiles = (\n"
    "\t\t\t);\n"
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
    "\t\t};\n"
    "/* End PBXFrameworksBuildPhase section */",
)

# Main group and Products group.
replace_once(
    "\t\t\t\tA130C3CE304E714300DBEEFA /* BibleApp */,\n\t\t\t\tA130C3CD304E714300DBEEFA /* Products */,",
    "\t\t\t\tA130C3CE304E714300DBEEFA /* BibleApp */,\n"
    f"\t\t\t\t{WIDGET_GROUP} /* BibleAppWidgets */,\n"
    f"\t\t\t\t{SHARED_GROUP} /* Shared */,\n"
    "\t\t\t\tA130C3CD304E714300DBEEFA /* Products */,",
)
replace_once(
    "\t\t\t\tA130C3CC304E714300DBEEFA /* BibleApp.app */,\n",
    "\t\t\t\tA130C3CC304E714300DBEEFA /* BibleApp.app */,\n"
    f"\t\t\t\t{APPEX} /* BibleAppWidgets.appex */,\n",
)

# App target: embed phase, dependency, Shared folder.
replace_once(
    "\t\t\t\tA130C3CA304E714300DBEEFA /* Resources */,\n\t\t\t);",
    "\t\t\t\tA130C3CA304E714300DBEEFA /* Resources */,\n"
    f"\t\t\t\t{EMBED_PHASE} /* Embed Foundation Extensions */,\n"
    "\t\t\t);",
)
replace_once(
    "\t\t\tdependencies = (\n\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n"
    "\t\t\t\tA130C3CE304E714300DBEEFA /* BibleApp */,\n\t\t\t);",
    "\t\t\tdependencies = (\n"
    f"\t\t\t\t{DEPENDENCY} /* PBXTargetDependency */,\n"
    "\t\t\t);\n"
    "\t\t\tfileSystemSynchronizedGroups = (\n"
    "\t\t\t\tA130C3CE304E714300DBEEFA /* BibleApp */,\n"
    f"\t\t\t\t{SHARED_GROUP} /* Shared */,\n"
    "\t\t\t);",
)

# Extension native target.
replace_once(
    "/* End PBXNativeTarget section */",
    f"\t\t{WIDGET_TARGET} /* BibleAppWidgets */ = {{\n"
    "\t\t\tisa = PBXNativeTarget;\n"
    f'\t\t\tbuildConfigurationList = {WIDGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "BibleAppWidgets" */;\n'
    "\t\t\tbuildPhases = (\n"
    f"\t\t\t\t{WIDGET_SOURCES} /* Sources */,\n"
    f"\t\t\t\t{WIDGET_FRAMEWORKS} /* Frameworks */,\n"
    f"\t\t\t\t{WIDGET_RESOURCES} /* Resources */,\n"
    "\t\t\t);\n"
    "\t\t\tbuildRules = (\n"
    "\t\t\t);\n"
    "\t\t\tdependencies = (\n"
    "\t\t\t);\n"
    "\t\t\tfileSystemSynchronizedGroups = (\n"
    f"\t\t\t\t{WIDGET_GROUP} /* BibleAppWidgets */,\n"
    f"\t\t\t\t{SHARED_GROUP} /* Shared */,\n"
    "\t\t\t);\n"
    "\t\t\tname = BibleAppWidgets;\n"
    "\t\t\tpackageProductDependencies = (\n"
    "\t\t\t);\n"
    "\t\t\tproductName = BibleAppWidgets;\n"
    f"\t\t\tproductReference = {APPEX} /* BibleAppWidgets.appex */;\n"
    '\t\t\tproductType = "com.apple.product-type.app-extension";\n'
    "\t\t};\n"
    "/* End PBXNativeTarget section */",
)

# Project: target attributes and target list.
replace_once(
    "\t\t\t\t\tA130C3CB304E714300DBEEFA = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.4;\n\t\t\t\t\t};\n",
    "\t\t\t\t\tA130C3CB304E714300DBEEFA = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.4;\n\t\t\t\t\t};\n"
    f"\t\t\t\t\t{WIDGET_TARGET} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.4;\n\t\t\t\t\t}};\n",
)
replace_once(
    "\t\t\ttargets = (\n\t\t\t\tA130C3CB304E714300DBEEFA /* BibleApp */,\n\t\t\t);",
    "\t\t\ttargets = (\n\t\t\t\tA130C3CB304E714300DBEEFA /* BibleApp */,\n"
    f"\t\t\t\t{WIDGET_TARGET} /* BibleAppWidgets */,\n\t\t\t);",
)

# Extension resources and sources phases.
replace_once(
    "/* End PBXResourcesBuildPhase section */",
    f"\t\t{WIDGET_RESOURCES} /* Resources */ = {{\n"
    "\t\t\tisa = PBXResourcesBuildPhase;\n"
    "\t\t\tbuildActionMask = 2147483647;\n"
    "\t\t\tfiles = (\n"
    "\t\t\t);\n"
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
    "\t\t};\n"
    "/* End PBXResourcesBuildPhase section */",
)
replace_once(
    "/* End PBXSourcesBuildPhase section */",
    f"\t\t{WIDGET_SOURCES} /* Sources */ = {{\n"
    "\t\t\tisa = PBXSourcesBuildPhase;\n"
    "\t\t\tbuildActionMask = 2147483647;\n"
    "\t\t\tfiles = (\n"
    "\t\t\t);\n"
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
    "\t\t};\n"
    "/* End PBXSourcesBuildPhase section */\n\n"
    "/* Begin PBXTargetDependency section */\n"
    f"\t\t{DEPENDENCY} /* PBXTargetDependency */ = {{\n"
    "\t\t\tisa = PBXTargetDependency;\n"
    f"\t\t\ttarget = {WIDGET_TARGET} /* BibleAppWidgets */;\n"
    f"\t\t\ttargetProxy = {PROXY} /* PBXContainerItemProxy */;\n"
    "\t\t};\n"
    "/* End PBXTargetDependency section */",
)


def widget_config(config_id, name):
    return (
        f"\t\t{config_id} /* {name} */ = {{\n"
        "\t\t\tisa = XCBuildConfiguration;\n"
        "\t\t\tbuildSettings = {\n"
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
        "\t\t\t\tDEVELOPMENT_TEAM = A6U459NUFN;\n"
        "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n"
        "\t\t\t\tINFOPLIST_FILE = BibleAppWidgets/Info.plist;\n"
        "\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = BibleAppWidgets;\n"
        "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.4;\n"
        '\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks";\n'
        "\t\t\t\tMARKETING_VERSION = 1.0;\n"
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.trailbyte.bible.widget.BibleAppWidgets;\n"
        '\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";\n'
        "\t\t\t\tSDKROOT = iphoneos;\n"
        "\t\t\t\tSKIP_INSTALL = YES;\n"
        '\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "WIDGET_EXTENSION $(inherited)";\n'
        "\t\t\t\tSWIFT_APPROACHABLE_CONCURRENCY = YES;\n"
        "\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;\n"
        "\t\t\t\tSWIFT_VERSION = 5.0;\n"
        '\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";\n'
        "\t\t\t};\n"
        f"\t\t\tname = {name};\n"
        "\t\t};\n"
    )


replace_once(
    "/* End XCBuildConfiguration section */",
    widget_config(WIDGET_DEBUG, "Debug")
    + widget_config(WIDGET_RELEASE, "Release")
    + "/* End XCBuildConfiguration section */",
)
replace_once(
    "/* End XCConfigurationList section */",
    f'\t\t{WIDGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "BibleAppWidgets" */ = {{\n'
    "\t\t\tisa = XCConfigurationList;\n"
    "\t\t\tbuildConfigurations = (\n"
    f"\t\t\t\t{WIDGET_DEBUG} /* Debug */,\n"
    f"\t\t\t\t{WIDGET_RELEASE} /* Release */,\n"
    "\t\t\t);\n"
    "\t\t\tdefaultConfigurationIsVisible = 0;\n"
    "\t\t\tdefaultConfigurationName = Release;\n"
    "\t\t};\n"
    "/* End XCConfigurationList section */",
)

path.write_text(text)
print("ok")
```

Expected output: `ok`.

- [ ] **Step 7: Check that Xcode reads the project**

Run: `xcodebuild -project BibleApp/BibleApp.xcodeproj -list`
Expected: `Targets:` lists both `BibleApp` and `BibleAppWidgets`.

- [ ] **Step 8: Build**

Run the build command from the header.
Expected: success. Then confirm the extension is embedded:

Run: `find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphonesimulator/BibleApp.app/PlugIns/BibleAppWidgets.appex' -maxdepth 8 | head -1`
Expected: one path printed.

- [ ] **Step 9: Commit**

```bash
git add BibleApp/Shared BibleApp/BibleAppWidgets BibleApp/BibleApp.xcodeproj/project.pbxproj BibleApp/BibleApp/Info.plist
git commit -m "Add BibleAppWidgets extension with the reading session Live Activity UI

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `ReadingSessionController`, shared model container, and intents

**Files:**
- Create: `BibleApp/BibleApp/State/SharedModelContainer.swift`
- Create: `BibleApp/BibleApp/LiveActivity/ReadingSessionController.swift`
- Create: `BibleApp/Shared/ReadingSessionIntents.swift`
- Modify: `BibleApp/BibleApp/Content/ContentStore.swift` (add `entry(for:)` after `content(for:)`)
- Modify: `BibleApp/BibleApp/BibleAppApp.swift` (`.modelContainer(for: UserState.self)` → `.modelContainer(SharedModelContainer.shared)`)

**Interfaces:**
- Consumes: `SessionQueue`, `PersistedSession`, `VerseSnippet` (Tasks 1–2); `ReadingSessionAttributes` (Task 3); existing `ContentStore.load()`, `ContentStore.content(for:)`, `UserState.markSeen(_:)`, `UserState.toggleSaved(_:)`, `UserState.savedSet`, `UserState.preferredTranslation`.
- Produces:
  - `enum SharedModelContainer { static let shared: ModelContainer }`
  - `ContentStore.entry(for id: String) -> VerseIndexEntry?`
  - `@Observable final class ReadingSessionController` with `static let shared`, `private(set) var activeEndDate: Date?`, `var alertMessage: String?`, and `func start(minutes: Int, ids: [String]) async`, `func next() async`, `func toggleSaved() async`, `func end() async`, `func reconcile() async`
  - `NextVerseIntent`, `SaveVerseIntent`, `EndSessionIntent` (`LiveActivityIntent`, no parameters)

- [ ] **Step 1: Shared model container**

Create `BibleApp/BibleApp/State/SharedModelContainer.swift`:

```swift
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
```

In `BibleApp/BibleApp/BibleAppApp.swift`, replace:

```swift
        .modelContainer(for: UserState.self)
```

with:

```swift
        .modelContainer(SharedModelContainer.shared)
```

- [ ] **Step 2: Index lookup on `ContentStore`**

In `BibleApp/BibleApp/Content/ContentStore.swift`, insert after the closing brace of `func content(for ids: [String]) async -> [String: VerseContent]`:

```swift

    func entry(for id: String) -> VerseIndexEntry? {
        indexByID[id]
    }
```

- [ ] **Step 3: The controller**

Create `BibleApp/BibleApp/LiveActivity/ReadingSessionController.swift`:

```swift
import ActivityKit
import Foundation
import SwiftData
import BibleFeedKit

/// Runs the timed reflection session: starts the Live Activity, answers its
/// Lock Screen buttons, and cleans up after expiry or dismissal. The
/// session is kept on disk so a button tap still works after the app has
/// been terminated.
@Observable
final class ReadingSessionController {
    static let shared = ReadingSessionController()

    private(set) var activeEndDate: Date?
    var alertMessage: String?

    private let store = ContentStore()
    private let fileURL = URL.applicationSupportDirectory.appending(path: "reading-session.json")

    private init() {
        activeEndDate = PersistedSession.load(from: fileURL)?.queue.endDate
    }

    func start(minutes: Int, ids: [String]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            alertMessage = "Turn on Live Activities for this app in Settings to use reflection sessions."
            return
        }
        await end(dismissal: .immediate)

        let endDate = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        guard var queue = SessionQueue(ids: Array(ids.prefix(200)), endDate: endDate),
              let state = await loadState(for: &queue) else {
            alertMessage = "Couldn't load verses for this session."
            return
        }
        do {
            let activity = try Activity.request(
                attributes: ReadingSessionAttributes(endDate: endDate),
                content: ActivityContent(state: state, staleDate: endDate),
                pushType: nil)
            persist(PersistedSession(activityID: activity.id, queue: queue))
        } catch {
            alertMessage = "Couldn't start the session. \(error.localizedDescription)"
        }
    }

    func next() async {
        guard var session = PersistedSession.load(from: fileURL) else { return }
        guard !session.queue.isExpired(now: .now) else {
            await end()
            return
        }
        userState?.markSeen(session.queue.current)
        saveContext()
        guard session.queue.advance(),
              let state = await loadState(for: &session.queue) else {
            await end()
            return
        }
        persist(session)
        await activity(for: session)?.update(
            ActivityContent(state: state, staleDate: session.queue.endDate))
    }

    func toggleSaved() async {
        guard let session = PersistedSession.load(from: fileURL),
              let activity = activity(for: session),
              let userState else { return }
        userState.toggleSaved(session.queue.current)
        saveContext()
        var state = activity.content.state
        state.isSaved = userState.savedSet.contains(session.queue.current)
        await activity.update(ActivityContent(state: state, staleDate: session.queue.endDate))
    }

    func end() async {
        await end(dismissal: .default)
    }

    /// Run on launch and on every return to the foreground. Finishes a
    /// session that expired or was swiped away, and ends stray activities.
    func reconcile() async {
        let session = PersistedSession.load(from: fileURL)
        for activity in Activity<ReadingSessionAttributes>.activities
        where activity.id != session?.activityID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let session else {
            activeEndDate = nil
            return
        }
        let live = activity(for: session)
        let isLive = live.map { $0.activityState == .active } ?? false
        if session.queue.isExpired(now: .now) || !isLive {
            finish(session)
            await live?.end(nil, dismissalPolicy: .immediate)
        } else {
            activeEndDate = session.queue.endDate
        }
    }

    // MARK: - Private

    private var context: ModelContext { SharedModelContainer.shared.mainContext }

    private var userState: UserState? {
        try? context.fetch(FetchDescriptor<UserState>()).first
    }

    private func end(dismissal: ActivityUIDismissalPolicy) async {
        guard let session = PersistedSession.load(from: fileURL) else { return }
        finish(session)
        guard let activity = activity(for: session) else { return }
        var state = activity.content.state
        state.isComplete = true
        await activity.end(ActivityContent(state: state, staleDate: nil),
                           dismissalPolicy: dismissal)
    }

    /// Counts the last verse as read and forgets the session.
    private func finish(_ session: PersistedSession) {
        userState?.markSeen(session.queue.current)
        saveContext()
        PersistedSession.delete(at: fileURL)
        activeEndDate = nil
    }

    private func persist(_ session: PersistedSession) {
        do {
            try session.save(to: fileURL)
            activeEndDate = session.queue.endDate
        } catch {
            assertionFailure("Could not save the reading session: \(error)")
        }
    }

    private func saveContext() {
        try? context.save()
    }

    private func activity(for session: PersistedSession) -> Activity<ReadingSessionAttributes>? {
        Activity<ReadingSessionAttributes>.activities.first { $0.id == session.activityID }
    }

    /// Builds the Lock Screen state for the queue's current verse, moving
    /// past verses whose content fails to load, up to three tries.
    private func loadState(for queue: inout SessionQueue) async -> ReadingSessionAttributes.ContentState? {
        if store.index.isEmpty { store.load() }
        let translation = userState?.preferredTranslation ?? .kjv
        for _ in 0..<3 {
            let id = queue.current
            if let entry = store.entry(for: id),
               let content = await store.content(for: [id])[id] {
                let text = content.translations[translation]?.displayText
                    ?? content.translations[.kjv]?.displayText ?? ""
                return ReadingSessionAttributes.ContentState(
                    verseID: id,
                    reference: entry.reference,
                    text: VerseSnippet.truncate(text),
                    versesRead: queue.versesRead,
                    isSaved: userState?.savedSet.contains(id) ?? false,
                    isComplete: false)
            }
            guard queue.advance() else { return nil }
        }
        return nil
    }
}
```

- [ ] **Step 4: The intents**

Create `BibleApp/Shared/ReadingSessionIntents.swift`:

```swift
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
```

- [ ] **Step 5: Build**

Run the build command from the header.
Expected: success. If the compiler reports an actor-isolation error on an intent's `perform()` (reaching the main-actor `ReadingSessionController.shared` from a nonisolated context), mark each of the three `perform()` methods `@MainActor` and rebuild.

- [ ] **Step 6: Commit**

```bash
git add BibleApp/BibleApp/State/SharedModelContainer.swift BibleApp/BibleApp/LiveActivity BibleApp/Shared/ReadingSessionIntents.swift BibleApp/BibleApp/Content/ContentStore.swift BibleApp/BibleApp/BibleAppApp.swift
git commit -m "Add ReadingSessionController and Lock Screen intents

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Lock Screen buttons

**Files:**
- Modify: `BibleApp/BibleAppWidgets/ReadingSessionLiveActivity.swift` (replace the placeholder `SessionControls`)

**Interfaces:**
- Consumes: `NextVerseIntent`, `SaveVerseIntent`, `EndSessionIntent` (Task 4).

- [ ] **Step 1: Replace the placeholder**

In `BibleApp/BibleAppWidgets/ReadingSessionLiveActivity.swift`, add `import AppIntents` below `import ActivityKit`, then replace:

```swift
/// Filled in once the Lock Screen intents exist.
private struct SessionControls: View {
    let isSaved: Bool

    var body: some View {
        EmptyView()
    }
}
```

with:

```swift
/// Save, Next and End. Each runs a `LiveActivityIntent` in the app process.
private struct SessionControls: View {
    let isSaved: Bool

    var body: some View {
        HStack {
            Button(intent: SaveVerseIntent()) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
            }
            .accessibilityLabel(isSaved ? "Remove from saved" : "Save verse")

            Spacer()

            Button(intent: NextVerseIntent()) {
                Label("Next", systemImage: "forward.fill")
            }

            Spacer()

            Button(intent: EndSessionIntent()) {
                Image(systemName: "stop.fill")
            }
            .accessibilityLabel("End session")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .font(.subheadline.weight(.semibold))
    }
}
```

- [ ] **Step 2: Build**

Run the build command from the header.
Expected: success.

- [ ] **Step 3: Check the previews render**

Open `BibleApp/BibleAppWidgets/ReadingSessionLiveActivity.swift` in Xcode and view the "Lock Screen" and "Expanded" previews. Expected: the short verse shows three buttons; the long verse fits in 3 lines (shrinking to at most 80%); the complete state shows "Session complete · 5 verses" with no buttons.

- [ ] **Step 4: Commit**

```bash
git add BibleApp/BibleAppWidgets/ReadingSessionLiveActivity.swift
git commit -m "Add Next, Save and End buttons to the reading session Live Activity

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Start and stop from the Feed

**Files:**
- Create: `BibleApp/BibleApp/Views/ReflectionButton.swift`
- Modify: `BibleApp/BibleApp/Views/FeedView.swift`
- Modify: `BibleApp/BibleApp/ContentView.swift`

**Interfaces:**
- Consumes: `ReadingSessionController.shared` (`activeEndDate`, `alertMessage`, `start(minutes:ids:)`, `end()`, `reconcile()`) from Task 4.
- Produces: `struct ReflectionButton: View { let ids: () -> [String] }`.

- [ ] **Step 1: The button**

Create `BibleApp/BibleApp/Views/ReflectionButton.swift`:

```swift
import SwiftUI

/// Starts a timed reflection session on the Lock Screen, or shows the
/// running one with a way to end it.
struct ReflectionButton: View {
    /// Verse ids for the session, starting at the verse on screen.
    let ids: () -> [String]

    @State private var isChoosingDuration = false
    private let session = ReadingSessionController.shared

    var body: some View {
        Group {
            if let endDate = session.activeEndDate, endDate > .now {
                Button {
                    Task { await session.end() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text(timerInterval: Date.now...endDate, countsDown: true)
                            .monospacedDigit()
                        Text("· End")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                }
                .accessibilityLabel("End reflection session")
            } else {
                Button {
                    isChoosingDuration = true
                } label: {
                    Image(systemName: "timer")
                }
                .accessibilityLabel("Start reflection session")
            }
        }
        .font(.subheadline.weight(.semibold))
        .confirmationDialog("Reflection session",
                            isPresented: $isChoosingDuration,
                            titleVisibility: .visible) {
            ForEach([5, 10, 15], id: \.self) { minutes in
                Button("\(minutes) minutes") {
                    let sessionIDs = ids()
                    Task { await session.start(minutes: minutes, ids: sessionIDs) }
                }
            }
        } message: {
            Text("Keep reading on your Lock Screen until the timer ends.")
        }
        .alert("Reflection session",
               isPresented: Binding(get: { session.alertMessage != nil },
                                    set: { if !$0 { session.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.alertMessage ?? "")
        }
    }
}
```

- [ ] **Step 2: Track the visible verse and host the button in `FeedView`**

In `BibleApp/BibleApp/Views/FeedView.swift`:

Add below `@State private var seenTasks: [String: Task<Void, Never>] = [:]`:

```swift
    @State private var visibleID: String?
```

Replace:

```swift
        .scrollTargetBehavior(.paging)
```

with:

```swift
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleID)
```

Replace the overlay's `HStack` contents:

```swift
                Label("\(state.streak)", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.streak > 0 ? .orange : .secondary)
                Spacer()
```

with:

```swift
                Label("\(state.streak)", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.streak > 0 ? .orange : .secondary)
                Spacer()
                ReflectionButton(ids: sessionIDs)
```

Add this method just above `private func rebuild()`:

```swift
    /// The Feed queue from the verse on screen onward, for a reflection
    /// session. Falls back to the start when nothing has scrolled yet.
    private func sessionIDs() -> [String] {
        let start = visibleID.flatMap { id in queue.firstIndex { $0.id == id } } ?? 0
        return queue[start...].prefix(200).map(\.id)
    }
```

- [ ] **Step 3: Reconcile on launch and foreground in `ContentView`**

In `BibleApp/BibleApp/ContentView.swift`, replace:

```swift
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard newPhase == .active else { return }
```

with:

```swift
        .task {
            await ReadingSessionController.shared.reconcile()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard newPhase == .active else { return }
            Task { await ReadingSessionController.shared.reconcile() }
```

- [ ] **Step 4: Build**

Run the build command from the header.
Expected: success.

- [ ] **Step 5: Commit**

```bash
git add BibleApp/BibleApp/Views/ReflectionButton.swift BibleApp/BibleApp/Views/FeedView.swift BibleApp/BibleApp/ContentView.swift
git commit -m "Start and end reflection sessions from the Feed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: End-to-end verification in the Simulator

**Files:** none unless a check fails (fix in the file that owns the behavior, rebuild, re-run the failing check, commit with a message naming the fix).

Use the iPhone 17 Pro simulator (has a Dynamic Island). Build and run the `BibleApp` scheme on it, complete onboarding if shown.

- [ ] **Step 1: Start.** On Feed, scroll to the third card, tap ⏱, choose "5 minutes". Expected: the pill "⏱ 4:59 · End" appears; the Dynamic Island shows 📖 and a countdown.
- [ ] **Step 2: Lock Screen.** Lock (⌘L). Expected: "Reflection · 1 verse", the third card's verse and reference, a running countdown, and 🔖 / Next / ⏹.
- [ ] **Step 3: Next.** Tap Next twice. Expected: the verse changes each time and the header reads "2 verses", then "3 verses".
- [ ] **Step 4: Save.** Tap 🔖. Expected: the icon fills. Unlock, open Saved: the verse is listed.
- [ ] **Step 5: Seen and streak.** Expected: the streak on Feed is at least 1. Switch tabs away and back so Feed rebuilds: the verses passed with Next do not reappear near the top.
- [ ] **Step 6: Cold wake.** Terminate the app from the app switcher, lock, tap Next. Expected: the verse still advances.
- [ ] **Step 7: End.** Tap ⏹. Expected: "Session complete · N verses" with no buttons; opening the app shows the ⏱ icon again, not the pill.
- [ ] **Step 8: Expiry.** Start a 5-minute session and wait it out (or temporarily change `[5, 10, 15]` to `[1, 10, 15]` locally and do not commit it). Expected: the Lock Screen switches to the complete state by itself; on reopening the app the pill is gone.
- [ ] **Step 9: Disabled.** Settings → BibleApp → turn off Live Activities, tap ⏱ → 5 minutes. Expected: the "Turn on Live Activities…" alert.
- [ ] **Step 10: Package tests still pass.** Run `cd packages/BibleFeedKit && swift test`. Expected: all pass.
