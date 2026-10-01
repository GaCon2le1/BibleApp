# Verse of the Day Widget — Design

## Goal

Add a Home Screen and Lock Screen widget that shows one Bible verse per day as
text. Tapping it opens that verse in the app.

## Scope

- Content: "verse of the day" only. "Continue reading" is out of scope.
- Families: `systemSmall`, `systemMedium`, `accessoryRectangular`, `accessoryInline`.
- Data path: App Group (approach A). The app writes a snapshot; the widget only reads it.

## Data flow

1. **Pick the verse.** A pure function maps a date to an index in `feed_index`
   (`daysSinceEpoch % verses.count`). The same verse shows all day.
2. **Write the snapshot.** On launch and on return to foreground, the app loads
   the verse text via `ContentStore.content(for:)` and writes
   `{id, reference, text, day}` to App Group `UserDefaults`.
3. **Reload.** After writing, the app calls `WidgetCenter.reloadAllTimelines()`.
4. **Timeline.** The widget reads the snapshot, emits one entry, and schedules
   the next refresh at the next midnight. If the app has not been opened since
   the day changed, the widget keeps showing the last snapshot.
5. **Fallback.** With no snapshot at all (app never launched), show a hardcoded
   verse (Genesis 1:1) so the widget is never empty.

## UI

| Family | Content |
|---|---|
| `systemSmall` | Reference, verse text scaled/truncated to fit |
| `systemMedium` | Reference, fuller verse text |
| `accessoryRectangular` | Reference plus 2–3 lines of text |
| `accessoryInline` | `Reference · start of verse…` |

All families set `widgetURL(bibleapp://verse/<id>)`. `ContentView.onOpenURL`
gains a branch that switches to the Feed tab and scrolls to that verse.

## Project changes

- New `BibleAppWidgets/VerseOfTheDayWidget.swift`, registered in
  `BibleAppWidgetsBundle`.
- New shared file in `Shared/` for the snapshot struct and App Group read/write.
- App Group capability on both the app and widget targets. This must be enabled
  in Xcode by the user (needs an App Group ID on their developer account).
- Prerequisite: the app and widget targets currently use different
  `DEVELOPMENT_TEAM` values (`875TKZ94AW` vs `A6U459NUFN`). App Groups require
  both to be in the same team; confirm before testing on a device.

## Error handling

- If a shard fails to load, keep the previous snapshot; never overwrite it with
  empty data.
- If the snapshot cannot be decoded, use the hardcoded fallback.

## Testing

- Unit tests: date → verse selection (stable within a day, changes across days,
  wraps at the end of the list) and snapshot encode/decode.
- Manual: check all four families in the Simulator, and tap-through to the verse.
