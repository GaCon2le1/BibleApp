# Reading Session Live Activity — Design

Date: 2026-09-29
Status: Approved

## Problem

Users can only read verses with the app open. We want a timed reflection
session that lives on the Lock Screen and Dynamic Island as a Live Activity —
the current verse, a countdown, and controls — so a user can keep reading
without unlocking, in the spirit of lock-screen lyrics in music apps.

A Live Activity must represent an ongoing event with an end, so the feature
is framed as a timed session rather than a permanent "verse of the day"
(that belongs to a future Lock Screen widget, out of scope here).

## Decisions

| Question | Decision |
|---|---|
| Session model | Timed reflection: user picks 5, 10 or 15 minutes; unlimited verses until time runs out |
| Verse source | Continue the Feed queue, starting at the verse currently on screen in Feed; up to 200 ids captured at start |
| Seen / streak | Advancing past a verse (▶︎), ending (⏹), or expiry marks the verse seen via `UserState.markSeen`, which also counts the streak day. No 2-second dwell rule on the Lock Screen — the tap is deliberate |
| Lock Screen controls | ▶︎ Next, 🔖 Save (toggle), ⏹ End |
| How buttons run | `LiveActivityIntent`s whose `perform()` runs in the app process (iOS wakes the app in the background, even if it was terminated). No server, no push |
| Concurrency | At most one session. Starting a new one ends the old one first |
| Language | UI strings in English, matching the rest of the app. Verse text uses the preferred translation, falling back to KJV |
| Deployment target | Unchanged (iOS 26.4); every API used is available |

Rejected alternatives:
- **Preload all verses into the activity's content state** — ActivityKit caps
  the payload at ~4 KB, and marking verses seen still requires the app.
- **Remote push updates via APNs** — the app has no backend.

## Architecture

### New target

`BibleAppWidgets` — a Widget Extension containing only the Live Activity UI.
It does not link `BibleFeedKit` and needs no App Group, because all logic and
data access happen in the app process.

### Shared between app and extension

- `ReadingSessionAttributes: ActivityAttributes`
  - static: `endDate: Date`
  - `ContentState`: `verseID: String`, `reference: String`,
    `text: String` (already truncated), `versesRead: Int`, `isSaved: Bool`
- `NextVerseIntent`, `SaveVerseIntent`, `EndSessionIntent` —
  `LiveActivityIntent`s. The extension references them only to build
  `Button(intent:)`; `perform()` calls into `ReadingSessionController` in the
  app target.

### App target

- `SessionQueue` (in `BibleFeedKit`, pure value type, `Codable`):
  `ids: [String]`, `position: Int`, `endDate: Date`, `versesRead: Int`;
  `current`, `advance() -> Bool` (false when exhausted), `isExpired(now:)`
  (true when `now >= endDate`).
- `VerseSnippet.truncate(_:limit:)` (in `BibleFeedKit`): returns the text
  unchanged if it fits in `limit` characters (default 220), otherwise cuts at
  the last word boundary within the limit and appends "…". Operates on
  `Character`s so grapheme clusters are never split.
- `ReadingSessionController` (`@MainActor`, single shared instance):
  `start(duration:from:)`, `next()`, `toggleSaved()`, `end()`,
  `reconcile()`. Talks to ActivityKit, reads verse content through
  `ContentStore`, mutates `UserState`, and persists the session (activity id
  plus `SessionQueue`) as a small JSON file in Application Support so it
  survives termination.
- `SharedModelContainer`: a single static `ModelContainer` for `UserState`,
  used by the `WindowGroup` (`.modelContainer(SharedModelContainer.shared)`)
  and by intents running with no UI.
- Feed UI: a ⏱ button in the Feed top overlay next to the streak. Tapping it
  shows a confirmation dialog with 5 / 10 / 15 minutes. While a session is
  active, the button becomes a pill "⏱ 7:32 · End". `FeedView` tracks the
  visible card with `.scrollPosition(id:)` so the session can start there.
- `Info.plist`: `NSSupportsLiveActivities = YES`.

## UI

### Lock Screen (≤160pt tall)

```
┌──────────────────────────────────────────┐
│ ⏱ Reflection · 3 verses          07:32 │
│                                          │
│ "Be still, and know that I am God:       │
│  I will be exalted among the heathen…"   │
│ Psalm 46:10                              │
│                                          │
│        🔖           ▶︎ Next          ⏹    │
└──────────────────────────────────────────┘
```

- Countdown uses `Text(timerInterval:countsDown:)`; no per-second updates.
- Verse text: serif, `lineLimit(3)`, `minimumScaleFactor(0.8)`.
- 🔖 shows `bookmark.fill` when saved.
- Tapping the activity body opens the app on the Feed tab.

### Expired (stale) state

The activity is requested with `staleDate = endDate`. When
`context.isStale`, the view shows "✓ Session complete · N verses" and the last
reference dimmed, with no buttons. The app does not need to run for this.

### Dynamic Island

- Compact: leading book icon, trailing countdown.
- Minimal: countdown.
- Expanded: leading reference, trailing countdown; bottom region with two
  lines of verse text and the three buttons.

## Data flow

**Start**
1. If `ActivityAuthorizationInfo().areActivitiesEnabled` is false, show an
   alert "Turn on Live Activities in Settings" and stop.
2. End any existing session.
3. Capture up to 200 ids from the Feed queue starting at the visible verse.
4. Load content for the first verse, `Activity.request(...)` with
   `staleDate = endDate`, `pushType: nil`.
5. Persist the session file.

**Next (▶︎)**
Load session file → if expired, run End → `markSeen(current)` and save the
model context → `advance()`; if exhausted, run End → load content →
`activity.update(...)` with `versesRead + 1` → persist.

**Save (🔖)**
`toggleSaved(current)` → save context → update `isSaved`.

**End (⏹, expiry, or exhaustion)**
`markSeen(current)` → `activity.end(...)` with the "Session complete" content
and `.default` dismissal → delete the session file.

**`reconcile()`** — on launch and every return to `.active` scene phase:
- Session expired, or its activity is no longer active (user dismissed it):
  `markSeen(current)`, end the activity with `.immediate` if it still
  exists, delete the file.
- An activity with no session file, or a file with no activity: clean up the
  orphan.

## Error handling

- Content for a verse fails to load (missing shard): skip to the next id, up
  to 3 attempts; if all fail, End.
- `Activity.request` throws (e.g. system limit): show a short alert; no
  session file is written.
- Intent runs on a cold launch: the controller calls `store.load()` if the
  index is empty.
- Rapid repeated taps: all controller work runs serially on `@MainActor`.

## Out of scope

- Feed does not live-follow the verse being read on the Lock Screen; seen
  verses simply drop out on the next Feed rebuild.
- No sound or haptic at expiry.
- Saved-verses sessions, Lock Screen widget, audio Bible.

## Testing

**Unit tests (`BibleFeedKit`, TDD)**
- `SessionQueue`: `current`, `advance()` mid-list and at the end,
  `isExpired(now:)` exactly at `endDate`, Codable round-trip.
- `VerseSnippet.truncate`: short text unchanged, long text cut at a word
  boundary with "…", no split grapheme clusters, text with no spaces.

**Previews** — `#Preview(as: .content, using:)` for Lock Screen, compact,
minimal, expanded, and the complete state, each with a short and a very long
verse.

**Manual (Simulator, iPhone 17 Pro)**
1. Start a 5-minute session, lock (⌘L): Lock Screen layout and running
   countdown.
2. ▶︎ several times, open the app: streak counted, read verses gone from the
   rebuilt Feed.
3. 🔖: verse appears in Saved.
4. Terminate the app, ▶︎ from the Lock Screen: app wakes and the verse
   updates.
5. Wait for expiry: complete state, buttons hidden.
6. Disable Live Activities in Settings, tap ⏱: alert shown.
