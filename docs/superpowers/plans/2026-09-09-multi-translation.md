# Multi-Translation Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship BSB and CPDV alongside the existing KJV, with a translation picker in the Library, and every one of the app's 600 verses correct in all three.

**Architecture:** Each verse's shipped record gains a `translations` object holding KJV, BSB and CPDV text side by side; the app's `Verse` model and `VerseCard` read whichever the user has picked. BSB pairs with the existing content by (book, chapter, verse) exactly like KJV. CPDV cannot: its Psalms use the historic Vulgate/Septuagint numbering, which this investigation confirmed diverges from Protestant numbering for 130 of the app's 600 verses (107 of them Psalms) — those 130 get a hand-verified reference table; the other 470 get a direct lookup.

**Tech Stack:** Swift 6.3 (BibleFeedKit package), Python 3.9.6 stdlib (content pipeline), SwiftUI/SwiftData (app).

## Global Constraints

- Xcode project: iOS 26.4 deployment target, Xcode 26.4, Swift 6.3. Build with
  `xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` is enabled — any Swift file
  directly accessing a `BibleFeedKit` member needs its own `import BibleFeedKit`.
- Python is 3.9.6 at `/usr/bin/python3`. No pytest, no third-party dependencies,
  no pip. Tests use stdlib `unittest`. No syntax requiring Python 3.10+.
- `BibleFeedKit` imports neither SwiftUI nor SwiftData.
- Verse text for every translation is verbatim from its vendored source, never
  hand-typed. `displayText` is validated as an exact contiguous substring of
  `text`, per translation.
- The 600-entry `data/curation/selection.json` and 600-entry
  `data/curation/contexts.json` are frozen — this plan reads them, never edits
  them. `context`, `topics`, `tier` and `reference` stay translation-independent.
- The reference label shown on a card is always the Protestant reference
  (e.g. "Psalms 23:1"), regardless of which translation's text is displayed.
- Default translation stays KJV for every user, existing and new.
- Every task ends with a commit. Work happens on branch `feature/multi-translation`.
- Never run `git add -A` or `git add .` on this branch — the working tree has
  the user's own unrelated, uncommitted Xcode changes (app icon assets).
  Stage only the exact files each task names.

---

## File Structure

| Path | Responsibility |
|---|---|
| `data/source/BSB.json` | Vendored Berean Standard Bible (already 66-book, index-aligned with the Protestant canon — no mapping needed). |
| `data/source/CPDV.json` | Vendored Catholic Public Domain Version (78 books, Old Testament interleaved with the deuterocanon — paired by name, not index). |
| `tools/bible_source.py` | Shared book-pairing and index-building helpers, extracted from `validate_feed.py`'s existing KJV-only logic so KJV, BSB and CPDV all read through one implementation. |
| `tools/cpdv_psalm_offsets.py` | The verified Psalms chapter-resolution function (KJV chapter/verse → CPDV chapter/verse), covering the two chapter-merges, one 2-way split, and the five long-heading chapters this investigation found. |
| `data/curation/cpdv_verse_map.json` | One entry per one of the 600 selected ids: CPDV's own `{chapter, verse}` for that content. Hand-verified for the 130 affected ids. |
| `tools/build_feed.py` | Extended to read all three sources and emit `translations` per verse. |
| `tools/validate_feed.py` | Extended to check all three translations per verse. |
| `packages/BibleFeedKit/Sources/BibleFeedKit/Verse.swift` | `Verse` gains `translations: [Translation: TranslationText]`, replacing the flat `text`/`displayText` fields. |
| `BibleApp/BibleApp/State/UserState.swift` | Gains `preferredTranslation`. |
| `BibleApp/BibleApp/Views/VerseCard.swift` | Gains a `translation` parameter. |
| `BibleApp/BibleApp/Views/LibraryView.swift` | Gains a translation picker in its toolbar. |

---

## Phase 1 — Restructure the schema (KJV only, regression-free)

### Task 1: `Translation` enum and multi-translation `Verse`

**Files:**
- Modify: `packages/BibleFeedKit/Sources/BibleFeedKit/Verse.swift`
- Modify: `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Translation` (String-backed Codable enum, cases `kjv`, `bsb`, `cpdv`, raw values `"KJV"`, `"BSB"`, `"CPDV"`), `TranslationText` (`{ text: String, displayText: String }`), `Verse.translations: [Translation: TranslationText]`. Every later Swift task reads through this.

- [ ] **Step 1: Write the failing test**

Replace `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseTests.swift` with:

```swift
import Testing
import Foundation
@testable import BibleFeedKit

private let sampleJSON = """
{
  "schemaVersion": 1,
  "contentVersion": "test",
  "verses": [
    {
      "id": "JHN.3.16", "reference": "John 3:16",
      "book": "JHN", "chapter": 3, "verse": 16,
      "translations": {
        "KJV": { "text": "A Psalm of David. For God so loved the world",
                 "displayText": "For God so loved the world" },
        "BSB": { "text": "For God so loved the world (BSB)",
                 "displayText": "For God so loved the world (BSB)" },
        "CPDV": { "text": "For God so loved the world (CPDV)",
                  "displayText": "For God so loved the world (CPDV)" }
      },
      "context": "Jesus said this at night to a religious leader.",
      "topics": ["love", "hope"], "tier": 1
    }
  ]
}
""".data(using: .utf8)!

@Test func decodesFeedContent() throws {
    let content = try JSONDecoder().decode(FeedContent.self, from: sampleJSON)
    #expect(content.schemaVersion == 1)
    #expect(content.verses.count == 1)
    let verse = content.verses[0]
    #expect(verse.id == "JHN.3.16")
    #expect(verse.topics == [.love, .hope])
    #expect(verse.tier == 1)
    #expect(verse.translations[.kjv]?.displayText == "For God so loved the world")
    #expect(verse.translations[.bsb]?.displayText == "For God so loved the world (BSB)")
    #expect(verse.translations[.cpdv]?.displayText == "For God so loved the world (CPDV)")
    // displayText is the card-facing form; text keeps the source prefix.
    #expect(verse.translations[.kjv]!.text.hasSuffix(verse.translations[.kjv]!.displayText))
}

@Test func topicHasTwelveCases() {
    #expect(Topic.allCases.count == 12)
}

@Test func translationHasThreeCases() {
    #expect(Translation.allCases.count == 3)
}

@Test func unknownTopicFailsDecoding() {
    let bad = """
    {"schemaVersion":1,"contentVersion":"t","verses":[
      {"id":"A.1.1","reference":"A 1:1","book":"A","chapter":1,"verse":1,
       "translations":{"KJV":{"text":"x","displayText":"x"}},
       "context":"y","topics":["prosperity"],"tier":1}]}
    """.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(FeedContent.self, from: bad)
    }
}

@Test func unknownTranslationKeyFailsDecoding() {
    let bad = """
    {"schemaVersion":1,"contentVersion":"t","verses":[
      {"id":"A.1.1","reference":"A 1:1","book":"A","chapter":1,"verse":1,
       "translations":{"NIV":{"text":"x","displayText":"x"}},
       "context":"y","topics":["hope"],"tier":1}]}
    """.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(FeedContent.self, from: bad)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && swift test --package-path packages/BibleFeedKit`
Expected: FAIL — `cannot find 'Translation' in scope` (and `Verse` has no member `translations`).

- [ ] **Step 3: Write minimal implementation**

Replace `packages/BibleFeedKit/Sources/BibleFeedKit/Verse.swift` with:

```swift
import Foundation

public enum Topic: String, Codable, CaseIterable, Sendable, Hashable {
    case anxiety, hope, love, forgiveness, strength, guidance
    case peace, doubt, purpose, gratitude, grief, worth
}

/// A translation the feed can render a card in. Raw values are the exact
/// keys used in `feed_verses.json`'s per-verse `translations` object.
public enum Translation: String, Codable, CaseIterable, Sendable, Hashable {
    case kjv = "KJV"
    case bsb = "BSB"
    case cpdv = "CPDV"

    /// Display name for the Settings/Library picker.
    public var displayName: String {
        switch self {
        case .kjv: return "King James Version"
        case .bsb: return "Berean Standard Bible"
        case .cpdv: return "Catholic Public Domain Version"
        }
    }
}

public struct TranslationText: Codable, Hashable, Sendable {
    public let text: String
    public let displayText: String

    public init(text: String, displayText: String) {
        self.text = text
        self.displayText = displayText
    }
}

public struct Verse: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let reference: String
    public let book: String
    public let chapter: Int
    public let verse: Int
    public let translations: [Translation: TranslationText]
    public let context: String
    public let topics: [Topic]
    public let tier: Int

    public init(id: String, reference: String, book: String, chapter: Int,
                verse: Int, translations: [Translation: TranslationText],
                context: String, topics: [Topic], tier: Int) {
        self.id = id
        self.reference = reference
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.translations = translations
        self.context = context
        self.topics = topics
        self.tier = tier
    }
}

public struct FeedContent: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let verses: [Verse]
}
```

Note: `[Translation: TranslationText]` decodes correctly from a JSON object
whose keys are `Translation`'s raw values, because `Translation` is
`RawRepresentable` by `String` — `Dictionary`'s `Codable` conformance uses
that automatically. The dropped top-level `translation: String` field (which
named "KJV" as if it were the only one) is removed; nothing reads it after
this task.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && swift test --package-path packages/BibleFeedKit`
Expected: PASS, 5 tests in this file (26 total in the package — the pre-existing `FeedEngineTests`/`StreakCalculatorTests` still reference `Verse` — see the note below).

- [ ] **Step 5: Fix the other test files' `Verse` construction**

`packages/BibleFeedKit/Tests/BibleFeedKitTests/FeedEngineTests.swift` has a
`verse(_:tier:topics:)` helper that constructs `Verse` with the old flat
`text`/`displayText` parameters. Find it and replace:

```swift
private func verse(_ id: String, tier: Int, topics: [Topic] = [.hope]) -> Verse {
    Verse(id: id, reference: id, book: "PSA", chapter: 1, verse: 1,
          text: "text", displayText: "text", context: "context",
          topics: topics, tier: tier)
}
```

with:

```swift
private func verse(_ id: String, tier: Int, topics: [Topic] = [.hope]) -> Verse {
    Verse(id: id, reference: id, book: "PSA", chapter: 1, verse: 1,
          translations: [.kjv: TranslationText(text: "text", displayText: "text")],
          context: "context", topics: topics, tier: tier)
}
```

- [ ] **Step 6: Run the full package suite**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && swift test --package-path packages/BibleFeedKit`
Expected: PASS, all tests (20 pre-existing + 5 new − 1 removed for the dropped `translation` field assertion, if any referenced it — check `decodesFeedContent`'s old assertions are gone, replaced by the version above).

- [ ] **Step 7: Commit**

```bash
git add packages/BibleFeedKit/Sources/BibleFeedKit/Verse.swift packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseTests.swift packages/BibleFeedKit/Tests/BibleFeedKitTests/FeedEngineTests.swift
git commit -m "Restructure Verse to hold multiple translations"
```

---

### Task 2: Restructure `build_feed.py` and `validate_feed.py` for the new schema (KJV only)

**Files:**
- Modify: `tools/build_feed.py`
- Modify: `tools/validate_feed.py`
- Modify: `tools/test_validate_feed.py`
- Modify: `tools/fixtures/valid_feed.json`
- Modify: `tools/fixtures/invalid_feed.json`

**Interfaces:**
- Consumes: `data/curation/selection.json`, `data/curation/contexts.json`, `data/source/KJV.json` (unchanged).
- Produces: `feed_verses.json` verses now shaped `{"id", "reference", "book", "chapter", "verse", "translations": {"KJV": {"text","displayText"}}, "context", "topics", "tier"}` — no more top-level `translation` field, no more flat `text`/`displayText`. This is the schema Task 1's Swift decoder expects. Task 5/9/11 add `"BSB"`/`"CPDV"` keys to the same `translations` object.

This task is a pure reshaping of KJV's existing output — the marker tables
(`SUPERSCRIPTIONS`, `TRAILING_MARKERS`, `HEADING_HINT`, `display_text_for`)
and their exact values are unchanged, only where their output lands in the
JSON changes.

- [ ] **Step 1: Update the fixtures to the new shape**

Replace `tools/fixtures/valid_feed.json` with:

```json
{
  "schemaVersion": 1,
  "contentVersion": "test",
  "verses": [
    {
      "id": "JHN.3.16", "reference": "John 3:16",
      "book": "JHN", "chapter": 3, "verse": 16,
      "translations": {
        "KJV": {
          "text": "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.",
          "displayText": "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."
        }
      },
      "context": "Jesus said this at night to a religious leader who came to him in secret, afraid of being seen asking questions.",
      "topics": ["love", "hope"], "tier": 1
    }
  ]
}
```

Replace `tools/fixtures/invalid_feed.json` with:

```json
{
  "schemaVersion": 1,
  "contentVersion": "test",
  "verses": [
    {
      "id": "JHN.3.16", "reference": "John 3:16",
      "book": "JHN", "chapter": 3, "verse": 16,
      "translations": {
        "KJV": {
          "text": "For God so loved the world that he gave his only Son.",
          "displayText": "Something never found in the verse."
        }
      },
      "context": "Too short.",
      "topics": ["love", "prosperity"], "tier": 1
    }
  ]
}
```

- [ ] **Step 2: Update `validate_feed.py`'s tests for the new shape**

`tools/test_validate_feed.py` has two tests (`test_accepts_stripped_leading_superscription`,
`test_accepts_stripped_trailing_colophon`) that build a mutated copy of the
fixture's single verse. Find them and replace the entry-mutation target —
where they currently do `doc["verses"][0] = {...}` with flat `text`/`displayText`
keys, change to the nested shape. The `PSA.23.1` case becomes:

```python
        doc["verses"][0] = {
            "id": "PSA.23.1", "reference": "Psalms 23:1",
            "book": "PSA", "chapter": 23, "verse": 1,
            "translations": {
                "KJV": {
                    "text": "A Psalm of David. The Lord is my shepherd; I shall not want.",
                    "displayText": "The Lord is my shepherd; I shall not want.",
                }
            },
            "context": "David compares God to a shepherd who provides and protects.",
            "topics": ["peace", "hope"], "tier": 1,
        }
```

and the `HAB.3.19` case becomes:

```python
        doc["verses"][0] = {
            "id": "HAB.3.19", "reference": "Habakkuk 3:19",
            "book": "HAB", "chapter": 3, "verse": 19,
            "translations": {
                "KJV": {
                    "text": ("The Lord God is my strength, and he will make my feet like "
                             "hinds’ feet, and he will make me to walk upon mine high "
                             "places. To the chief singer on my stringed instruments."),
                    "displayText": ("The Lord God is my strength, and he will make my "
                                     "feet like hinds’ feet, and he will make me "
                                     "to walk upon mine high places."),
                }
            },
            "context": "Habakkuk ends his book declaring trust in God despite hardship.",
            "topics": ["strength", "hope"], "tier": 2,
        }
```

Every other test in the file references `FIX / "valid_feed.json"` or
`FIX / "invalid_feed.json"` directly — those pick up the Step 1 fixture
changes automatically, no per-test edit needed.

- [ ] **Step 3: Rewrite `validate_feed.py`'s per-entry checks for the nested shape**

In `tools/validate_feed.py`, the per-entry loop currently reads
`entry.get("text")` and `entry.get("displayText")` directly. Replace the
block from `key = (entry.get("book")...` through the `displayText` checks
with:

```python
        key = (entry.get("book"), entry.get("chapter"), entry.get("verse"))
        translations = entry.get("translations")
        if not isinstance(translations, dict) or not translations:
            errors.append(f"{vid}: translations is missing or empty")
            translations = {}

        for code in TRANSLATIONS:
            t = translations.get(code)
            if t is None:
                errors.append(f"{vid}: missing translation {code}")
                continue
            if not isinstance(t, dict):
                errors.append(f"{vid}: translation {code} is not an object")
                continue
            text = t.get("text")
            display = t.get("displayText")
            if code == "KJV":
                if key not in index:
                    errors.append(f"{vid}: no such verse in KJV source")
                elif text != index[key]:
                    errors.append(f"{vid}: KJV text does not match KJV source")
            if display is None:
                errors.append(f"{vid}: {code} displayText is missing")
            elif not isinstance(display, str) or not display.strip():
                errors.append(f"{vid}: {code} displayText is empty")
            elif not isinstance(text, str) or display not in text:
                # Substring, not suffix: most strips remove a leading superscription,
                # but some verses remove a trailing colophon instead.
                errors.append(f"{vid}: {code} displayText is not part of {code} text")

        unknown_codes = set(translations) - TRANSLATIONS
        if unknown_codes:
            errors.append(f"{vid}: unknown translation code(s) {sorted(unknown_codes)}")
```

Add the constant near the top of the file, alongside `TOPICS`:

```python
TRANSLATIONS = {"KJV", "BSB", "CPDV"}
```

This task only ever populates `"KJV"` in `translations`, so `TRANSLATIONS`
being `{"KJV", "BSB", "CPDV"}` means every fixture and every real verse will
report `missing translation BSB` / `missing translation CPDV` until Tasks 5
and 11 add them — that is expected and correct for this task; do not narrow
`TRANSLATIONS` to just `{"KJV"}` to make it pass early, since the whole point
is that the validator already enforces the target end-state.

**This makes the fixtures from Step 1 fail** (they only carry `"KJV"`). Update
`tools/fixtures/valid_feed.json` to a shape that stays valid for this task's
scope, by loosening what "valid" means here: temporarily add empty-but-present
BSB/CPDV entries is wrong (they'd fail displayText-empty checks) — instead,
narrow `TRANSLATIONS` to `{"KJV"}` for now with a comment marking it will grow,
which is simpler and honest about this task's actual scope:

```python
# Grows to {"KJV", "BSB", "CPDV"} as Tasks 5 and 11 add those translations.
TRANSLATIONS = {"KJV"}
```

- [ ] **Step 4: Run the validator's test suite**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -m unittest discover -s tools -p 'test_validate_feed.py' -v`
Expected: FAIL initially (fixtures/tests reference the new shape, `validate_feed.py` still reads the old flat shape) — this confirms the test drives the implementation. After Step 3's rewrite, re-run:
Expected: PASS, all tests in this file.

- [ ] **Step 5: Rewrite `build_feed.py`'s emission for the nested shape**

In `tools/build_feed.py`, replace the `verses.append({...})` block inside
`main()` with:

```python
        verse_text = text[(book, chapter, verse)]
        verses.append({
            "id": entry["id"],
            "reference": f"{names[book]} {chapter}:{verse}",
            "book": book, "chapter": chapter, "verse": verse,
            "translations": {
                "KJV": {
                    "text": verse_text,
                    "displayText": display_text_for(entry["id"], verse_text),
                },
            },
            "context": contexts[entry["id"]],
            "topics": entry["topics"],
            "tier": entry["tier"],
        })
```

And replace the final `doc = {...}` line:

```python
    doc = {"schemaVersion": 1, "contentVersion": CONTENT_VERSION, "verses": verses}
```

(dropping the old `"translation": "KJV"` top-level field entirely).

Bump the version constant, since the shape is changing:

```python
CONTENT_VERSION = "2026-09-09.1"
```

- [ ] **Step 6: Rebuild and validate**

Run:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp
/usr/bin/python3 tools/build_feed.py
/usr/bin/python3 tools/validate_feed.py BibleApp/BibleApp/Resources/feed_verses.json
```
Expected: `wrote 600 verses to BibleApp/BibleApp/Resources/feed_verses.json`, then `0 error(s)`.

- [ ] **Step 7: Run the full Python suite**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -m unittest discover -s tools -p 'test_*.py' -v`
Expected: PASS, all tests (`test_build_feed.py` also constructs fixture verses
with the old flat shape in its own tests for `display_text_for` — that
function's signature is unchanged (`display_text_for(vid, text) -> str`), so
`test_build_feed.py` needs no changes here).

- [ ] **Step 8: Commit**

```bash
git add tools/build_feed.py tools/validate_feed.py tools/test_validate_feed.py tools/fixtures/valid_feed.json tools/fixtures/invalid_feed.json BibleApp/BibleApp/Resources/feed_verses.json
git commit -m "Restructure feed_verses.json to a per-translation schema (KJV only)"
```

---

### Task 3: Wire the app to the new schema (still KJV-only, hardcoded)

**Files:**
- Modify: `BibleApp/BibleApp/Views/VerseCard.swift`
- Modify: `BibleApp/BibleApp/Views/FeedView.swift`
- Modify: `BibleApp/BibleApp/Views/LibraryView.swift`

**Interfaces:**
- Consumes: `Verse.translations`, `Translation` from Task 1.
- Produces: `VerseCard(verse:translation:isSaved:onSave:)`. Task 6 replaces the
  hardcoded `.kjv` call sites with `state.preferredTranslation`.

This task only makes the app compile and run correctly against Task 2's
rebuilt `feed_verses.json` — it does not add any translation-switching UI yet
(Task 6 does). Every call site passes `.kjv` explicitly.

- [ ] **Step 1: `VerseCard` reads through a translation parameter**

In `BibleApp/BibleApp/Views/VerseCard.swift`, add a `translation` property and
change the text lookup:

```swift
struct VerseCard: View {
    let verse: Verse
    let translation: Translation
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            Text(verse.translations[translation]?.displayText ?? "")
                .font(.system(.title2, design: .serif))
                .lineSpacing(6)
```

Leave the rest of the file (reference, context, topics, save button) unchanged.

- [ ] **Step 2: `FeedView` passes `.kjv` for now**

In `BibleApp/BibleApp/Views/FeedView.swift`, update the `VerseCard(...)` call:

```swift
                ForEach(queue) { verse in
                    VerseCard(verse: verse,
                              translation: .kjv,
                              isSaved: state.savedSet.contains(verse.id),
                              onSave: { state.toggleSaved(verse.id) })
```

- [ ] **Step 3: `LibraryView` reads through the same lookup**

In `BibleApp/BibleApp/Views/LibraryView.swift`, change:

```swift
                                Text(verse.displayText)
                                    .font(.system(.body, design: .serif))
```

to:

```swift
                                Text(verse.translations[.kjv]?.displayText ?? "")
                                    .font(.system(.body, design: .serif))
```

- [ ] **Step 4: Build and run on the simulator**

Run:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

Launch on the simulator (fresh install or existing state), confirm the feed
still shows verse text exactly as before this task — no visible behavior
change, since only the plumbing changed and every call site still names
`.kjv`.

- [ ] **Step 5: Commit**

```bash
git add BibleApp/BibleApp/Views/VerseCard.swift BibleApp/BibleApp/Views/FeedView.swift BibleApp/BibleApp/Views/LibraryView.swift
git commit -m "Wire app views to the multi-translation Verse schema (KJV hardcoded)"
```

---

## Phase 2 — Add BSB

### Task 4: Extract `tools/bible_source.py`, refactor `validate_feed.py` to use it

**Files:**
- Create: `tools/bible_source.py`
- Create: `tools/test_bible_source.py`
- Modify: `tools/validate_feed.py`

**Interfaces:**
- Consumes: `data/source/KJV.json`, `BibleApp/BibleApp/Resources/bible_books.json` (unchanged).
- Produces: `normalize_book_name(name) -> str`, `load_protestant_books() -> list[dict]`,
  `SourceDataError` (moved here from `validate_feed.py`),
  `load_source_by_index(path) -> dict[(book_id, chapter, verse), text]` (KJV/BSB),
  `load_source_by_name(path) -> dict[book_id, dict]` (raw per-book source data,
  keyed by protestant book id, for CPDV's own chapter/verse numbers — Task 8
  reads this). Task 5 and Task 9 both import this module; neither KJV nor BSB
  loading logic should be written twice.

This is a pure extraction — `validate_feed.py`'s existing behavior and error
messages do not change, only where the code lives. Existing tests must pass
unmodified.

- [ ] **Step 1: Write the failing test**

Create `tools/test_bible_source.py`:

```python
import pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import normalize_book_name, load_protestant_books, load_source_by_index, SourceDataError

ROOT = pathlib.Path(__file__).resolve().parent.parent


class NormalizeBookNameTests(unittest.TestCase):
    def test_roman_numeral_prefix(self):
        self.assertEqual(normalize_book_name("II Kings"), "2 Kings")
        self.assertEqual(normalize_book_name("I Samuel"), "1 Samuel")
        self.assertEqual(normalize_book_name("III John"), "3 John")

    def test_of_john_suffix(self):
        self.assertEqual(normalize_book_name("Revelation of John"), "Revelation")

    def test_unaffected_name_unchanged(self):
        self.assertEqual(normalize_book_name("Genesis"), "Genesis")

    def test_none_and_empty(self):
        self.assertEqual(normalize_book_name(None), "")
        self.assertEqual(normalize_book_name(""), "")


class LoadProtestantBooksTests(unittest.TestCase):
    def test_returns_66_books_in_order(self):
        books = load_protestant_books()
        self.assertEqual(len(books), 66)
        self.assertEqual(books[0]["id"], "GEN")
        self.assertEqual(books[-1]["id"], "REV")


class LoadSourceByIndexTests(unittest.TestCase):
    def test_loads_real_kjv(self):
        index = load_source_by_index(ROOT / "data" / "source" / "KJV.json")
        self.assertEqual(len(index), 31102)
        self.assertEqual(index[("JHN", 3, 16)],
                          "For God so loved the world, that he gave his only "
                          "begotten Son, that whosoever believeth in him should "
                          "not perish, but have everlasting life.")

    def test_missing_file_raises_source_data_error(self):
        with self.assertRaises(SourceDataError):
            load_source_by_index(ROOT / "data" / "source" / "NOPE.json")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -m unittest discover -s tools -p 'test_bible_source.py' -v`
Expected: ERROR — `ModuleNotFoundError: No module named 'bible_source'`

- [ ] **Step 3: Write the shared module**

Create `tools/bible_source.py`:

```python
"""Shared helpers for reading the vendored Bible source JSON files (KJV,
BSB, CPDV, ...) and pairing their books against the 66-book Protestant
canon in BibleApp/BibleApp/Resources/bible_books.json.

Two pairing strategies exist because the sources are not laid out the same
way. KJV and BSB list exactly the 66 Protestant books, in Protestant order,
so they pair by array index. CPDV lists 78 books with the deuterocanon
interleaved through the Old Testament in traditional Catholic order, so it
must pair by (normalized) book name instead -- see load_source_by_name.
"""
import json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
BOOKS = ROOT / "BibleApp" / "BibleApp" / "Resources" / "bible_books.json"

# bible_books.json uses Arabic-numeral prefixes ("1 Samuel", "2 Kings") and a
# bare "Revelation"; several vendored sources use Roman-numeral prefixes
# ("I Samuel", "II Kings") and "Revelation of John". Both name a book title
# -> a normalized form so the two conventions compare equal without masking
# a genuine mismatch (e.g. a transposed book pair).
_ROMAN_PREFIX = {"I": "1", "II": "2", "III": "3"}


def normalize_book_name(name):
    name = (name or "").strip()
    parts = name.split(" ", 1)
    if len(parts) == 2 and parts[0] in _ROMAN_PREFIX:
        name = f"{_ROMAN_PREFIX[parts[0]]} {parts[1]}"
    if name.endswith(" of John"):
        name = name[: -len(" of John")]
    return name


class SourceDataError(Exception):
    """Raised when a vendored source file or bible_books.json fails a
    structural sanity check (missing file, malformed JSON, book count,
    chapter count, or book identity). Callers must catch this and report it
    as a validation error rather than let it propagate."""


def load_protestant_books():
    """Return the 66 canon == 'protestant' entries from bible_books.json,
    in their existing order (Genesis..Revelation)."""
    try:
        meta = json.loads(BOOKS.read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise SourceDataError(f"failed to read or parse {BOOKS}: {e}")
    return [b for b in meta["books"] if b["canon"] == "protestant"]


def load_source_by_index(path):
    """Load a source whose `books` array is already index-aligned with the
    66 protestant books (KJV, BSB). Returns
    {(book_id, chapter, verse): normalized_text}."""
    prot = load_protestant_books()
    try:
        data = json.loads(pathlib.Path(path).read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise SourceDataError(f"failed to read or parse {path}: {e}")

    if len(prot) != len(data["books"]):
        raise SourceDataError(
            f"book count mismatch: bible_books.json has {len(prot)} "
            f"protestant books, {path} has {len(data['books'])} books")

    index = {}
    for i, book in enumerate(prot):
        src = data["books"][i]
        if len(src["chapters"]) != book["chapters"]:
            raise SourceDataError(
                f"{path}: source/book chapter-count mismatch at {book['id']}")
        if normalize_book_name(src.get("name")) != normalize_book_name(book["name"]):
            raise SourceDataError(
                f"{path}: source/book identity mismatch at position {i} "
                f"(id {book['id']}): bible_books.json name {book['name']!r} "
                f"vs source name {src.get('name')!r}")
        for ch in src["chapters"]:
            for v in ch["verses"]:
                key = (book["id"], int(ch["chapter"]), int(v["verse"]))
                index[key] = re.sub(r"\s+", " ", v["text"]).strip()
    return index


def load_source_by_name(path):
    """Load a source whose books must be paired by normalized name rather
    than array index (CPDV, whose deuterocanon is interleaved through the
    Old Testament). Returns {book_id: raw_book_dict}, keyed by the
    protestant book id -- callers resolve chapter/verse themselves, since a
    name-paired source's own chapter/verse numbers do not always equal the
    protestant ones (see tools/cpdv_psalm_offsets.py for Psalms)."""
    prot = load_protestant_books()
    try:
        data = json.loads(pathlib.Path(path).read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise SourceDataError(f"failed to read or parse {path}: {e}")

    by_name = {normalize_book_name(b.get("name")): b for b in data["books"]}
    out = {}
    for book in prot:
        src = by_name.get(normalize_book_name(book["name"]))
        if src is None:
            raise SourceDataError(
                f"{path}: no book matching {book['name']!r} (id {book['id']})")
        out[book["id"]] = src
    return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -m unittest discover -s tools -p 'test_bible_source.py' -v`
Expected: PASS, 6 tests.

- [ ] **Step 5: Refactor `validate_feed.py` to use the shared module**

In `tools/validate_feed.py`, remove the now-duplicated `_ROMAN_PREFIX`,
`_normalize_book_name`, `SourceDataError`, and `_kjv_index` — replace the
top of the file through `_kjv_index`'s definition with:

```python
#!/usr/bin/env python3
"""Validate a built feed_verses.json against the vendored translation sources."""
import json, pathlib, sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import SourceDataError, load_source_by_index

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "data" / "source" / "KJV.json"

TOPICS = {"anxiety", "hope", "love", "forgiveness", "strength", "guidance",
          "peace", "doubt", "purpose", "gratitude", "grief", "worth"}
CONTEXT_MIN, CONTEXT_MAX = 60, 220
# Grows to {"KJV", "BSB", "CPDV"} as Tasks 5 and 11 add those translations.
TRANSLATIONS = {"KJV"}


def _kjv_index():
    return load_source_by_index(SOURCE)
```

Everything from `def validate_feed(path):` onward is unchanged (it already
calls `_kjv_index()` and catches `SourceDataError`, both of which still
exist with the same names/behavior, just imported rather than defined
locally).

- [ ] **Step 6: Run the full test suite**

Run:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp
/usr/bin/python3 -m unittest discover -s tools -p 'test_*.py' -v
```
Expected: PASS, every test — this is a pure refactor, no behavior changed.
If `test_validate_feed.py`'s tests for book-identity-mismatch or
chapter-count-mismatch reference `validate_feed.SourceDataError` or
`validate_feed._normalize_book_name` directly (rather than through the
public `validate_feed` function), update those references to import from
`bible_source` instead.

- [ ] **Step 7: Commit**

```bash
git add tools/bible_source.py tools/test_bible_source.py tools/validate_feed.py tools/test_validate_feed.py
git commit -m "Extract shared book-pairing helpers into tools/bible_source.py"
```

---

### Task 5: Vendor BSB, add it to the build and validator

**Files:**
- Create: `data/source/BSB.json` (vendored, not authored)
- Modify: `tools/build_feed.py`
- Modify: `tools/validate_feed.py`
- Modify: `tools/test_build_feed.py`

**Interfaces:**
- Consumes: `tools/bible_source.py`'s `load_source_by_index` (Task 4).
- Produces: `feed_verses.json` verses gain a `"BSB"` key in `translations`.
  `TRANSLATIONS` in `validate_feed.py` grows to `{"KJV", "BSB"}`.

BSB's own superscription/marker prefixes and suffixes are different wording
from KJV's, verified directly against the vendored file for all 19 ids that
carry one in KJV (14 leading, 4 trailing plus PSA.119.105 confirmed to carry
none). Values below are exact, confirmed byte-for-byte with
`text.startswith(prefix)` / `text.endswith(suffix)` against the real file —
transcribe them exactly, including the em dashes and curly quotes.

- [ ] **Step 1: Vendor the source file**

```bash
curl -sL --max-time 60 -o /Users/vietdo/Documents/GitHub/BibleApp/data/source/BSB.json \
  "https://raw.githubusercontent.com/scrollmapper/bible_databases/master/formats/json/BSB.json"
```

Verify it downloaded correctly:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -c "
import json
d = json.load(open('data/source/BSB.json'))
print(d['translation'])
print(len(d['books']), 'books')
print(sum(len(c['verses']) for b in d['books'] for c in b['chapters']), 'verses')
"
```
Expected: `BSB: Berean Standard Bible`, `66 books`, `31102 verses`.

- [ ] **Step 2: Add BSB's marker tables and emission to `build_feed.py`**

In `tools/build_feed.py`, the existing `SUPERSCRIPTIONS`/`TRAILING_MARKERS`/
`HEADING_HINT`/`display_text_for` are all implicitly KJV's. Rename them to
make that explicit, and add BSB's own:

Rename (find-and-replace across the file):
- `SUPERSCRIPTIONS` → `KJV_SUPERSCRIPTIONS`
- `TRAILING_MARKERS` → `KJV_TRAILING_MARKERS`
- `HEADING_HINT` → `KJV_HEADING_HINT`
- `display_text_for` → `kjv_display_text_for` (and update its one call site
  in `main()` to match)

Then add BSB's tables and a generic stripping function, right after the
renamed KJV block:

```python
BSB_SUPERSCRIPTIONS = {
    "PSA.19.1": "For the choirmaster. A Psalm of David. ",
    "PSA.22.1": "For the choirmaster. To the tune of “The Doe of the Dawn.” A Psalm of David. ",
    "PSA.23.1": "A Psalm of David. ",
    "PSA.24.1": "A Psalm of David. ",
    "PSA.27.1": "Of David. ",
    "PSA.32.1": "Of David. A Maskil. ",
    "PSA.42.1": "For the choirmaster. A Maskil of the sons of Korah. ",
    "PSA.46.1": "For the choirmaster. Of the sons of Korah. According to Alamoth. A song. ",
    "PSA.89.1": "A Maskil of Ethan the Ezrahite. ",
    "PSA.90.1": "A prayer of Moses the man of God. ",
    "PSA.121.1": "A song of ascents. ",
    "PSA.127.1": "A song of ascents. Of Solomon. ",
    "PSA.130.1": "A song of ascents. ",
    "PSA.133.1": "A song of ascents. Of David. ",
}

BSB_TRAILING_MARKERS = {
    "HAB.3.19": " For the choirmaster. With stringed instruments.",
    "PSA.62.8": " Selah",
    "PSA.77.9": " Selah",
    "2PE.3.18": " To Him be the glory both now and to the day of eternity. Amen.",
}

BSB_HEADING_HINT = re.compile(
    r"^(?:[^.]{0,140}?(?:Psalm|Maskil|Choirmaster|song of ascents|prayer of)"
    r"[^.]{0,140}?\.\s)"
)


def display_text_for(vid, text, superscriptions, trailing_markers, heading_hint, table_name):
    """Return the card-facing text: `text` minus any known superscription or
    trailing marker for one translation's marker tables."""
    prefix = superscriptions.get(vid)
    if prefix is not None:
        if not text.startswith(prefix):
            raise SystemExit(f"{vid}: {table_name} prefix does not match source text")
        stripped = text[len(prefix):].strip()
        if not stripped:
            raise SystemExit(f"{vid}: stripping the superscription empties {table_name}'s verse")
        return stripped
    suffix = trailing_markers.get(vid)
    if suffix is not None:
        if not text.endswith(suffix):
            raise SystemExit(f"{vid}: {table_name} suffix does not match source text")
        stripped = text[: -len(suffix)].strip()
        if not stripped:
            raise SystemExit(f"{vid}: stripping the trailing marker empties {table_name}'s verse")
        return stripped
    if heading_hint.match(text):
        raise SystemExit(
            f"{vid}: text looks like it carries a heading but is not in "
            f"{table_name} — add it explicitly or confirm it is verse content")
    if text.rstrip().endswith(("Selah", "Selah.")):
        raise SystemExit(f"{vid}: text ends with 'Selah' but is not in {table_name}")
    return text


def kjv_display_text_for(vid, text):
    return display_text_for(vid, text, KJV_SUPERSCRIPTIONS, KJV_TRAILING_MARKERS,
                             KJV_HEADING_HINT, "KJV_SUPERSCRIPTIONS/KJV_TRAILING_MARKERS")


def bsb_display_text_for(vid, text):
    return display_text_for(vid, text, BSB_SUPERSCRIPTIONS, BSB_TRAILING_MARKERS,
                             BSB_HEADING_HINT, "BSB_SUPERSCRIPTIONS/BSB_TRAILING_MARKERS")
```

Note `kjv_display_text_for` is now a thin wrapper delegating to the shared
`display_text_for(vid, text, superscriptions, trailing_markers, heading_hint, table_name)`
— this replaces the old KJV-only `display_text_for`'s body. Delete the old
KJV-specific `display_text_for` function body (the one with the hardcoded
`SUPERSCRIPTIONS.get`/`TRAILING_MARKERS.get`/`HEADING_HINT.match` calls) —
its logic is now the shared parametrized version above.

- [ ] **Step 3: Load BSB and emit it per verse**

At the top of `main()` in `tools/build_feed.py`, add the import and BSB load:

```python
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import load_source_by_index
```

(add this near the top of the file, alongside the existing `import json, pathlib, re, sys`)

Inside `main()`, after the existing KJV `text` index is built, add:

```python
    bsb_text = load_source_by_index(ROOT / "data/source/BSB.json")
```

And in the `verses.append({...})` block, extend the `translations` dict:

```python
        verse_text = text[(book, chapter, verse)]
        bsb_verse_text = bsb_text[(book, chapter, verse)]
        verses.append({
            "id": entry["id"],
            "reference": f"{names[book]} {chapter}:{verse}",
            "book": book, "chapter": chapter, "verse": verse,
            "translations": {
                "KJV": {
                    "text": verse_text,
                    "displayText": kjv_display_text_for(entry["id"], verse_text),
                },
                "BSB": {
                    "text": bsb_verse_text,
                    "displayText": bsb_display_text_for(entry["id"], bsb_verse_text),
                },
            },
            "context": contexts[entry["id"]],
            "topics": entry["topics"],
            "tier": entry["tier"],
        })
```

- [ ] **Step 4: Extend `validate_feed.py` to check BSB too**

In `tools/validate_feed.py`, grow the constant:

```python
TRANSLATIONS = {"KJV", "BSB"}
```

The per-entry loop already iterates `for code in TRANSLATIONS` and only does
the KJV-source-text comparison `if code == "KJV"` — BSB entries get the
displayText/non-empty checks but not a source-text comparison, since
`validate_feed.py` does not (yet) load BSB's own source for comparison. This
is intentionally lighter than KJV's check for now; Task 9 tightens it.

- [ ] **Step 5: Update `test_build_feed.py`'s fixtures for the new function names**

`tools/test_build_feed.py` imports `display_text_for`, `SUPERSCRIPTIONS`,
`TRAILING_MARKERS`, `HEADING_HINT` from `build_feed`. Update the imports:

```python
from build_feed import (kjv_display_text_for, KJV_SUPERSCRIPTIONS,
                         KJV_TRAILING_MARKERS, KJV_HEADING_HINT)
```

And every call in the file to `display_text_for(...)` becomes
`kjv_display_text_for(...)`; every reference to `SUPERSCRIPTIONS`/
`TRAILING_MARKERS`/`HEADING_HINT` becomes `KJV_SUPERSCRIPTIONS`/
`KJV_TRAILING_MARKERS`/`KJV_HEADING_HINT`.

- [ ] **Step 6: Rebuild and validate**

```bash
cd /Users/vietdo/Documents/GitHub/BibleApp
/usr/bin/python3 tools/build_feed.py
/usr/bin/python3 tools/validate_feed.py BibleApp/BibleApp/Resources/feed_verses.json
```
Expected: `wrote 600 verses...`, then `0 error(s)`. If any `SystemExit` fires
during the build (a BSB verse carries a heading not in `BSB_SUPERSCRIPTIONS`),
that is a real signal — read the flagged verse's actual BSB text and add its
exact prefix/suffix to the appropriate table; do not loosen `BSB_HEADING_HINT`
to make the error disappear.

- [ ] **Step 7: Run the full Python suite**

```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -m unittest discover -s tools -p 'test_*.py' -v
```
Expected: PASS, every test.

- [ ] **Step 8: Commit**

```bash
git add data/source/BSB.json tools/build_feed.py tools/validate_feed.py tools/test_build_feed.py BibleApp/BibleApp/Resources/feed_verses.json
git commit -m "Add BSB translation to the shipped feed"
```

---

### Task 6: Translation picker in Settings

**Files:**
- Modify: `BibleApp/BibleApp/State/UserState.swift`
- Modify: `BibleApp/BibleApp/Views/LibraryView.swift`
- Modify: `BibleApp/BibleApp/Views/FeedView.swift`

**Interfaces:**
- Consumes: `Translation` (Task 1), `Verse.translations` (Task 1).
- Produces: `UserState.preferredTranslation: Translation`,
  `UserState.setPreferredTranslation(_:)`. Task 11 needs nothing new here —
  CPDV becomes selectable automatically once Task 11 adds it to `Translation`'s
  already-fixed 3 cases and to the shipped data.

- [ ] **Step 1: `UserState` gains a persisted preference**

In `BibleApp/BibleApp/State/UserState.swift`, add a stored property and a
computed wrapper, following the same pattern `topicsRaw`/`topics` already
uses:

```swift
    var preferredTranslationRaw: String = Translation.kjv.rawValue
```

Add this near the other `var` declarations at the top of the class. Then add
the computed property and setter, near `setTopics`:

```swift
    var preferredTranslation: Translation {
        Translation(rawValue: preferredTranslationRaw) ?? .kjv
    }

    func setPreferredTranslation(_ translation: Translation) {
        preferredTranslationRaw = translation.rawValue
    }
```

- [ ] **Step 2: Build to confirm the model change compiles**

```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Add the picker to `LibraryView`'s toolbar**

In `BibleApp/BibleApp/Views/LibraryView.swift`, add a second leading toolbar
item, alongside the existing "Edit topics" button:

```swift
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(Translation.allCases, id: \.self) { translation in
                            Button {
                                state.setPreferredTranslation(translation)
                            } label: {
                                if translation == state.preferredTranslation {
                                    Label(translation.displayName, systemImage: "checkmark")
                                } else {
                                    Text(translation.displayName)
                                }
                            }
                        }
                    } label: {
                        Text(state.preferredTranslation.rawValue)
                    }
                    .font(.subheadline)
                }
```

This sits alongside (not replacing) the existing "Edit topics" `ToolbarItem`
— both are `.topBarLeading`, SwiftUI stacks them left to right in the order
declared.

Also update the saved-verse row to honor the preference, replacing the
Task 3 hardcoded `.kjv`:

```swift
                                Text(verse.translations[state.preferredTranslation]?.displayText ?? "")
                                    .font(.system(.body, design: .serif))
```

- [ ] **Step 4: `FeedView` reads the live preference**

In `BibleApp/BibleApp/Views/FeedView.swift`, replace the Task 3 hardcoded
`.kjv`:

```swift
                    VerseCard(verse: verse,
                              translation: state.preferredTranslation,
                              isSaved: state.savedSet.contains(verse.id),
                              onSave: { state.toggleSaved(verse.id) })
```

- [ ] **Step 5: Build and verify on the simulator**

```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

On the simulator: open the Library sheet, tap the translation menu (shows
"KJV" initially), select "Berean Standard Bible", close the sheet, confirm
the currently visible feed card's text changed to BSB wording (e.g. Psalm
23:1 now reads "The LORD is my shepherd; I shall lack nothing" rather than
"I shall not want"). Switch back to KJV and confirm it reverts.

- [ ] **Step 6: Commit**

```bash
git add BibleApp/BibleApp/State/UserState.swift BibleApp/BibleApp/Views/LibraryView.swift BibleApp/BibleApp/Views/FeedView.swift
git commit -m "Add translation picker to the Library toolbar"
```

---

## Phase 3 — Add CPDV

### Task 7: Vendor CPDV, extend `bible_source.py`'s name-pairing test coverage

**Files:**
- Create: `data/source/CPDV.json` (vendored, not authored)
- Modify: `tools/test_bible_source.py`

**Interfaces:**
- Consumes: `load_source_by_name` (already written in Task 4).
- Produces: nothing new — this task only adds real-data coverage for the
  function Task 4 already shipped, since Task 4 had no CPDV-shaped file to
  test against yet.

- [ ] **Step 1: Vendor the source file**

```bash
curl -sL --max-time 60 -o /Users/vietdo/Documents/GitHub/BibleApp/data/source/CPDV.json \
  "https://raw.githubusercontent.com/scrollmapper/bible_databases/master/formats/json/CPDV.json"
```

Verify:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -c "
import json
d = json.load(open('data/source/CPDV.json'))
print(d['translation'])
print(len(d['books']), 'books')
"
```
Expected: `CPDV: Catholic Public Domain Version`, `78 books`.

- [ ] **Step 2: Add real-data tests to `tools/test_bible_source.py`**

Append to `tools/test_bible_source.py`:

```python
from bible_source import load_source_by_name


class LoadSourceByNameTests(unittest.TestCase):
    def test_loads_real_cpdv_paired_by_name_not_index(self):
        by_book = load_source_by_name(ROOT / "data" / "source" / "CPDV.json")
        self.assertEqual(len(by_book), 66)
        # CPDV interleaves the deuterocanon through the Old Testament, so its
        # array position for Psalms differs from bible_books.json's — proving
        # this loaded correctly (by name) rather than by coincidence of index.
        psalms = by_book["PSA"]
        self.assertEqual(psalms["name"], "Psalms")
        self.assertEqual(len(psalms["chapters"]), 150)

    def test_esther_pairs_correctly_despite_deuterocanon_between_ezra_and_job(self):
        # Genesis..Nehemiah then Tobit/Judith (deuterocanon) sit before Esther
        # in CPDV's own array order; a naive index pairing would land on the
        # wrong book here. Confirm the real content is Esther's, not Tobit's
        # or Judith's.
        by_book = load_source_by_name(ROOT / "data" / "source" / "CPDV.json")
        self.assertEqual(by_book["EST"]["name"], "Esther")
```

- [ ] **Step 3: Run the test suite**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -m unittest discover -s tools -p 'test_bible_source.py' -v`
Expected: PASS, 8 tests (6 pre-existing + 2 new).

- [ ] **Step 4: Commit**

```bash
git add data/source/CPDV.json tools/test_bible_source.py
git commit -m "Vendor CPDV and add real-data coverage for name-based book pairing"
```

---

### Task 8: `tools/cpdv_psalm_offsets.py` — the verified chapter-resolution function

**Files:**
- Create: `tools/cpdv_psalm_offsets.py`
- Create: `tools/test_cpdv_psalm_offsets.py`

**Interfaces:**
- Consumes: `load_source_by_name` (Task 4/7).
- Produces: `resolve_psalm_verse(kjv_chapter, kjv_verse, kjv_verse_counts, cpdv_verse_counts) -> (cpdv_chapter, cpdv_verse)`.
  Task 9 calls this to generate a starting CANDIDATE for each of the 130
  affected ids — **not** a final answer. This investigation found the naive
  per-chapter delta is right for most chapters but wrong for at least two
  (4 and 56, both confirmed below by reading real text), so Task 9's human
  verification of every one of the 130 is mandatory regardless of what this
  function returns.

CPDV's Psalms diverge from Protestant/KJV numbering in two independent ways,
both confirmed against real text in this session:

1. **Chapter-level**: the historic Vulgate/Septuagint numbering merges KJV
   Psalms 9+10 into one CPDV chapter, merges KJV 114+115 into one, splits KJV
   116 into two, and splits KJV 147 into two — all four confirmed by exact
   verse-count arithmetic AND content reading. Every other chapter maps to
   the *same* CPDV chapter number for KJV chapters 1-8 and 148-150, and to
   CPDV chapter − 1 for KJV chapters 11-113 and 117-146 — but this is only
   the chapter-level pairing, not the verse-level one (see point 2): most
   chapters in the 1-8 range still shift at the verse level within that same
   CPDV chapter.
2. **Verse-level, within a chapter**: many Psalms carry their heading (e.g.
   "Unto the end. A Psalm of David.") as CPDV's own separate verse 1, where
   KJV folds the same heading into verse 1 alongside the first line of
   content — shifting every subsequent verse in that chapter by a constant.
   Confirmed directly against real text: only Psalm 1 and Psalms 148-150
   have zero verse-level shift; Psalms 2 through 8 each shift by +1 for the
   same reason, despite mapping to an unchanged chapter number.

The verse-level shift is USUALLY the constant `(CPDV chapter's verse count)
− (KJV chapter's verse count)`, but not always — Psalms 4 and 56 are
confirmed counter-examples:

- **Psalm 4**: KJV has 8 verses, CPDV chapter 4 has 10 (delta 2 by count).
  Reading the actual text: the delta is +1 for KJV verses 2-7 (CPDV 3-8), but
  KJV verse 8 ("I will both lay me down in peace, and sleep...") is itself
  split across CPDV verses 9 and 10. The content anyone would actually want
  starts at CPDV 4:9.
- **Psalm 56**: KJV and CPDV chapter 55 both have 13 verses (delta 0 by
  count — misleadingly suggesting no shift at all). Reading the actual text:
  KJV verses 2-11 are offset +1 (CPDV 3-12), but KJV verses 12-13 are offset
  +0 (CPDV 12-13) — the count matches only because a compensating
  consolidation happens between KJV verse 11 and 12, not because there is no
  shift.

- [ ] **Step 1: Write the failing test**

Create `tools/test_cpdv_psalm_offsets.py`:

```python
import pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cpdv_psalm_offsets import resolve_psalm_verse
from bible_source import load_source_by_index, load_source_by_name

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _verse_counts(chapters_key_source):
    """{chapter: verse_count} from a book's raw `chapters` list."""
    return {c["chapter"]: len(c["verses"]) for c in chapters_key_source}


class ResolvePsalmVerseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        kjv_index = load_source_by_index(ROOT / "data" / "source" / "KJV.json")
        cpdv_by_book = load_source_by_name(ROOT / "data" / "source" / "CPDV.json")
        # Rebuild per-chapter verse counts directly from the raw sources,
        # since load_source_by_index only gives a flat (book,chapter,verse)->text
        # map, not counts, and CPDV's own chapter/verse numbers are not the
        # protestant ones load_source_by_name resolves against.
        import json
        kjv_raw = json.loads((ROOT / "data" / "source" / "KJV.json").read_text())
        cpdv_raw = json.loads((ROOT / "data" / "source" / "CPDV.json").read_text())
        kjv_psa = next(b for b in kjv_raw["books"] if b["name"] == "Psalms")
        cpdv_psa = next(b for b in cpdv_raw["books"] if b["name"] == "Psalms")
        cls.kjv_counts = _verse_counts(kjv_psa["chapters"])
        cls.cpdv_counts = _verse_counts(cpdv_psa["chapters"])
        cls.kjv_text = {c["chapter"]: {v["verse"]: v["text"] for v in c["verses"]}
                         for c in kjv_psa["chapters"]}
        cls.cpdv_text = {c["chapter"]: {v["verse"]: v["text"] for v in c["verses"]}
                          for c in cpdv_psa["chapters"]}

    def _assert_content_overlaps(self, kjv_ref, cpdv_ref, shared_word):
        kch, kv = kjv_ref
        cch, cv = cpdv_ref
        self.assertIn(shared_word, self.kjv_text[kch][kv].lower())
        self.assertIn(shared_word, self.cpdv_text[cch][cv].lower())

    def test_simple_range_offset_minus_one(self):
        # KJV 23:1 ("The Lord is my shepherd") is the famous anchor point:
        # confirmed by direct reading earlier in this investigation to be
        # CPDV 22:1. No shared-word content check here -- CPDV renders this
        # verse as "The Lord directs me, and nothing will be lacking to me",
        # which shares no vocabulary with KJV's "shepherd" despite being the
        # same verse, so the numeric assertion is the real proof.
        result = resolve_psalm_verse(23, 1, self.kjv_counts, self.cpdv_counts)
        self.assertEqual(result, (22, 1))

    def test_psalm_1_offset_zero(self):
        # Psalm 1 has no musical/authorship heading in either translation,
        # so it is the one chapter in 1-8 with zero verse-level shift too --
        # chapters 2-8 map to an unchanged chapter number but still shift by
        # +1 at the verse level (see the module docstring).
        self.assertEqual(resolve_psalm_verse(1, 1, self.kjv_counts, self.cpdv_counts), (1, 1))

    def test_chapters_148_through_150_offset_zero(self):
        self.assertEqual(resolve_psalm_verse(150, 6, self.kjv_counts, self.cpdv_counts), (150, 6))

    def test_psalm_9_10_merge(self):
        # KJV 9 and 10 both live inside CPDV's single chapter 9. KJV 9:1 folds
        # its heading into verse 1 the way most psalms do; CPDV 9's heading is
        # its own separate verse 1, so content starts at CPDV 9:2.
        self.assertEqual(resolve_psalm_verse(9, 1, self.kjv_counts, self.cpdv_counts), (9, 2))
        self.assertEqual(resolve_psalm_verse(10, 1, self.kjv_counts, self.cpdv_counts), (9, 22))

    def test_psalm_114_115_merge(self):
        self.assertEqual(resolve_psalm_verse(114, 1, self.kjv_counts, self.cpdv_counts), (113, 1))
        self.assertEqual(resolve_psalm_verse(115, 1, self.kjv_counts, self.cpdv_counts), (113, 9))

    def test_psalm_116_split(self):
        self.assertEqual(resolve_psalm_verse(116, 9, self.kjv_counts, self.cpdv_counts), (114, 9))
        self.assertEqual(resolve_psalm_verse(116, 10, self.kjv_counts, self.cpdv_counts), (115, 1))

    def test_psalm_147_split(self):
        self.assertEqual(resolve_psalm_verse(147, 11, self.kjv_counts, self.cpdv_counts), (146, 11))
        self.assertEqual(resolve_psalm_verse(147, 12, self.kjv_counts, self.cpdv_counts), (147, 1))

    def test_psalm_4_known_exception(self):
        # A naive count-based delta (2) is wrong here -- confirmed by reading
        # real text. Verses 2-7 are +1; verse 8 is where content genuinely
        # starts in CPDV 4:9 (its second half spills into CPDV 4:10, but 4:9
        # is where a reader should land).
        self.assertEqual(resolve_psalm_verse(4, 2, self.kjv_counts, self.cpdv_counts), (4, 3))
        self.assertEqual(resolve_psalm_verse(4, 8, self.kjv_counts, self.cpdv_counts), (4, 9))

    def test_psalm_56_known_exception(self):
        # A naive count-based delta (0, since both chapters have 13 verses)
        # is wrong here too -- confirmed by reading real text. +1 through
        # verse 11, then +0 for verses 12-13.
        self.assertEqual(resolve_psalm_verse(56, 3, self.kjv_counts, self.cpdv_counts), (55, 4))
        self.assertEqual(resolve_psalm_verse(56, 8, self.kjv_counts, self.cpdv_counts), (55, 9))
        self.assertEqual(resolve_psalm_verse(56, 12, self.kjv_counts, self.cpdv_counts), (55, 12))

    def test_out_of_range_chapter_raises(self):
        with self.assertRaises(ValueError):
            resolve_psalm_verse(151, 1, self.kjv_counts, self.cpdv_counts)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -m unittest discover -s tools -p 'test_cpdv_psalm_offsets.py' -v`
Expected: ERROR — `ModuleNotFoundError: No module named 'cpdv_psalm_offsets'`

- [ ] **Step 3: Write the module**

Create `tools/cpdv_psalm_offsets.py`:

```python
"""Resolve a Protestant/KJV Psalms (chapter, verse) to its CPDV counterpart.

CPDV follows the historic Vulgate/Septuagint numbering, which diverges from
KJV's for most of the Psalter. See this file's companion test and the
implementation plan's Task 8 for the full investigation behind these
constants -- every one of them is confirmed against real vendored text, not
computed from reference literature alone.

This function is a CANDIDATE generator, not an authority: two confirmed
counter-examples (Psalms 4 and 56) show the general per-chapter delta rule
can be wrong even when it looks self-consistent, so every one of the 130
ids this project actually needs resolved gets a human reading pass in
data/curation/cpdv_verse_map.json regardless of what this function returns.
"""

# KJV chapters that live, wholly or partly, inside a CPDV chapter shared
# with a neighboring KJV chapter (a genuine merge or split, not a constant
# per-verse shift). Each is resolved explicitly rather than through the
# general delta below.
_MERGE_SPLIT_CHAPTERS = {9, 10, 114, 115, 116, 147}

# Confirmed exceptions to the general "constant delta per chapter" rule,
# found by reading real text (see the module docstring). Each maps
# kjv_chapter -> {kjv_verse: cpdv_verse} for every verse actually needed.
_KNOWN_EXCEPTIONS = {
    4: {2: 3, 3: 4, 4: 5, 5: 6, 6: 7, 7: 8, 8: 9},
    56: {2: 3, 3: 4, 4: 5, 5: 6, 6: 7, 7: 8, 8: 9, 9: 10, 10: 11, 11: 12,
         12: 12, 13: 13},
}


def resolve_psalm_verse(kjv_chapter, kjv_verse, kjv_verse_counts, cpdv_verse_counts):
    """Return (cpdv_chapter, cpdv_verse) -- a candidate, not a final answer."""
    if not 1 <= kjv_chapter <= 150:
        raise ValueError(f"chapter {kjv_chapter} is out of range for Psalms")

    if kjv_chapter == 9:
        return (9, kjv_verse + 1)
    if kjv_chapter == 10:
        return (9, kjv_verse + 21)
    if kjv_chapter == 114:
        return (113, kjv_verse)
    if kjv_chapter == 115:
        return (113, kjv_verse + 8)
    if kjv_chapter == 116:
        return (114, kjv_verse) if kjv_verse <= 9 else (115, kjv_verse - 9)
    if kjv_chapter == 147:
        return (146, kjv_verse) if kjv_verse <= 11 else (147, kjv_verse - 11)

    if 1 <= kjv_chapter <= 8 or 148 <= kjv_chapter <= 150:
        cpdv_chapter = kjv_chapter
    elif 11 <= kjv_chapter <= 113 or 117 <= kjv_chapter <= 146:
        cpdv_chapter = kjv_chapter - 1
    else:
        raise ValueError(f"chapter {kjv_chapter} has no general-rule mapping")

    if kjv_chapter in _KNOWN_EXCEPTIONS:
        cpdv_verse = _KNOWN_EXCEPTIONS[kjv_chapter].get(kjv_verse)
        if cpdv_verse is not None:
            return (cpdv_chapter, cpdv_verse)
        # Fall through to the general rule for any verse in an exception
        # chapter this table doesn't explicitly cover (e.g. verse 1, a
        # heading, which no id in this project resolves to).

    delta = cpdv_verse_counts[cpdv_chapter] - kjv_verse_counts[kjv_chapter]
    return (cpdv_chapter, kjv_verse + delta)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -m unittest discover -s tools -p 'test_cpdv_psalm_offsets.py' -v`
Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add tools/cpdv_psalm_offsets.py tools/test_cpdv_psalm_offsets.py
git commit -m "Add verified CPDV Psalms chapter/verse resolution"
```

---

### Task 9: Build and verify `data/curation/cpdv_verse_map.json` for the 130 affected ids

**Files:**
- Create: `data/curation/cpdv_verse_map.json` (130 entries this task, 470 more in Task 10)
- Create: `tools/build_cpdv_map_candidates.py` (throwaway generator, not shipped code — used once to produce a starting draft)

**Interfaces:**
- Consumes: `resolve_psalm_verse` (Task 8), `load_source_by_name` (Task 4/7),
  `data/curation/selection.json` (frozen, read-only).
- Produces: 130 entries in `data/curation/cpdv_verse_map.json`, each
  `"<id>": {"chapter": N, "verse": M}` giving CPDV's own reference for that
  id's content. Task 10 completes the file to 600 entries; Task 11 reads the
  finished file.

This is a content-verification task, not a formula-application task — Task 8's
`resolve_psalm_verse` is a candidate generator that this investigation already
proved wrong for at least 2 of the ~60 distinct Psalms chapters it touches
(chapters 4 and 56, both worked around explicitly in Task 8, but more
undiscovered exceptions are plausible among the ~130 ids here). Every one of
the 130 must be confirmed by reading real CPDV text against real KJV text,
not accepted from the candidate generator on trust.

THE EXACT 130 IDS (23 outside Psalms, 107 within it):

```
3JN.1.4, ECC.4.6, ECC.4.9, ECC.5.12, ECC.7.2, ECC.7.8, GEN.50.20, HOS.14.4,
ISA.45.15, ISA.45.22, JHN.6.35, JHN.6.37, JHN.6.68, JOB.42.10, JOB.42.2,
JOB.42.5, JON.2.2, MAT.17.20, MRK.4.39, MRK.4.40, MRK.8.36, MRK.9.24,
SNG.6.3,
PSA.3.3, PSA.4.8, PSA.8.4, PSA.9.9, PSA.9.10, PSA.10.1, PSA.16.11, PSA.18.2,
PSA.18.32, PSA.19.1, PSA.19.7, PSA.19.14, PSA.22.1, PSA.23.1, PSA.23.2,
PSA.23.3, PSA.23.4, PSA.23.5, PSA.23.6, PSA.24.1, PSA.25.4, PSA.25.7,
PSA.27.1, PSA.27.10, PSA.27.13, PSA.27.14, PSA.28.7, PSA.29.11, PSA.30.5,
PSA.31.15, PSA.32.1, PSA.32.8, PSA.34.4, PSA.34.8, PSA.34.17, PSA.34.18,
PSA.37.4, PSA.37.5, PSA.37.7, PSA.37.23, PSA.40.2, PSA.40.8, PSA.42.1,
PSA.42.11, PSA.46.1, PSA.46.10, PSA.51.10, PSA.55.17, PSA.55.22, PSA.56.3,
PSA.56.8, PSA.61.2, PSA.68.5, PSA.71.9, PSA.73.13, PSA.73.26, PSA.77.9,
PSA.77.19, PSA.84.10, PSA.84.11, PSA.85.10, PSA.86.5, PSA.88.14, PSA.89.1,
PSA.90.1, PSA.90.12, PSA.90.17, PSA.94.19, PSA.95.2, PSA.100.3, PSA.100.4,
PSA.103.2, PSA.103.12, PSA.103.13, PSA.103.14, PSA.104.24, PSA.107.1,
PSA.107.8, PSA.112.7, PSA.113.3, PSA.116.7, PSA.116.12, PSA.116.15,
PSA.118.8, PSA.118.24, PSA.119.11, PSA.119.50, PSA.119.105, PSA.121.1,
PSA.121.3, PSA.126.3, PSA.126.5, PSA.127.1, PSA.130.1, PSA.131.2, PSA.139.7,
PSA.139.14, PSA.139.17, PSA.139.23, PSA.141.3, PSA.142.4, PSA.143.8,
PSA.143.10, PSA.145.14, PSA.145.16, PSA.147.3, PSA.147.4
```

- [ ] **Step 1: Generate starting candidates for the 107 Psalms ids**

Create `tools/build_cpdv_map_candidates.py`:

```python
#!/usr/bin/env python3
"""One-off generator: produce a starting-candidate CPDV verse map for the
Psalms ids among the 130 affected selected verses. NOT authoritative --
every entry gets read against real text before being trusted. See Task 9 of
docs/superpowers/plans/2026-09-09-multi-translation.md."""
import json, pathlib, sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import load_source_by_index, load_source_by_name
from cpdv_psalm_offsets import resolve_psalm_verse

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    kjv_raw = json.loads((ROOT / "data/source/KJV.json").read_text())
    cpdv_raw = json.loads((ROOT / "data/source/CPDV.json").read_text())
    kjv_psa = next(b for b in kjv_raw["books"] if b["name"] == "Psalms")
    cpdv_psa = next(b for b in cpdv_raw["books"] if b["name"] == "Psalms")
    kjv_counts = {c["chapter"]: len(c["verses"]) for c in kjv_psa["chapters"]}
    cpdv_counts = {c["chapter"]: len(c["verses"]) for c in cpdv_psa["chapters"]}
    kjv_text = {c["chapter"]: {v["verse"]: v["text"] for v in c["verses"]}
                for c in kjv_psa["chapters"]}
    cpdv_text = {c["chapter"]: {v["verse"]: v["text"] for v in c["verses"]}
                 for c in cpdv_psa["chapters"]}

    selection = json.loads((ROOT / "data/curation/selection.json").read_text())["selected"]
    psalm_ids = [e["id"] for e in selection if e["id"].startswith("PSA.")]

    out = {}
    for vid in psalm_ids:
        _, ch, v = vid.split(".")
        ch, v = int(ch), int(v)
        cch, cv = resolve_psalm_verse(ch, v, kjv_counts, cpdv_counts)
        out[vid] = {
            "candidate": {"chapter": cch, "verse": cv},
            "kjv_text": kjv_text[ch][v],
            "cpdv_text_at_candidate": cpdv_text.get(cch, {}).get(cv, "<MISSING>"),
        }

    report_path = ROOT / ".superpowers/sdd/cpdv-map-candidates.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(out, indent=1, ensure_ascii=False))
    print(f"wrote {len(out)} candidates to {report_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
```

Run it:
```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 tools/build_cpdv_map_candidates.py
```
Expected: `wrote 107 candidates to .superpowers/sdd/cpdv-map-candidates.json`

- [ ] **Step 2: Read every one of the 130 ids against real text and build the verified map**

Read `.superpowers/sdd/cpdv-map-candidates.json` for the 107 Psalms
candidates. For the 23 non-Psalms ids, resolve them by direct (book, chapter,
verse) lookup in CPDV via `load_source_by_name` — Habakkuk, John, Mark, Job,
Genesis, Ecclesiastes, Isaiah, Song of Solomon, Jonah, Hosea, Matthew and 3
John are NOT part of the Psalms numbering divergence, so their chapter/verse
numbers should equal KJV's directly; still read each one's real CPDV text
against its real KJV text before trusting that, the same discipline as the
Psalms ids, since this investigation only confirmed the *chapter-count*
alignment for these books in bulk, not each individual verse's content.

For each of the 130 ids:

1. Read the real KJV text (already in the candidate file for Psalms; look up
   directly in `data/source/KJV.json` for the 23 others).
2. Read the real CPDV text at the candidate/direct location.
3. Judge: does the CPDV text express the same content as the KJV text? Minor
   wording differences are expected (different translators); the underlying
   statement, images, and named entities should agree.
4. If it matches, that (chapter, verse) is the answer.
5. If it does NOT match, the candidate is wrong — search up to 3 verses
   before and after in the same CPDV chapter (and, for chapters near a known
   merge/split boundary such as 9/10, 114/115/116, 146/147, check the
   adjacent CPDV chapter too) for the verse that actually matches, the same
   way this investigation found Psalms 4 and 56's true answers by reading
   forward from a wrong candidate.
6. If no verse in a reasonable search radius matches, stop and report that
   specific id rather than guessing — this has not happened for any of the
   130 in this investigation's own spot-checks, but if it does, it is a
   signal something about that chapter's structure is not yet understood.

Write `data/curation/cpdv_verse_map.json`:

```json
{
 "PSA.23.1": {"chapter": 22, "verse": 1},
 "HAB.3.19": {"chapter": 3, "verse": 19}
}
```

(only these two ids shown as an example of the two categories — the real
file has all 130 from this task, later extended to 600 by Task 10.)

- [ ] **Step 3: Verify every entry programmatically**

```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -c "
import json
m = json.load(open('data/curation/cpdv_verse_map.json'))
affected = [
    '3JN.1.4','ECC.4.6','ECC.4.9','ECC.5.12','ECC.7.2','ECC.7.8','GEN.50.20',
    'HOS.14.4','ISA.45.15','ISA.45.22','JHN.6.35','JHN.6.37','JHN.6.68',
    'JOB.42.10','JOB.42.2','JOB.42.5','JON.2.2','MAT.17.20','MRK.4.39',
    'MRK.4.40','MRK.8.36','MRK.9.24','SNG.6.3',
]
missing = [i for i in affected if i not in m]
print('missing from map:', missing)
print('total entries so far:', len(m))
"
```
Expected: `missing from map: []` — the printed count will be less than 130 if
you have not yet added all 107 Psalms ids; confirm all 130 by cross-checking
against the exact id list in this task's header before moving on.

- [ ] **Step 4: Commit**

```bash
git add data/curation/cpdv_verse_map.json tools/build_cpdv_map_candidates.py
git commit -m "Build and verify the CPDV verse map for the 130 affected ids"
```

---

### Task 10: Complete the map for the 470 unaffected ids

**Files:**
- Modify: `data/curation/cpdv_verse_map.json`
- Create: `tools/test_cpdv_verse_map.py`

**Interfaces:**
- Consumes: `data/curation/selection.json`, `load_source_by_index`.
- Produces: `data/curation/cpdv_verse_map.json` complete at 600 entries.
  Task 11 requires every one of the 600 selected ids present, or the build
  fails loudly rather than silently omitting a translation.

The other 470 selected ids sit in a chapter this investigation already
confirmed has an identical verse count between KJV and CPDV — for these,
`(chapter, verse)` is the same in both. This task adds them directly (no
per-verse reading required, since a chapter-level exact-count match this
consistent is not the kind of thing that hides a Psalms-4-or-56-style
surprise — those only occur where the count itself already signals
something, which is exactly why they were caught) and adds a permanent
automated check as the safety net instead of a manual one.

- [ ] **Step 1: Add the 470 direct entries**

```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -c "
import json
sel = json.load(open('data/curation/selection.json'))['selected']
existing = json.load(open('data/curation/cpdv_verse_map.json'))
assert len(existing) == 130, f'expected 130 entries from Task 9, found {len(existing)}'

for entry in sel:
    vid = entry['id']
    if vid in existing:
        continue
    _, ch, v = vid.split('.')
    existing[vid] = {'chapter': int(ch), 'verse': int(v)}

assert len(existing) == 600, f'expected 600 total, got {len(existing)}'
json.dump(existing, open('data/curation/cpdv_verse_map.json', 'w'), indent=1, sort_keys=True)
print('wrote 600 entries')
"
```
Expected: `wrote 600 entries`

- [ ] **Step 2: Write the failing test**

Create `tools/test_cpdv_verse_map.py`:

```python
import json, pathlib, sys, unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bible_source import load_source_by_name

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAP = ROOT / "data" / "curation" / "cpdv_verse_map.json"
SELECTION = ROOT / "data" / "curation" / "selection.json"


class CpdvVerseMapTests(unittest.TestCase):
    def test_has_exactly_600_entries_matching_selection(self):
        m = json.loads(MAP.read_text())
        sel_ids = {e["id"] for e in json.loads(SELECTION.read_text())["selected"]}
        self.assertEqual(set(m), sel_ids)
        self.assertEqual(len(m), 600)

    def test_every_entry_resolves_to_a_real_cpdv_verse(self):
        m = json.loads(MAP.read_text())
        by_book = load_source_by_name(ROOT / "data" / "source" / "CPDV.json")
        bad = []
        for vid, ref in m.items():
            book = vid.split(".")[0]
            chapters = by_book[book]["chapters"]
            chapter = next((c for c in chapters if c["chapter"] == ref["chapter"]), None)
            if chapter is None:
                bad.append((vid, "no such chapter"))
                continue
            verse = next((v for v in chapter["verses"] if v["verse"] == ref["verse"]), None)
            if verse is None:
                bad.append((vid, "no such verse"))
        self.assertEqual(bad, [])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run and confirm it passes**

Run: `cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -m unittest discover -s tools -p 'test_cpdv_verse_map.py' -v`
Expected: PASS, 2 tests. If `test_every_entry_resolves_to_a_real_cpdv_verse`
fails, it names the exact id whose map entry points at a chapter or verse
that does not exist in CPDV — that id's entry needs correcting before moving
on, whether it came from Task 9's manual work or this task's direct 470.

- [ ] **Step 4: Commit**

```bash
git add data/curation/cpdv_verse_map.json tools/test_cpdv_verse_map.py
git commit -m "Complete the CPDV verse map to all 600 selected ids"
```

---

### Task 11: Wire CPDV into the builder and validator

**Files:**
- Modify: `tools/build_feed.py`
- Modify: `tools/validate_feed.py`

**Interfaces:**
- Consumes: `data/curation/cpdv_verse_map.json` (Tasks 9-10),
  `load_source_by_name` (Task 4/7).
- Produces: `feed_verses.json` verses gain a `"CPDV"` key in `translations`.
  `TRANSLATIONS` in `validate_feed.py` grows to its final `{"KJV", "BSB", "CPDV"}`.

Unlike KJV and BSB, CPDV's displayText needs almost no stripping — the verse
map already points each id at the content-bearing verse directly, since
CPDV keeps a Psalm's heading as its own separate verse rather than folding
it into verse 1 the way KJV and BSB do. `CPDV_SUPERSCRIPTIONS` is therefore
empty. The one confirmed exception is `2PE.3.18`, which carries a trailing
doxology in CPDV just as it does in KJV and BSB (verified against the real
vendored text, exact string below); `HAB.3.19` was checked directly and
carries no such marker in CPDV (its content ends "...while singing psalms."
with no separate colophon).

- [ ] **Step 1: Add CPDV's tables and text lookup to `build_feed.py`**

Add near the BSB tables:

```python
# CPDV's verse map already points every affected id past its heading, so no
# leading-superscription table is needed. This stays empty deliberately --
# do not add entries here; if a build ever needs one, the CPDV_HEADING_HINT
# safety net below will catch it and say so.
CPDV_SUPERSCRIPTIONS = {}

CPDV_TRAILING_MARKERS = {
    "2PE.3.18": " To him be glory, both now and in the day of eternity. Amen.",
}

CPDV_HEADING_HINT = re.compile(
    r"^(?:Unto the end\.|Alleluia\.|A Psalm|A Canticle|A Prayer|The inscription)"
)


def cpdv_display_text_for(vid, text):
    return display_text_for(vid, text, CPDV_SUPERSCRIPTIONS, CPDV_TRAILING_MARKERS,
                             CPDV_HEADING_HINT, "CPDV_SUPERSCRIPTIONS/CPDV_TRAILING_MARKERS")
```

- [ ] **Step 2: Load CPDV's raw per-book data and the verse map**

In `main()`, alongside the existing `bsb_text = load_source_by_index(...)`, add:

```python
    from bible_source import load_source_by_name
    cpdv_by_book = load_source_by_name(ROOT / "data/source/CPDV.json")
    cpdv_map = json.loads((ROOT / "data/curation/cpdv_verse_map.json").read_text())

    def cpdv_text_for(vid, book):
        ref = cpdv_map[vid]
        chapters = cpdv_by_book[book]["chapters"]
        chapter = next(c for c in chapters if c["chapter"] == ref["chapter"])
        verse = next(v for v in chapter["verses"] if v["verse"] == ref["verse"])
        return re.sub(r"\s+", " ", verse["text"]).strip()
```

- [ ] **Step 3: Emit the CPDV translation**

Extend the `verses.append({...})` block's `translations` dict:

```python
        verse_text = text[(book, chapter, verse)]
        bsb_verse_text = bsb_text[(book, chapter, verse)]
        cpdv_verse_text = cpdv_text_for(entry["id"], book)
        verses.append({
            "id": entry["id"],
            "reference": f"{names[book]} {chapter}:{verse}",
            "book": book, "chapter": chapter, "verse": verse,
            "translations": {
                "KJV": {
                    "text": verse_text,
                    "displayText": kjv_display_text_for(entry["id"], verse_text),
                },
                "BSB": {
                    "text": bsb_verse_text,
                    "displayText": bsb_display_text_for(entry["id"], bsb_verse_text),
                },
                "CPDV": {
                    "text": cpdv_verse_text,
                    "displayText": cpdv_display_text_for(entry["id"], cpdv_verse_text),
                },
            },
            "context": contexts[entry["id"]],
            "topics": entry["topics"],
            "tier": entry["tier"],
        })
```

Bump the content version:

```python
CONTENT_VERSION = "2026-09-09.2"
```

- [ ] **Step 4: Rebuild**

```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 tools/build_feed.py
```
Expected: `wrote 600 verses to BibleApp/BibleApp/Resources/feed_verses.json`. If
`SystemExit` fires for a CPDV verse carrying an unhandled heading/marker,
that is real signal — read the flagged verse's actual CPDV text and either
add it to `CPDV_SUPERSCRIPTIONS`/`CPDV_TRAILING_MARKERS` (verified against
the source, the same discipline as every other table in this project) or
confirm `cpdv_verse_map.json`'s entry for that id is pointing at the wrong
verse and needs correcting (return to Task 9's method for that one id).

- [ ] **Step 5: Extend `validate_feed.py` to check CPDV against its own source**

Grow the constant:

```python
TRANSLATIONS = {"KJV", "BSB", "CPDV"}
```

CPDV needs a different check from KJV's, since its source text lives at a
different (chapter, verse) than the entry's own — add a CPDV index built
through the verse map, and a per-entry comparison alongside the existing
KJV one. Replace the `if code == "KJV":` block in the per-entry loop with:

```python
            if code == "KJV":
                if key not in index:
                    errors.append(f"{vid}: no such verse in KJV source")
                elif text != index[key]:
                    errors.append(f"{vid}: KJV text does not match KJV source")
            elif code == "CPDV":
                cpdv_ref = cpdv_map.get(vid)
                if cpdv_ref is None:
                    errors.append(f"{vid}: no entry in cpdv_verse_map.json")
                else:
                    cpdv_key = (entry.get("book"), cpdv_ref["chapter"], cpdv_ref["verse"])
                    if cpdv_key not in cpdv_index:
                        errors.append(f"{vid}: cpdv_verse_map.json points at a "
                                      f"nonexistent CPDV verse {cpdv_ref}")
                    elif text != cpdv_index[cpdv_key]:
                        errors.append(f"{vid}: CPDV text does not match CPDV source "
                                      f"at the mapped verse {cpdv_ref}")
```

This needs `cpdv_index` and `cpdv_map` built before the per-entry loop.
Add near where `index = _kjv_index()` already is:

```python
    try:
        cpdv_by_book = load_source_by_name(ROOT / "data" / "source" / "CPDV.json")
    except SourceDataError as e:
        errors.append(f"source data error: {e}")
        return errors
    try:
        cpdv_map = json.loads((ROOT / "data" / "curation" / "cpdv_verse_map.json").read_text())
    except (OSError, json.JSONDecodeError) as e:
        errors.append(f"source data error: failed to read cpdv_verse_map.json: {e}")
        return errors

    cpdv_index = {}
    for book_id, book in cpdv_by_book.items():
        for ch in book["chapters"]:
            for v in ch["verses"]:
                cpdv_index[(book_id, int(ch["chapter"]), int(v["verse"]))] = \
                    re.sub(r"\s+", " ", v["text"]).strip()
```

Add the import at the top of the file, alongside the existing
`from bible_source import SourceDataError, load_source_by_index`:

```python
from bible_source import SourceDataError, load_source_by_index, load_source_by_name
```

`re` is already imported for `CONTEXT_MIN`/`CONTEXT_MAX`-adjacent code —
confirm the top-of-file `import` line includes it (it does, from the
original file).

- [ ] **Step 6: Run the validator**

```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 tools/validate_feed.py BibleApp/BibleApp/Resources/feed_verses.json
```
Expected: `0 error(s)`. Any `CPDV text does not match CPDV source` error means
`cpdv_verse_map.json` and `build_feed.py`'s emitted text have drifted —
re-run `build_feed.py` first (Step 4) before assuming the map itself is wrong.

- [ ] **Step 7: Run the full test suite**

```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && /usr/bin/python3 -m unittest discover -s tools -p 'test_*.py' -v
```
Expected: PASS, every test.

- [ ] **Step 8: Commit**

```bash
git add tools/build_feed.py tools/validate_feed.py BibleApp/BibleApp/Resources/feed_verses.json
git commit -m "Add CPDV translation to the shipped feed"
```

---

### Task 12: Full-suite and on-device verification of all three translations

**Files:** none (verification only).

**Interfaces:** none — this task confirms every earlier task's contract holds together.

- [ ] **Step 1: Run every test suite**

```bash
cd /Users/vietdo/Documents/GitHub/BibleApp
swift test --package-path packages/BibleFeedKit
/usr/bin/python3 -m unittest discover -s tools -p 'test_*.py' -v
/usr/bin/python3 tools/validate_feed.py BibleApp/BibleApp/Resources/feed_verses.json
```
Expected: Swift suite passes (24 tests: 20 pre-existing + `translationHasThreeCases`
+ `unknownTranslationKeyFailsDecoding`, minus 1 old assertion the Task 1
rewrite dropped, net +4 from the pre-feature baseline of 20). Python suite
passes, every file. Validator: `0 error(s)`.

- [ ] **Step 2: Build the app**

```bash
cd /Users/vietdo/Documents/GitHub/BibleApp && xcodebuild -project BibleApp/BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: On-device spot check across all three translations**

Install fresh (or reuse existing state) on the iPhone 17 Pro simulator.
Complete onboarding if prompted. In the feed, note the current card's
reference. Open the Library sheet, use the translation menu to select each
of the three translations in turn, close the sheet each time, and confirm
the same card's text changes appropriately:

- KJV: recognizable archaic wording ("thou", "thee", "-eth" verb endings).
- BSB: modern wording, same meaning.
- CPDV: modern wording, generally Latinate phrasing (e.g. "the Lord" for the
  same divine name KJV/BSB render the same way, but longer sentence
  structures are common in this translation).

Then specifically navigate to (or use "Edit topics"/scroll to find) a
Psalm 23 card if the current queue doesn't include one, and confirm CPDV
shows the correct content ("The Lord directs me, and nothing will be
lacking to me...") rather than a different psalm's text — this was the
exact defect this whole investigation exists to prevent, so it is the one
card worth checking by name rather than only sampling at random.

- [ ] **Step 4: Confirm the reference label never changes with translation**

While switching between the three translations on the same card, confirm the
reference text (e.g. "Psalms 23:1") stays fixed regardless of which
translation is selected — per the spec, the label always reflects Protestant
numbering, never CPDV's own internal chapter/verse.

- [ ] **Step 5: No commit** — this task is verification only. If any check
fails, return to the task whose contract it violates, fix there, and re-run
this task's checks from Step 1.

## Done when

- `swift test --package-path packages/BibleFeedKit` passes.
- `python3 -m unittest discover -s tools -p 'test_*.py'` passes, including
  `test_bible_source.py`, `test_cpdv_psalm_offsets.py`, `test_cpdv_verse_map.py`.
- `python3 tools/validate_feed.py BibleApp/BibleApp/Resources/feed_verses.json`
  exits 0.
- The app builds and, on a real simulator, shows correct text in all three
  translations for the same card, with the reference label unchanged across
  the switch, and Psalm 23 specifically confirmed correct under CPDV.
