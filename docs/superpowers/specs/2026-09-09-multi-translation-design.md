# Multi-Translation Support — Design

Date: 2026-09-09
Status: Approved

## Problem

The scroll feed ships 600 verses in KJV only. The user wants to add two more
free, public-domain translations — BSB (Berean Standard Bible) and CPDV
(Catholic Public Domain Version) — so a viewer can read the same 600 verses
in a translation of their choice.

Both are available in the same JSON schema already used for `data/source/KJV.json`,
from the same source repository (`scrollmapper/bible_databases`). BSB is a
drop-in: its 66 books line up with the Protestant canon by array position,
exactly like KJV, with zero chapter-count mismatches.

CPDV is not a drop-in. Investigation (this session, verified against the real
vendored files, not assumed from reference literature) found:

- CPDV's 78 books are not a superset of the 66 Protestant books in the same
  order — it interleaves the deuterocanonical books through the Old Testament
  in traditional Catholic order, so it cannot be paired by array index the way
  KJV and BSB can. It must be paired by (normalized) book name instead.
- CPDV's Psalms use the traditional Vulgate/Septuagint numbering, which
  diverges from the Protestant numbering used throughout this app (topics,
  tiers, contexts, and every existing id are all pinned to Protestant
  numbering). Confirmed directly: KJV Psalm 23 ("The LORD is my shepherd") is
  CPDV's chapter 22. The offset is not a constant — it shifts through two
  merge/split zones (around Psalm 9–11 and Psalm 114–117/146–148) before
  resolving back to zero by Psalm 148.
- Separately, many CPDV Psalms carry their heading (e.g. "Unto the end. A
  Psalm of David.") as its own verse 1, while KJV folds the same heading into
  verse 1 alongside the first line of content. This shifts verse numbers
  within a chapter by one, independent of the chapter-level Psalms offset
  above, and is specific to headed Psalms — confirmed absent in Habakkuk 3,
  Romans 1, Genesis 1, and Matthew 1, which all match KJV's verse count
  exactly.
- A full 1,189-chapter scan across all 66 books found 139 of Psalms' 150
  chapters affected, versus 62 scattered mismatches (ordinary translation
  verse-division differences, not a systemic numbering scheme) across the
  other 65 books combined.
- Of the app's 600 selected verses, 130 (107 Psalms, 23 elsewhere) sit in an
  affected chapter and need their exact CPDV (chapter, verse) resolved by
  reading real content, not computed from a formula. The other 470 verses
  should genuinely be a direct (chapter, verse) match, and get one non-blocking
  automated content-similarity check as a safety net rather than blind trust.

The owner chose full accuracy over reduced scope: verify all 600 verses
against real CPDV content before shipping, rather than only supporting the
470 unaffected verses or dropping CPDV for Psalms.

## Decisions

| Question | Decision |
|---|---|
| How does a viewer switch translation | One default translation, chosen in Settings, not a per-card control |
| Where does the Settings control live | The Library sheet's toolbar (alongside the existing "Edit topics") — no new top-level screen, no growth of the feed header |
| Does the reference label change per translation | No. It always shows the Protestant reference (e.g. "Psalms 23:1"), because topics, tier, and context are all keyed to Protestant numbering regardless of which translation's text is on screen |
| Default translation for existing and new users | KJV, unchanged — this feature adds optionality, it does not change today's default |
| CPDV verse resolution for the 130 affected verses | A committed, per-id reference table (`data/curation/cpdv_verse_map.json`), each entry verified against real CPDV text before being added — not a computed offset formula |
| CPDV verse resolution for the other 470 | Direct (chapter, verse) match, still covered by an automated content-similarity check in the validator |

## Architecture

### Data model

Each entry in `feed_verses.json` keeps its existing translation-independent
fields (`id`, `reference`, `book`, `chapter`, `verse`, `context`, `topics`,
`tier`) and gains one new field, `translations`, holding the three texts:

```json
{
  "id": "PSA.23.1",
  "reference": "Psalms 23:1",
  "book": "PSA", "chapter": 23, "verse": 1,
  "translations": {
    "KJV":  { "text": "A Psalm of David. The Lord is my shepherd; I shall not want.",
              "displayText": "The Lord is my shepherd; I shall not want." },
    "BSB":  { "text": "A Psalm of David. The LORD is my shepherd; I shall lack nothing.",
              "displayText": "The LORD is my shepherd; I shall lack nothing." },
    "CPDV": { "text": "A Psalm of David. The Lord directs me, and nothing will be lacking to me.",
              "displayText": "The Lord directs me, and nothing will be lacking to me." }
  },
  "context": "David compares God to a shepherd who provides and protects.",
  "topics": ["peace", "hope"], "tier": 1
}
```

`displayText` keeps doing exactly what it already does for KJV — the
superscription/marker stripped, card-facing form — extended to whichever
translation's raw text carries the same kind of artifact. CPDV's headed
Psalms need no stripping at all once the reference table points at the
correct content verse directly (see Content pipeline below), since the
heading already lives in its own separate verse in CPDV, unlike KJV's
merged-into-verse-1 convention.

In `BibleFeedKit`: `Verse` gains `translations: [Translation: TranslationText]`.
`Translation` is a `String`-backed `Codable` enum, cases `kjv`, `bsb`, `cpdv`,
matching the JSON keys `"KJV"`/`"BSB"`/`"CPDV"`. `TranslationText` is a plain
`{ text: String, displayText: String }` struct. Neither `FeedEngine` nor
`ContentStore` needs to change — they operate on whole `Verse` values and are
indifferent to what is inside `translations`.

`UserState` (SwiftData) gains `preferredTranslationRaw: String`, defaulting
to `"KJV"`, with a computed `preferredTranslation: Translation` property
mirroring the existing `topics`/`topicsRaw` pattern. `LibraryView` gains a
translation picker in its toolbar, next to "Edit topics"; `VerseCard` reads
`verse.translations[state.preferredTranslation]?.displayText`. The validator
(below) guarantees every one of the 600 verses carries all three
translations, so this lookup cannot fail in a correctly built
`feed_verses.json` — the code still falls back to the KJV entry if it
somehow does, as defensive hardening only, not a designed behavior a user
is meant to encounter.

### Content pipeline

Vendored alongside `data/source/KJV.json`:

- `data/source/BSB.json` — same schema, same 66-book array order as KJV.
  Zero mismatches confirmed; paired by array index exactly like KJV is today.
- `data/source/CPDV.json` — same schema, 78 books, Old Testament interleaved
  with the deuterocanon in traditional order. Paired by normalized book name
  (reusing the existing `_normalize_book_name` Roman-numeral/suffix handling
  already in `tools/validate_feed.py`), not by array index.

New curated file, `data/curation/cpdv_verse_map.json`:

```json
{ "PSA.23.1": {"chapter": 22, "verse": 1}, "...": "..." }
```

One entry per one of the 600 selected ids, giving CPDV's own (chapter, verse)
for that content. For the 470 unaffected ids this equals the Protestant
(chapter, verse) — included explicitly rather than assumed, so the map is a
complete, single source of truth with no implicit fallback rule to keep in
sync elsewhere. The 130 affected entries are populated by reading real CPDV
text against the real KJV text for that id, the same discipline the KJV
superscription tables were built with.

`tools/build_feed.py` extends to read all three source files and the CPDV
map, emitting the `translations` object per verse. BSB requires no per-verse
table — straight (book, chapter, verse) lookup, matching how KJV is read
today. Each translation keeps its own independent `SUPERSCRIPTIONS` /
`TRAILING_MARKERS` tables and its own `HEADING_HINT` safety net (headings are
worded differently translation to translation even for the same psalm, so
KJV's existing tables are not reused for BSB or CPDV) — a verse whose text
looks like it carries a heading or trailing marker without a matching entry
in that translation's own table fails the build, exactly as KJV's guard
already does today. CPDV's headed Psalms are the one case that needs no
stripping at all: `cpdv_verse_map.json` already points each id at the
correct content-bearing verse directly (see above), since CPDV keeps the
heading as its own separate verse rather than folding it into verse 1.

`tools/validate_feed.py` extends to check every verse has all three
translations, each with non-empty `text` and a `displayText` that is a
contiguous substring of its own `text` (the existing rule, applied
per-translation rather than once). A new check verifies BSB and the 470
unaffected CPDV entries actually resolve to real verses in their source file
(id-and-count sanity, not content correctness — content correctness for the
130 affected CPDV entries is established once, by hand, when
`cpdv_verse_map.json` is built, and is not re-derived at build time).

### UI

`LibraryView`'s toolbar gains a `Menu` or `Picker` alongside "Edit topics",
listing the three translations by name; selecting one calls
`state.setPreferredTranslation(_:)` and the change is visible the moment the
sheet closes, since `VerseCard` reads the current preference live.

## Testing

- `BibleFeedKit`: a decode test confirming a `Verse` with all three
  translations round-trips correctly, and that an unknown translation key
  fails to decode (mirroring the existing `Topic` strict-decode test).
- Python: a new test file for the CPDV verse map — every entry resolves
  against the real `CPDV.json`, and the map has exactly 600 entries with no
  duplicate or missing ids relative to `selection.json`.
- `validate_feed.py`'s existing test suite gains the per-translation
  completeness checks described above, run against the real shipped file as
  the existing `ShippedSelectionTests`-style tests already do.
- On-device: switch translation in Settings, confirm the feed's currently
  visible card updates; spot-check several of the 130 remapped ids on screen
  against their real CPDV text.

## Out of scope

Per-card translation switching · showing more than one translation on a card
at once · any translation beyond these three · changing the default
translation for existing users · CPDV/BSB support for `data/candidates/` or
any verse outside the current 600 (a later expansion re-runs this same
verification discipline for whatever new ids it adds).
