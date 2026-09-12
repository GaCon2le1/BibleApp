# Paginated Content Loading — Design

Date: 2026-09-12
Status: Approved

## Problem

`ContentStore.load()` reads the entire `feed_verses.json` (1.2MB, 1000 verses,
each carrying 3 translations plus a context paragraph) into memory as
`[Verse]` at app launch, and keeps all of it resident for the whole session.
This works today but does not scale: every verse's full text sits in memory
whether or not the user ever scrolls to it, and the cost only grows as the
feed expands toward the full Bible.

`FeedEngine.queue(...)` genuinely needs to see every verse's `id`, `tier`,
and `topics` on every rebuild to rank and order the feed — it cannot operate
on a partial window of the dataset. So the fix is not "load less data
overall," it's splitting *what must always be resident* (lightweight ranking
metadata) from *what can be loaded on demand* (translation text and context).

## Decisions

| Question | Decision |
|---|---|
| What stays fully resident in memory | A lightweight index: `id, reference, book, chapter, verse, topics, tier, shard` per verse — no translation text, no context |
| What loads on demand | Translation text + context, split into shard files, decoded only when a verse in that shard needs to be displayed |
| Shard size | 100 verses/shard (10 shards for the current 1000-verse set) |
| Shard cache eviction | LRU, capped at 5 resident shards (~600KB ceiling regardless of total dataset size) |
| Loading trigger | Each card's `.onAppear` requests its shard plus the next shard in scroll direction (prefetch) |
| Loading UI | Skeleton placeholder that cross-fades to real text once content resolves; only visible on very fast swipes since shard decode is a local, sub-millisecond operation |
| Missing/corrupt index file | Packaging bug — `assertionFailure` + `loadFailed`, same as today |
| Missing/corrupt shard file | Recoverable — skip that verse rather than failing the whole app |

## Data format

`Resources/feed_verses.json` is replaced by two kinds of bundled files:

- **`feed_index.json`** — `{schemaVersion, contentVersion, verses: [VerseIndexEntry]}`.
  Always fully decoded at launch.
- **`feed_shards/shard_0000.json` … `shard_0009.json`** — each
  `{schemaVersion, contentVersion, verses: [VerseContentEntry]}`, 100 verses
  per shard.

`tools/build_feed.py` assigns `shard = index // 100` while walking the verse
list in the same order it uses today (this order must stay stable —
`FeedEngine`'s seeded shuffle depends on it, per the existing comment in
`FeedEngine.swift`) and writes both outputs. `tools/validate_feed.py` is
extended to check that every index entry's shard file contains that id
exactly once, and that no shard contains an id absent from the index.

`schemaVersion` and `CONTENT_VERSION` are bumped to mark this as a breaking
format change.

## BibleFeedKit model split

`Verse.swift` splits into:

- `VerseIndexEntry` (`id, reference, book, chapter, verse, topics, tier,
  shard`) — Codable/Identifiable/Hashable/Sendable. This is what
  `FeedEngine` ranks.
- `VerseContent` (`id, translations, context`) — Codable/Sendable, decoded
  from shard files.
- `Verse` — unchanged shape, kept for UI code that wants translations +
  metadata together. Built via `Verse.init(index: VerseIndexEntry, content:
  VerseContent)` at the point of use, so `VerseCard`/`LibraryView` keep
  working with one familiar type.
- `FeedContent` is renamed `FeedIndex`. A new `ContentShard` type mirrors it
  for shard files.

`FeedEngine` changes its stored/queued type from `[Verse]` to
`[VerseIndexEntry]`. `score`/`rank`/`queue` are otherwise unchanged since
they only ever read `id`/`tier`/`topics`. `FeedQueue.verses` becomes
`[VerseIndexEntry]`.

## Runtime loading & caching (BibleApp target)

- `ContentStore` loads `feed_index.json` eagerly at launch, exactly like
  today, and exposes `index: [VerseIndexEntry]`.
- A new `ShardStore` actor owns the LRU shard cache. `func content(for ids:
  some Collection<String>) async -> [String: VerseContent]` decodes any
  shard not already cached (looking up each id's `shard` field from the
  index) and evicts the least-recently-touched shard(s) once resident count
  exceeds 5.
- `ContentStore` owns one `ShardStore` shared by the whole app, so a shard
  decoded for the feed is reused if the Library needs the same verse.

## UI integration

- `FeedView.queue` becomes `[VerseIndexEntry]`; a new
  `loadedContent: [String: VerseContent]` holds merged-in content for the
  currently visible/prefetched window.
- Each card's `.onAppear` (alongside the existing seen-timer) also starts a
  task that asks `ShardStore` for that verse's shard plus the next shard in
  scroll direction, merging results into `loadedContent`.
- `VerseCard` takes `(entry: VerseIndexEntry, content: VerseContent?, ...)`.
  `content == nil` renders a skeleton that cross-fades to real text once
  content arrives.
- `LibraryView.saved` filters `store.index` (metadata only, cheap) for the
  saved id set, then requests content for exactly those ids from the shared
  `ShardStore` before rendering rows.
- `MilestoneCard(count:)` reads `store.index.count`.

## Error handling

Same philosophy as today, split by failure scope: index corruption is a
whole-app packaging failure (`assertionFailure` + `loadFailed`); shard
corruption is scoped to the verses in that shard and does not take down the
rest of the feed.

## Testing

- Codable round-trip tests for `VerseIndexEntry`, `VerseContent`, and the
  shard/index JSON schemas.
- `FeedEngineTests` updated to build `VerseIndexEntry` fixtures instead of
  full `Verse`.
- New `ShardStoreTests`: cache hit avoids re-decoding, LRU eviction at
  capacity, concurrent overlapping `ensureLoaded` calls don't double-decode.
- `tools/test_build_feed.py` / `tools/test_validate_feed.py` updated for the
  two-file output.

## Out of scope

- Remote/network fetching of content — everything stays bundled with the
  app; this design only changes what's decoded into memory and when.
- Changing the feed ranking algorithm itself.
- Per-book/chapter sharding (fixed 100-verse shards only, for now).
