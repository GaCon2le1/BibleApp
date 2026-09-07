# Bible Scroll Feed — Design

Date: 2026-09-07
Status: Approved

## Problem

Build an iOS app where new believers and seekers learn the Bible by scrolling a
vertical feed. Each page is one famous verse.

The repo currently holds a bare SwiftUI template plus two data files:
`bible_books.json` (66 books, validated) and `key_verses.json` (1,189 verses, one
per chapter, KJV text validated against source).

`key_verses.json` is the wrong shape for a feed. One-verse-per-chapter is a
*coverage* rule, not a *quality* rule: it forces a card from the Chronicles
genealogies while capping Psalm 23 at a single verse. Scroll feeds live on hit
rate — a few dull cards and the user leaves.

## Decisions

| Question | Decision |
|---|---|
| Core loop | Feed that remembers: save, no repeats, daily streak, topic affinity |
| Target user | New believers and seekers, not regular churchgoers |
| Translation | KJV text on the card, plain modern English in a `context` field |
| Feed order | Onboarding topic picker drives ranking; no behavioural algorithm |
| v1 size | ~400 verses across 12 topics |

### Why KJV and not WEB

WEB is public domain and reads more easily, but renders Psalm 23:1 as
"Yahweh is my shepherd: I shall lack nothing." An app built on *famous* verses
needs the recognisable wording; users screenshot and share these. KJV keeps the
iconic form, and the `context` field carries the plain-English explanation.

## Architecture

SwiftUI, no backend. The Xcode project targets iOS 26.4 under Xcode 26.4
and Swift 6.3. Three layers:

- **Content** — static JSON in the app bundle, read-only, versioned
- **Engine** — `FeedEngine`, pure logic, shipped as the local Swift package
  `BibleFeedKit`. It imports neither SwiftUI nor SwiftData, and its tests run
  headless with `swift test`, because the Xcode project has no unit test target.
- **UI** — SwiftUI views holding no ordering logic

Persistence is SwiftData, on device only.

The content file carries `schemaVersion` and `contentVersion` so a later remote-refresh
layer is an addition, not a rewrite.

### Alternatives considered

- **Bundle + remote refresh** — lets content ship without an App Store release, but
  needs hosting, version negotiation and network error handling in v1.
- **Full backend with accounts** — premature; the feed is unproven.

## Data model

`feed_verses.json`, ~400 entries, replaces `key_verses.json` in the bundle:

```json
{
  "id": "JHN.3.16",
  "reference": "John 3:16",
  "book": "JHN", "chapter": 3, "verse": 16,
  "text": "For God so loved the world, that he gave his only begotten Son...",
  "displayText": "For God so loved the world, that he gave his only begotten Son...",
  "context": "Jesus said this at night to a religious leader who came to him in secret, afraid to be seen asking questions.",
  "topics": ["love", "hope"],
  "tier": 1
}
```

- `text` — KJV verbatim, extracted from source, never hand-typed. This field is
  the provenance guarantee and is never displayed directly.
- `displayText` — what the card renders. Identical to `text` for most verses.
  For the eight verses where the KJV source stores a psalm superscription or a
  Hebrew acrostic letter inside verse 1 ("A Psalm of David. The Lord is my
  shepherd", "נ NUN. Thy word is a lamp"), it is that prefix removed. It is
  derived programmatically and validated as an exact suffix of `text`, so no
  wording can be invented in the gap between the two fields.
  Source spelling is otherwise preserved as-is, including "The Lord" rather
  than small-capital "LORD".
- `context` — one or two sentences of plain modern English: who spoke, to whom,
  in what situation. This field is what makes the app teach rather than decorate.
- `tier` — 1 to 3, drives feed ranking, assigned by these criteria:
  - **1** — verses a non-churchgoer would plausibly recognise out of context
    (John 3:16, Psalm 23:1, Philippians 4:13). Roughly 100 of the 400.
  - **2** — well known within the church, quotable standalone, but not household
    phrases. Roughly 200.
  - **3** — worth reading and clear on its own, included for topical coverage
    where tiers 1 and 2 leave a topic thin. Roughly 100.
- `topics` — one to three tags drawn from the fixed list below

### Topics

Twelve, chosen for seekers, avoiding theological vocabulary:

`anxiety` · `hope` · `love` · `forgiveness` · `strength` · `guidance` ·
`peace` · `doubt` · `purpose` · `gratitude` · `grief` · `worth`

### Existing files

- `bible_books.json` stays in the bundle unchanged.
- `key_verses.json` moves out of the bundle to `data/candidates/`. It becomes the
  pool the 400 are selected from, and remains available for a future chapter reader.

## Components

| Component | Responsibility | Depends on |
|---|---|---|
| `ContentStore` | Loads and decodes JSON at launch | Bundle |
| `FeedEngine` | Builds the verse queue from topics, seen set and tier | ContentStore, UserState |
| `UserState` | SwiftData: seenIDs, savedIDs, topics, streak | — |
| `OnboardingView` | First-run topic picker, 3 to 5 choices, skippable | UserState |
| `FeedView` | Vertical paging, one card per page | FeedEngine |
| `VerseCard` | Text, reference, context, save control | — |
| `LibraryView` | Saved verses, filterable by topic | UserState |

`FeedEngine` must not import SwiftUI. That constraint is what makes it testable.

## Feed algorithm

1. Pool is every verse whose id is absent from `seenIDs`.
2. Score is `tierWeight` (tier 1 = 3, tier 2 = 2, tier 3 = 1), plus 2 when the
   verse carries a tag the user selected.
3. Sort by score descending, shuffling within each score band so two sessions
   do not open identically.
4. A card is marked seen once it has been on screen for two seconds — a flick
   past does not consume it.
5. When the pool empties, show a milestone screen, then reopen the queue giving
   priority to saved verses.
6. Scrolling back to an already-seen card does not re-consume it; seen is
   permanent for the current cycle.

### Streak

A day counts once the user marks at least one card seen, in device local time.
The streak increments on consecutive counted days and resets to zero after a
full calendar day with none. It is stored in `UserState` and shown in the
feed header. No grace days, no freezes, in v1.

## Error handling

- JSON decode failure: fatal in debug, since it is a programming error. In
  release, an empty state with a retry control.
- Onboarding skipped, or no topics selected: fall back to all twelve, so the
  topic bonus contributes nothing and ranking falls back to tier alone. Topics
  stay editable later from settings.
- Empty pool: milestone screen, never a blank view.

## Testing

`FeedEngine` unit tests:

- a seen verse never reappears while unseen verses remain
- tier ordering holds
- topic bonus is applied
- pool exhaustion produces the milestone path
- shuffling within a band loses no verses

Data validation script, extending the existing `validate.py` approach, run as a
test so bad data fails the build:

- every `id` resolves to a real KJV verse
- `text` matches the source exactly
- `topics` is a subset of the twelve
- `tier` is 1, 2 or 3
- `context` is non-empty and between 60 and 220 characters

## Out of scope for v1

Accounts and sync · full 31,102-verse text and chapter reader · quizzes and
spaced repetition · audio · WEB toggle · cross-references.

Two exclusions are deliberate but should follow immediately after v1, because
they drive retention in this category: a daily verse push notification, and
sharing a card as an image.
