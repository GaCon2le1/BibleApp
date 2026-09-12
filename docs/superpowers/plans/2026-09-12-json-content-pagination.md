# Paginated Content Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the shipped Bible content into an always-resident lightweight index (id/topics/tier, needed for feed ranking) and on-demand-loaded content shards (translations/context), so memory and decode cost scale with what's viewed, not the full dataset.

**Architecture:** `BibleFeedKit` gets a new `VerseIndexEntry`/`VerseContent` model split (replacing the combined `Verse` as the wire format, while `Verse` itself survives as a UI-facing merge of the two) plus a `ShardStore` actor that decodes shard files on demand with a capacity-5 LRU cache. `tools/build_feed.py` emits `feed_index.json` + `feed_shard_NNNN.json` files instead of one combined `feed_verses.json`; `tools/validate_feed.py` gains a `validate_split_feed` that reassembles them for the same content checks plus new structural cross-file checks. The app's `ContentStore`, `FeedView`, `VerseCard`, and `LibraryView` are updated to read the index eagerly and fetch content lazily.

**Tech Stack:** Swift 6 (Swift Testing framework, actors), Swift Package Manager (`packages/BibleFeedKit`), SwiftUI (iOS 18), Python 3.9 (`tools/*.py`, `unittest`).

## Global Constraints

- Shard size: 100 verses per shard file (from the approved spec).
- Shard cache capacity: 5 resident shards, LRU eviction (from the approved spec).
- `schemaVersion` bumps from 2 to 3 (breaking format change); `CONTENT_VERSION` in `tools/build_feed.py` bumps to `"2026-09-12.1"`.
- **Deviation from the spec's literal file layout:** the spec named shard files `feed_shards/shard_0000.json` in a subfolder. This plan instead uses flat filenames `feed_shard_0000.json` directly under `BibleApp/BibleApp/Resources/`, matching how every existing resource in this project is bundled and loaded (`Bundle.main.url(forResource:withExtension:)` with no `subdirectory:`, no explicit Xcode file references — the `Resources` group is a `PBXFileSystemSynchronizedRootGroup` that already flattens files into the bundle root today). This avoids introducing an unverified nested-folder-reference bundling behavior into a working project. The content/behavior described in the spec (index + on-demand shards, 100 verses/shard, LRU cache) is unchanged.
- No network fetching — everything stays bundled with the app (unchanged from the spec's "out of scope").
- Python tests run with `python3 -m unittest tools.test_<name> -v` from the repo root (`/Users/vietdo/Documents/GitHub/BibleApp`). Swift package tests run with `swift test` from `packages/BibleFeedKit`.

---

## Task 1: Split `Verse` into `VerseIndexEntry` + `VerseContent`

**Files:**
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/VerseIndexEntry.swift`
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/VerseContent.swift`
- Modify: `packages/BibleFeedKit/Sources/BibleFeedKit/Verse.swift`
- Modify: `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseTests.swift`
- Create: `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseIndexEntryTests.swift`
- Create: `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseContentTests.swift`

**Interfaces:**
- Produces: `VerseIndexEntry(id:reference:book:chapter:verse:topics:tier:shard:)` — `Codable, Identifiable, Hashable, Sendable`, `shard: Int` names which content shard holds this verse.
- Produces: `FeedIndex { schemaVersion: Int, contentVersion: String, verses: [VerseIndexEntry] }` — replaces `FeedContent`.
- Produces: `VerseContent(id:translations:context:)` — `Codable, Identifiable, Hashable, Sendable`.
- Produces: `ContentShard { schemaVersion: Int, contentVersion: String, verses: [VerseContent] }`.
- Produces: `Verse.init(index: VerseIndexEntry, content: VerseContent)` — merges the two into the existing combined `Verse` shape.
- Consumes: nothing new (this task only touches `BibleFeedKit`'s own model files).

- [ ] **Step 1: Write the new/updated test files**

Replace `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseTests.swift` entirely with:

```swift
import Testing
import Foundation
@testable import BibleFeedKit

@Test func topicHasTwelveCases() {
    #expect(Topic.allCases.count == 12)
}

@Test func translationHasThreeCases() {
    #expect(Translation.allCases.count == 3)
}

@Test func mergesIndexEntryAndContentIntoVerse() {
    let index = VerseIndexEntry(id: "JHN.3.16", reference: "John 3:16", book: "JHN",
                                 chapter: 3, verse: 16, topics: [.love, .hope],
                                 tier: 1, shard: 0)
    let content = VerseContent(
        id: "JHN.3.16",
        translations: [.kjv: TranslationText(text: "For God so loved the world",
                                              displayText: "For God so loved the world")],
        context: "Jesus said this at night to a religious leader.")
    let verse = Verse(index: index, content: content)
    #expect(verse.id == "JHN.3.16")
    #expect(verse.reference == "John 3:16")
    #expect(verse.book == "JHN")
    #expect(verse.chapter == 3)
    #expect(verse.verse == 16)
    #expect(verse.topics == [.love, .hope])
    #expect(verse.tier == 1)
    #expect(verse.translations[.kjv]?.displayText == "For God so loved the world")
    #expect(verse.context == "Jesus said this at night to a religious leader.")
}
```

Create `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseIndexEntryTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleFeedKit

private let sampleJSON = """
{
  "schemaVersion": 3,
  "contentVersion": "test",
  "verses": [
    {
      "id": "JHN.3.16", "reference": "John 3:16",
      "book": "JHN", "chapter": 3, "verse": 16,
      "topics": ["love", "hope"], "tier": 1, "shard": 0
    }
  ]
}
""".data(using: .utf8)!

@Test func decodesFeedIndex() throws {
    let index = try JSONDecoder().decode(FeedIndex.self, from: sampleJSON)
    #expect(index.schemaVersion == 3)
    #expect(index.verses.count == 1)
    let entry = index.verses[0]
    #expect(entry.id == "JHN.3.16")
    #expect(entry.reference == "John 3:16")
    #expect(entry.book == "JHN")
    #expect(entry.chapter == 3)
    #expect(entry.verse == 16)
    #expect(entry.topics == [.love, .hope])
    #expect(entry.tier == 1)
    #expect(entry.shard == 0)
}

@Test func unknownTopicFailsIndexDecoding() {
    let bad = """
    {"schemaVersion":3,"contentVersion":"t","verses":[
      {"id":"A.1.1","reference":"A 1:1","book":"A","chapter":1,"verse":1,
       "topics":["prosperity"],"tier":1,"shard":0}]}
    """.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(FeedIndex.self, from: bad)
    }
}
```

Create `packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseContentTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleFeedKit

private let sampleJSON = """
{
  "schemaVersion": 3,
  "contentVersion": "test",
  "verses": [
    {
      "id": "JHN.3.16",
      "translations": {
        "KJV": { "text": "A Psalm of David. For God so loved the world",
                 "displayText": "For God so loved the world" },
        "BSB": { "text": "For God so loved the world (BSB)",
                 "displayText": "For God so loved the world (BSB)" },
        "CPDV": { "text": "For God so loved the world (CPDV)",
                  "displayText": "For God so loved the world (CPDV)" }
      },
      "context": "Jesus said this at night to a religious leader."
    }
  ]
}
""".data(using: .utf8)!

@Test func decodesContentShard() throws {
    let shard = try JSONDecoder().decode(ContentShard.self, from: sampleJSON)
    #expect(shard.schemaVersion == 3)
    #expect(shard.verses.count == 1)
    let content = shard.verses[0]
    #expect(content.id == "JHN.3.16")
    #expect(content.translations[.kjv]?.displayText == "For God so loved the world")
    #expect(content.translations[.bsb]?.displayText == "For God so loved the world (BSB)")
    #expect(content.translations[.cpdv]?.displayText == "For God so loved the world (CPDV)")
    #expect(content.translations[.kjv]!.text.hasSuffix(content.translations[.kjv]!.displayText))
    #expect(content.context == "Jesus said this at night to a religious leader.")
}

@Test func unknownTranslationKeyFailsShardDecoding() {
    let bad = """
    {"schemaVersion":3,"contentVersion":"t","verses":[
      {"id":"A.1.1",
       "translations":{"NIV":{"text":"x","displayText":"x"}},
       "context":"y"}]}
    """.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ContentShard.self, from: bad)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to build**

Run: `cd packages/BibleFeedKit && swift test`
Expected: Build error — `VerseIndexEntry`, `FeedIndex`, `VerseContent`, `ContentShard`, and `Verse.init(index:content:)` do not exist yet.

- [ ] **Step 3: Create `VerseIndexEntry.swift`**

```swift
import Foundation

/// The lightweight metadata `FeedEngine` ranks on. Always fully loaded, since
/// ranking must see every verse's id/tier/topics at once. `shard` names which
/// content shard (see `ContentShard`) holds this verse's translations/context.
public struct VerseIndexEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let reference: String
    public let book: String
    public let chapter: Int
    public let verse: Int
    public let topics: [Topic]
    public let tier: Int
    public let shard: Int

    public init(id: String, reference: String, book: String, chapter: Int,
                verse: Int, topics: [Topic], tier: Int, shard: Int) {
        self.id = id
        self.reference = reference
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.topics = topics
        self.tier = tier
        self.shard = shard
    }
}

public struct FeedIndex: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let verses: [VerseIndexEntry]
}
```

- [ ] **Step 4: Create `VerseContent.swift`**

```swift
import Foundation

/// The heavy, on-demand-loaded half of a verse: translation text and
/// context. Decoded from a `ContentShard` file only when a verse needs to be
/// displayed.
public struct VerseContent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let translations: [Translation: TranslationText]
    public let context: String

    public init(id: String, translations: [Translation: TranslationText], context: String) {
        self.id = id
        self.translations = translations
        self.context = context
    }
}

public struct ContentShard: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let verses: [VerseContent]
}
```

- [ ] **Step 5: Update `Verse.swift`**

Replace the file's contents with:

```swift
import Foundation

public enum Topic: String, Codable, CaseIterable, Sendable, Hashable {
    case anxiety, hope, love, forgiveness, strength, guidance
    case peace, doubt, purpose, gratitude, grief, worth
}

/// A translation the feed can render a card in. Raw values are the exact
/// keys used in the shipped content files' per-verse `translations` object.
public enum Translation: String, Codable, CaseIterable, Sendable, Hashable, CodingKeyRepresentable {
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

    /// Merges a ranking-time index entry with its on-demand-loaded content
    /// into the combined shape views render.
    public init(index: VerseIndexEntry, content: VerseContent) {
        self.init(id: index.id, reference: index.reference, book: index.book,
                   chapter: index.chapter, verse: index.verse,
                   translations: content.translations, context: content.context,
                   topics: index.topics, tier: index.tier)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/BibleFeedKit && swift test`
Expected: All tests pass, including the three new/updated files.

- [ ] **Step 7: Commit**

```bash
git add packages/BibleFeedKit/Sources/BibleFeedKit/VerseIndexEntry.swift \
        packages/BibleFeedKit/Sources/BibleFeedKit/VerseContent.swift \
        packages/BibleFeedKit/Sources/BibleFeedKit/Verse.swift \
        packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseTests.swift \
        packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseIndexEntryTests.swift \
        packages/BibleFeedKit/Tests/BibleFeedKitTests/VerseContentTests.swift
git commit -m "$(cat <<'EOF'
Split Verse into VerseIndexEntry + VerseContent

Separates the always-resident ranking metadata from the on-demand
translation/context content, so FeedEngine can keep ranking every
verse without the whole library's text staying in memory.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Update `FeedEngine` to rank `VerseIndexEntry`

**Files:**
- Modify: `packages/BibleFeedKit/Sources/BibleFeedKit/FeedEngine.swift`
- Modify: `packages/BibleFeedKit/Tests/BibleFeedKitTests/FeedEngineTests.swift`

**Interfaces:**
- Consumes: `VerseIndexEntry` (from Task 1).
- Produces: `FeedEngine.init(verses: [VerseIndexEntry])`, `FeedQueue { verses: [VerseIndexEntry], isReplay: Bool }`, `FeedEngine.queue(selectedTopics:seen:saved:seed:) -> FeedQueue` — same method signature as before, only the element type of the arrays changed.

- [ ] **Step 1: Update the test fixture helper**

In `packages/BibleFeedKit/Tests/BibleFeedKitTests/FeedEngineTests.swift`, replace the `verse` helper at the top of the file:

```swift
private func verse(_ id: String, tier: Int, topics: [Topic] = [.hope]) -> VerseIndexEntry {
    VerseIndexEntry(id: id, reference: id, book: "PSA", chapter: 1, verse: 1,
                     topics: topics, tier: tier, shard: 0)
}
```

Leave every `@Test` function in the file unchanged — they only reference `.id`, `q.verses`, and `q.isReplay`, which still exist on the new types.

- [ ] **Step 2: Run the tests to verify they fail to build**

Run: `cd packages/BibleFeedKit && swift test`
Expected: Build error — `FeedEngine.init` still expects `[Verse]`, not `[VerseIndexEntry]`.

- [ ] **Step 3: Update `FeedEngine.swift`**

Replace every `Verse` in the file with `VerseIndexEntry`:

```swift
import Foundation

public struct FeedQueue: Equatable, Sendable {
    public let verses: [VerseIndexEntry]
    public let isReplay: Bool

    public init(verses: [VerseIndexEntry], isReplay: Bool) {
        self.verses = verses
        self.isReplay = isReplay
    }
}

public struct FeedEngine: Sendable {
    private let verses: [VerseIndexEntry]

    /// Verse array order must be stable across calls for seeded reproducibility.
    /// `shuffled(using:)` permutes from the current array position, so identical seeds with different input order produce different results.
    /// This assumption is satisfied in practice when verses come from JSONDecoder, which preserves JSON array source order.
    public init(verses: [VerseIndexEntry]) {
        self.verses = verses
    }

    /// Score is tier weight plus a bonus when the verse matches a chosen topic.
    /// Tier 1 weighs 3, tier 2 weighs 2, tier 3 weighs 1.
    static func score(_ verse: VerseIndexEntry, selectedTopics: Set<Topic>) -> Int {
        let tierWeight = max(0, 4 - verse.tier)
        let topicBonus = verse.topics.contains(where: selectedTopics.contains) ? 2 : 0
        return tierWeight + topicBonus
    }

    public func queue(selectedTopics: Set<Topic>,
                      seen: Set<String>,
                      saved: Set<String>,
                      seed: UInt64) -> FeedQueue {
        let unseen = verses.filter { !seen.contains($0.id) }
        if !unseen.isEmpty || verses.isEmpty {
            return FeedQueue(verses: rank(unseen, selectedTopics: selectedTopics, seed: seed),
                             isReplay: false)
        }

        // Every verse has been seen. Reopen the queue, saved verses first.
        let savedVerses = verses.filter { saved.contains($0.id) }
        let rest = verses.filter { !saved.contains($0.id) }
        let replay = rank(savedVerses, selectedTopics: selectedTopics, seed: seed)
            + rank(rest, selectedTopics: selectedTopics, seed: seed &+ 1)
        return FeedQueue(verses: replay, isReplay: true)
    }

    private func rank(_ pool: [VerseIndexEntry],
                      selectedTopics: Set<Topic>,
                      seed: UInt64) -> [VerseIndexEntry] {
        var generator = SeededGenerator(seed: seed)
        var bands: [Int: [VerseIndexEntry]] = [:]
        for verse in pool {
            bands[Self.score(verse, selectedTopics: selectedTopics), default: []].append(verse)
        }
        return bands.keys.sorted(by: >).flatMap { key in
            bands[key]!.shuffled(using: &generator)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/BibleFeedKit && swift test`
Expected: All tests pass, including every existing `FeedEngineTests` case unchanged.

- [ ] **Step 5: Commit**

```bash
git add packages/BibleFeedKit/Sources/BibleFeedKit/FeedEngine.swift \
        packages/BibleFeedKit/Tests/BibleFeedKitTests/FeedEngineTests.swift
git commit -m "$(cat <<'EOF'
Rank VerseIndexEntry instead of Verse in FeedEngine

FeedEngine only ever read id/tier/topics, so this is a type change,
not a logic change -- it lets the feed rank the full library without
needing every verse's translation text loaded.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add the `ShardStore` actor

**Files:**
- Create: `packages/BibleFeedKit/Sources/BibleFeedKit/ShardStore.swift`
- Create: `packages/BibleFeedKit/Tests/BibleFeedKitTests/ShardStoreTests.swift`

**Interfaces:**
- Consumes: `ContentShard`, `VerseContent` (from Task 1).
- Produces: `ShardStore.init(capacity: Int = 5, loadShard: @escaping @Sendable (Int) async throws -> Data)`, `func content(for ids: [String], shards: Set<Int>) async -> [String: VerseContent]`, `var cachedShardCount: Int { get async }`, `func isCached(_ shard: Int) async -> Bool`.

- [ ] **Step 1: Write the failing tests**

Create `packages/BibleFeedKit/Tests/BibleFeedKitTests/ShardStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleFeedKit

private func shardData(_ shard: Int, ids: [String]) -> Data {
    let verses = ids.map { id in
        """
        {"id":"\(id)","translations":{"KJV":{"text":"t","displayText":"t"}},"context":"c"}
        """
    }.joined(separator: ",")
    let json = """
    {"schemaVersion":3,"contentVersion":"test","verses":[\(verses)]}
    """
    return json.data(using: .utf8)!
}

private actor LoadCounter {
    private var counts: [Int: Int] = [:]
    func record(_ shard: Int) { counts[shard, default: 0] += 1 }
    func count(for shard: Int) -> Int { counts[shard] ?? 0 }
}

@Test func decodesRequestedShardAndReturnsMatchingContent() async {
    let store = ShardStore(capacity: 5) { shard in shardData(shard, ids: ["a\(shard)", "b\(shard)"]) }
    let result = await store.content(for: ["a0", "b0"], shards: [0])
    #expect(result["a0"]?.id == "a0")
    #expect(result["b0"]?.id == "b0")
}

@Test func cacheHitAvoidsRedecoding() async {
    let counter = LoadCounter()
    let store = ShardStore(capacity: 5) { shard in
        await counter.record(shard)
        return shardData(shard, ids: ["a\(shard)"])
    }
    _ = await store.content(for: ["a0"], shards: [0])
    _ = await store.content(for: ["a0"], shards: [0])
    let count = await counter.count(for: 0)
    #expect(count == 1)
}

@Test func lruEvictsOldestShardBeyondCapacity() async {
    let store = ShardStore(capacity: 2) { shard in shardData(shard, ids: ["v\(shard)"]) }
    _ = await store.content(for: ["v0"], shards: [0])
    _ = await store.content(for: ["v1"], shards: [1])
    _ = await store.content(for: ["v2"], shards: [2])
    let cached0 = await store.isCached(0)
    let cached1 = await store.isCached(1)
    let cached2 = await store.isCached(2)
    #expect(cached0 == false)
    #expect(cached1 == true)
    #expect(cached2 == true)
    let count = await store.cachedShardCount
    #expect(count == 2)
}

@Test func touchingCachedShardProtectsItFromEviction() async {
    let store = ShardStore(capacity: 2) { shard in shardData(shard, ids: ["v\(shard)"]) }
    _ = await store.content(for: ["v0"], shards: [0])
    _ = await store.content(for: ["v1"], shards: [1])
    _ = await store.content(for: ["v0"], shards: [0]) // re-touch shard 0
    _ = await store.content(for: ["v2"], shards: [2]) // should evict shard 1, not 0
    let cached0 = await store.isCached(0)
    let cached1 = await store.isCached(1)
    #expect(cached0 == true)
    #expect(cached1 == false)
}

@Test func concurrentOverlappingRequestsDoNotDoubleDecode() async {
    let counter = LoadCounter()
    let store = ShardStore(capacity: 5) { shard in
        await counter.record(shard)
        try? await Task.sleep(nanoseconds: 10_000_000)
        return shardData(shard, ids: ["a\(shard)"])
    }
    async let first = store.content(for: ["a0"], shards: [0])
    async let second = store.content(for: ["a0"], shards: [0])
    _ = await (first, second)
    let count = await counter.count(for: 0)
    #expect(count == 1)
}

@Test func failingShardDoesNotBlockOtherShardsInSameRequest() async {
    let store = ShardStore(capacity: 5) { shard in
        if shard == 1 { throw URLError(.fileDoesNotExist) }
        return shardData(shard, ids: ["v\(shard)"])
    }
    let result = await store.content(for: ["v0", "v1", "v2"], shards: [0, 1, 2])
    #expect(result["v0"] != nil)
    #expect(result["v1"] == nil)
    #expect(result["v2"] != nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail to build**

Run: `cd packages/BibleFeedKit && swift test`
Expected: Build error — `ShardStore` does not exist yet.

- [ ] **Step 3: Create `ShardStore.swift`**

```swift
import Foundation

/// Caches decoded shard content with a bounded LRU footprint, so memory use
/// stays constant regardless of how many verses the shipped library has
/// grown to.
public actor ShardStore {
    public typealias ShardLoader = @Sendable (Int) async throws -> Data

    private let loadShard: ShardLoader
    private let capacity: Int
    private var cache: [Int: [String: VerseContent]] = [:]
    private var lruOrder: [Int] = []
    private var inFlight: [Int: Task<[String: VerseContent], Error>] = [:]

    public init(capacity: Int = 5, loadShard: @escaping ShardLoader) {
        self.capacity = capacity
        self.loadShard = loadShard
    }

    /// Decodes any shard in `shardIndices` not already cached, then returns
    /// the merged id -> content map restricted to `ids`. A shard whose
    /// loader throws is skipped rather than failing the whole request, so
    /// one corrupt file only costs the verses inside it.
    public func content(for ids: [String], shards shardIndices: Set<Int>) async -> [String: VerseContent] {
        for shard in shardIndices {
            try? await ensureLoaded(shard)
        }
        var result: [String: VerseContent] = [:]
        for id in ids {
            for shard in shardIndices {
                if let content = cache[shard]?[id] {
                    result[id] = content
                    break
                }
            }
        }
        return result
    }

    public var cachedShardCount: Int { cache.count }
    public func isCached(_ shard: Int) -> Bool { cache[shard] != nil }

    private func ensureLoaded(_ shard: Int) async throws {
        if cache[shard] != nil {
            touch(shard)
            return
        }
        if let existing = inFlight[shard] {
            _ = try await existing.value
            touch(shard)
            return
        }
        let loader = loadShard
        let task = Task<[String: VerseContent], Error> {
            let data = try await loader(shard)
            let decoded = try JSONDecoder().decode(ContentShard.self, from: data)
            return Dictionary(uniqueKeysWithValues: decoded.verses.map { ($0.id, $0) })
        }
        inFlight[shard] = task
        do {
            let decoded = try await task.value
            cache[shard] = decoded
            inFlight[shard] = nil
            touch(shard)
            evictIfNeeded()
        } catch {
            inFlight[shard] = nil
            throw error
        }
    }

    private func touch(_ shard: Int) {
        lruOrder.removeAll { $0 == shard }
        lruOrder.append(shard)
    }

    private func evictIfNeeded() {
        while lruOrder.count > capacity {
            let oldest = lruOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/BibleFeedKit && swift test`
Expected: All tests pass, including all 7 new `ShardStoreTests` cases.

- [ ] **Step 5: Commit**

```bash
git add packages/BibleFeedKit/Sources/BibleFeedKit/ShardStore.swift \
        packages/BibleFeedKit/Tests/BibleFeedKitTests/ShardStoreTests.swift
git commit -m "$(cat <<'EOF'
Add ShardStore: LRU-capped on-demand content shard cache

An actor so concurrent overlapping requests for the same shard share
one decode instead of racing; a failing shard is skipped rather than
failing the whole request.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Build pipeline emits `feed_index.json` + shard files

**Files:**
- Modify: `tools/build_feed.py`

**Interfaces:**
- Produces on disk: `BibleApp/BibleApp/Resources/feed_index.json` and `BibleApp/BibleApp/Resources/feed_shard_NNNN.json` (4-digit, zero-padded), replacing `BibleApp/BibleApp/Resources/feed_verses.json`.

- [ ] **Step 1: Edit the output section of `tools/build_feed.py`**

Near the top of the file, replace:

```python
OUT = ROOT / "BibleApp" / "BibleApp" / "Resources" / "feed_verses.json"
CONTENT_VERSION = "2026-09-10.2"
```

with:

```python
OUT_DIR = ROOT / "BibleApp" / "BibleApp" / "Resources"
OUT_INDEX = OUT_DIR / "feed_index.json"
SHARD_SIZE = 100
CONTENT_VERSION = "2026-09-12.1"
```

At the end of `main()`, replace:

```python
    doc = {"schemaVersion": 2, "contentVersion": CONTENT_VERSION, "verses": verses}
    OUT.write_text(json.dumps(doc, indent=1, ensure_ascii=False))
    print(f"wrote {len(verses)} verses to {OUT.relative_to(ROOT)}")
```

with:

```python
    for old_shard in OUT_DIR.glob("feed_shard_*.json"):
        old_shard.unlink()

    index_entries = []
    for i, v in enumerate(verses):
        shard = i // SHARD_SIZE
        index_entries.append({
            "id": v["id"], "reference": v["reference"], "book": v["book"],
            "chapter": v["chapter"], "verse": v["verse"],
            "topics": v["topics"], "tier": v["tier"], "shard": shard,
        })

    index_doc = {"schemaVersion": 3, "contentVersion": CONTENT_VERSION, "verses": index_entries}
    OUT_INDEX.write_text(json.dumps(index_doc, indent=1, ensure_ascii=False))

    shard_count = (len(verses) + SHARD_SIZE - 1) // SHARD_SIZE if verses else 0
    for shard in range(shard_count):
        chunk = verses[shard * SHARD_SIZE:(shard + 1) * SHARD_SIZE]
        shard_verses = [{
            "id": v["id"], "translations": v["translations"], "context": v["context"],
        } for v in chunk]
        shard_doc = {"schemaVersion": 3, "contentVersion": CONTENT_VERSION, "verses": shard_verses}
        shard_path = OUT_DIR / f"feed_shard_{shard:04d}.json"
        shard_path.write_text(json.dumps(shard_doc, indent=1, ensure_ascii=False))

    print(f"wrote {len(index_entries)} verses to {OUT_INDEX.relative_to(ROOT)} "
          f"across {shard_count} shard file(s)")
```

- [ ] **Step 2: Run the existing build_feed unit tests to confirm nothing broke**

Run (from repo root): `python3 -m unittest tools.test_build_feed -v`
Expected: `Ran 14 tests ... OK` (these tests only exercise the display-text helper functions, unaffected by the output-writing change).

- [ ] **Step 3: Run the build script to regenerate the real shipped data**

Run (from repo root): `python3 tools/build_feed.py`
Expected output: `wrote 1000 verses to BibleApp/BibleApp/Resources/feed_index.json across 10 shard file(s)`

- [ ] **Step 4: Spot-check the generated files**

Run: `ls BibleApp/BibleApp/Resources/feed_shard_*.json | wc -l`
Expected: `10`

Run: `python3 -c "import json; d = json.load(open('BibleApp/BibleApp/Resources/feed_index.json')); print(d['schemaVersion'], len(d['verses']), d['verses'][0])"`
Expected: `3 1000 {'id': 'GEN.1.1', ... , 'shard': 0}` (schemaVersion 3, 1000 entries, first entry has a `shard` key).

- [ ] **Step 5: Remove the old combined file**

Run: `git rm BibleApp/BibleApp/Resources/feed_verses.json`

- [ ] **Step 6: Commit**

```bash
git add tools/build_feed.py BibleApp/BibleApp/Resources/feed_index.json \
        BibleApp/BibleApp/Resources/feed_shard_0000.json \
        BibleApp/BibleApp/Resources/feed_shard_0001.json \
        BibleApp/BibleApp/Resources/feed_shard_0002.json \
        BibleApp/BibleApp/Resources/feed_shard_0003.json \
        BibleApp/BibleApp/Resources/feed_shard_0004.json \
        BibleApp/BibleApp/Resources/feed_shard_0005.json \
        BibleApp/BibleApp/Resources/feed_shard_0006.json \
        BibleApp/BibleApp/Resources/feed_shard_0007.json \
        BibleApp/BibleApp/Resources/feed_shard_0008.json \
        BibleApp/BibleApp/Resources/feed_shard_0009.json
git commit -m "$(cat <<'EOF'
Build feed_index.json + shard files instead of one combined feed

Splits the shipped content into a lightweight index (always loaded
for feed ranking) and 100-verse shards (loaded on demand), per the
paginated-content-loading design.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

(If the actual verse count when this task runs is not exactly 1000, the shard file count and the list of `feed_shard_NNNN.json` paths above will differ accordingly — use `ls BibleApp/BibleApp/Resources/feed_shard_*.json` to get the real list before staging.)

---

## Task 5: `validate_feed.py` gains split-feed validation

**Files:**
- Modify: `tools/validate_feed.py`
- Modify: `tools/test_validate_feed.py`

**Interfaces:**
- Produces: `_validate_doc(doc: dict) -> list[str]` (extracted from the existing `validate_feed` body), `merge_split_feed(index_path, shards_dir) -> tuple[dict | None, list[str]]`, `validate_split_feed(index_path, shards_dir) -> list[str]`.
- Preserves: `validate_feed(path) -> list[str]` (unchanged behavior, unchanged existing tests) and the CLI's single-argument mode.

- [ ] **Step 1: Extract `_validate_doc` and add the merge/split functions**

In `tools/validate_feed.py`, replace the `validate_feed` function (currently starting `def validate_feed(path):` and ending right before `def main():`) with:

```python
def _validate_doc(doc):
    errors = []
    if not isinstance(doc, dict):
        errors.append(
            "feed file must contain a JSON object with a top-level "
            f"\"verses\" array, got {type(doc).__name__}")
        return errors

    try:
        index = _kjv_index()
    except SourceDataError as e:
        errors.append(f"source data error: {e}")
        return errors

    try:
        bsb_index = load_source_by_index(BSB_SOURCE)
    except SourceDataError as e:
        errors.append(f"source data error: {e}")
        return errors

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

    seen_ids = set()

    for entry in doc.get("verses", []):
        vid = entry.get("id", "<missing id>")

        if vid in seen_ids:
            errors.append(f"{vid}: duplicate id")
        seen_ids.add(vid)

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
            elif code == "BSB":
                if key not in bsb_index:
                    errors.append(f"{vid}: no such verse in BSB source")
                elif text != bsb_index[key]:
                    errors.append(f"{vid}: BSB text does not match BSB source")
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

        if vid != f"{key[0]}.{key[1]}.{key[2]}":
            errors.append(f"{vid}: id does not match book/chapter/verse fields")

        unknown = set(entry.get("topics", [])) - TOPICS
        if unknown:
            errors.append(f"{vid}: unknown topic {sorted(unknown)}")
        if not entry.get("topics"):
            errors.append(f"{vid}: topics must not be empty")

        if entry.get("tier") not in (1, 2, 3):
            errors.append(f"{vid}: tier must be 1, 2 or 3")

        ctx = entry.get("context", "")
        if not CONTEXT_MIN <= len(ctx) <= CONTEXT_MAX:
            errors.append(
                f"{vid}: context length {len(ctx)} outside {CONTEXT_MIN}-{CONTEXT_MAX}")

    return errors


def validate_feed(path):
    try:
        doc = json.loads(pathlib.Path(path).read_text())
    except OSError as e:
        return [f"failed to read feed file {path}: {e}"]
    except json.JSONDecodeError as e:
        return [f"feed file {path} contains invalid JSON: {e}"]
    return _validate_doc(doc)


def merge_split_feed(index_path, shards_dir):
    """Reassembles an index file + shard files into the combined shape
    _validate_doc's per-entry checks expect, and returns (doc, errors) where
    errors covers structural mismatches between the index and the shards (an
    id missing from its shard, a shard id absent from the index, a duplicate
    id across shards, or an index `shard` field pointing at the wrong file)
    that a single-file feed could never exhibit. `doc` is None only when the
    index file itself could not be read/parsed."""
    errors = []
    try:
        index_doc = json.loads(pathlib.Path(index_path).read_text())
    except OSError as e:
        return None, [f"failed to read index file {index_path}: {e}"]
    except json.JSONDecodeError as e:
        return None, [f"index file {index_path} contains invalid JSON: {e}"]

    index_entries = index_doc.get("verses", [])
    content_by_id = {}
    shard_of_id = {}
    shards_dir = pathlib.Path(shards_dir)
    for shard_path in sorted(shards_dir.glob("feed_shard_*.json")):
        m = re.match(r"feed_shard_(\d+)\.json$", shard_path.name)
        shard_number = int(m.group(1)) if m else None
        try:
            shard_doc = json.loads(shard_path.read_text())
        except (OSError, json.JSONDecodeError) as e:
            errors.append(f"failed to read shard file {shard_path}: {e}")
            continue
        for entry in shard_doc.get("verses", []):
            vid = entry.get("id")
            if vid in content_by_id:
                errors.append(f"{vid}: duplicate id across shard files")
            content_by_id[vid] = entry
            shard_of_id[vid] = shard_number

    index_ids = {e.get("id") for e in index_entries}
    orphan_shard_ids = set(content_by_id) - index_ids
    for vid in sorted(orphan_shard_ids):
        errors.append(f"{vid}: present in a shard file but not in the index")

    merged = []
    for entry in index_entries:
        vid = entry.get("id")
        content = content_by_id.get(vid)
        if content is None:
            errors.append(f"{vid}: in the index but missing from its shard file")
            continue
        if entry.get("shard") != shard_of_id.get(vid):
            errors.append(
                f"{vid}: index says shard {entry.get('shard')} but was found in "
                f"shard {shard_of_id.get(vid)}")
        merged.append({**entry, "translations": content.get("translations"),
                        "context": content.get("context")})

    doc = {"schemaVersion": index_doc.get("schemaVersion"),
           "contentVersion": index_doc.get("contentVersion"),
           "verses": merged}
    return doc, errors


def validate_split_feed(index_path, shards_dir):
    doc, merge_errors = merge_split_feed(index_path, shards_dir)
    if doc is None:
        return merge_errors
    return merge_errors + _validate_doc(doc)
```

- [ ] **Step 2: Update `main()` to support both CLI forms**

Replace the existing `main()`:

```python
def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate_feed.py <feed.json>")
    errors = validate_feed(sys.argv[1])
    for e in errors:
        print(e)
    print(f"{len(errors)} error(s)")
    sys.exit(1 if errors else 0)
```

with:

```python
def main():
    if len(sys.argv) == 2:
        errors = validate_feed(sys.argv[1])
    elif len(sys.argv) == 3:
        errors = validate_split_feed(sys.argv[1], sys.argv[2])
    else:
        raise SystemExit(
            "usage: validate_feed.py <feed.json> | validate_feed.py <feed_index.json> <shards_dir>")
    for e in errors:
        print(e)
    print(f"{len(errors)} error(s)")
    sys.exit(1 if errors else 0)
```

- [ ] **Step 3: Run the existing tests to confirm nothing broke**

Run (from repo root): `python3 -m unittest tools.test_validate_feed -v`
Expected: All 20 pre-existing tests still pass (they exercise `validate_feed(path)` and the single-arg CLI, both unchanged in behavior), but `ShippedFeedTests.test_shipped_feed_verses_has_no_errors` now fails since `feed_verses.json` no longer exists — that gets fixed in the next step.

- [ ] **Step 4: Add split-feed tests and fix the shipped-feed test**

In `tools/test_validate_feed.py`, replace the `ShippedFeedTests` class:

```python
class ShippedFeedTests(unittest.TestCase):
    """validate_feed.py has no automated coverage of the files the app
    actually ships. This is the permanent guard for that: run the real
    validator against the real shipped feed_index.json + feed_shard_*.json
    files, so bad data fails the build instead of only being caught by
    someone remembering to run the script by hand."""

    def test_shipped_feed_has_no_errors(self):
        resources = ROOT / "BibleApp" / "BibleApp" / "Resources"
        shipped_index = resources / "feed_index.json"
        self.assertTrue(shipped_index.is_file(), f"missing shipped feed index: {shipped_index}")
        self.assertEqual(vf.validate_split_feed(shipped_index, resources), [])
```

Then add a new class right before it:

```python
class ValidateSplitFeedTests(unittest.TestCase):
    def _write_split_feed(self, index_entries, shards):
        """shards: dict of shard_number -> list of content entries.
        Returns (index_path, shards_dir)."""
        td = pathlib.Path(tempfile.mkdtemp())
        index_doc = {"schemaVersion": 3, "contentVersion": "test", "verses": index_entries}
        index_path = td / "feed_index.json"
        index_path.write_text(json.dumps(index_doc))
        shards_dir = td / "shards"
        shards_dir.mkdir()
        for shard_number, entries in shards.items():
            shard_doc = {"schemaVersion": 3, "contentVersion": "test", "verses": entries}
            (shards_dir / f"feed_shard_{shard_number:04d}.json").write_text(json.dumps(shard_doc))
        return index_path, shards_dir

    def _valid_index_entry(self):
        return {"id": "JHN.3.16", "reference": "John 3:16", "book": "JHN",
                "chapter": 3, "verse": 16, "topics": ["love", "hope"],
                "tier": 1, "shard": 0}

    def _valid_content_entry(self):
        source = json.loads((FIX / "valid_feed.json").read_text())["verses"][0]
        return {"id": source["id"], "translations": source["translations"],
                "context": source["context"]}

    def test_valid_split_feed_has_no_errors(self):
        index_path, shards_dir = self._write_split_feed(
            [self._valid_index_entry()], {0: [self._valid_content_entry()]})
        self.assertEqual(vf.validate_split_feed(index_path, shards_dir), [])

    def test_catches_id_in_index_missing_from_shard(self):
        index_path, shards_dir = self._write_split_feed(
            [self._valid_index_entry()], {0: []})
        errs = vf.validate_split_feed(index_path, shards_dir)
        self.assertTrue(any("missing from its shard file" in e for e in errs), errs)

    def test_catches_id_in_shard_missing_from_index(self):
        index_path, shards_dir = self._write_split_feed(
            [], {0: [self._valid_content_entry()]})
        errs = vf.validate_split_feed(index_path, shards_dir)
        self.assertTrue(any("not in the index" in e for e in errs), errs)

    def test_catches_wrong_shard_number_in_index(self):
        entry = self._valid_index_entry()
        entry["shard"] = 7  # actually placed in shard 0 below
        index_path, shards_dir = self._write_split_feed(
            [entry], {0: [self._valid_content_entry()]})
        errs = vf.validate_split_feed(index_path, shards_dir)
        self.assertTrue(
            any("index says shard 7 but was found in shard 0" in e for e in errs), errs)

    def test_delegates_to_content_validation(self):
        # A wrong KJV translation text must surface the same error the
        # single-file validator reports, proving validate_split_feed reuses
        # the same per-entry checks after merging.
        content = self._valid_content_entry()
        content["translations"]["KJV"]["text"] = "Something never found in the KJV verse."
        index_path, shards_dir = self._write_split_feed(
            [self._valid_index_entry()], {0: [content]})
        errs = vf.validate_split_feed(index_path, shards_dir)
        self.assertTrue(any("text does not match KJV" in e for e in errs), errs)
```

- [ ] **Step 5: Run the tests to verify everything passes**

Run (from repo root): `python3 -m unittest tools.test_validate_feed -v`
Expected: All tests pass, including the 5 new `ValidateSplitFeedTests` cases and the updated `ShippedFeedTests` (validating the real files Task 4 generated).

- [ ] **Step 6: Commit**

```bash
git add tools/validate_feed.py tools/test_validate_feed.py
git commit -m "$(cat <<'EOF'
Add validate_split_feed for the index + shard file format

Reassembles the two file kinds and reuses the existing per-entry
content checks, plus new structural checks (orphan/missing ids,
wrong shard number) a single-file feed could never need.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Rewrite `ContentStore` to load the index and fetch content on demand

**Files:**
- Modify: `BibleApp/BibleApp/Content/ContentStore.swift`

**Interfaces:**
- Consumes: `FeedIndex`, `VerseIndexEntry`, `VerseContent`, `ShardStore` (from Tasks 1 and 3); the bundled `feed_index.json` and `feed_shard_NNNN.json` files (from Task 4).
- Produces: `ContentStore.index: [VerseIndexEntry]` (replaces `verses: [Verse]`), `ContentStore.loadFailed: Bool` (unchanged), `ContentStore.load()` (unchanged signature), `ContentStore.content(for ids: [String]) async -> [String: VerseContent]` (new).

There is no dedicated test target for the `BibleApp` app target (only the `BibleFeedKit` package has one), so this task is verified by compiling the app and by the manual simulator check in Task 9 — consistent with how `ContentStore` is verified today.

- [ ] **Step 1: Replace `BibleApp/BibleApp/Content/ContentStore.swift`**

```swift
import Foundation
import BibleFeedKit

@Observable
final class ContentStore {
    private(set) var index: [VerseIndexEntry] = []
    private(set) var loadFailed = false
    private var indexByID: [String: VerseIndexEntry] = [:]
    private let shardStore: ShardStore

    init() {
        shardStore = ShardStore(capacity: 5) { shard in
            let name = String(format: "feed_shard_%04d", shard)
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                throw ShardLoadError.missingShardFile(shard)
            }
            return try Data(contentsOf: url)
        }
    }

    func load() {
        guard let url = Bundle.main.url(forResource: "feed_index",
                                        withExtension: "json") else {
            fail("feed_index.json is missing from the bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(FeedIndex.self, from: data)
            index = decoded.verses
            indexByID = Dictionary(uniqueKeysWithValues: decoded.verses.map { ($0.id, $0) })
            loadFailed = false
        } catch {
            fail("feed_index.json failed to decode: \(error)")
        }
    }

    /// Loads (or returns already-cached) translation text and context for
    /// exactly the requested verse ids. A shard that fails to load is
    /// omitted from the result rather than failing the whole request -- the
    /// caller (a card left showing its skeleton) is the natural, scoped way
    /// to surface that gap.
    func content(for ids: [String]) async -> [String: VerseContent] {
        let shards = Set(ids.compactMap { indexByID[$0]?.shard })
        guard !shards.isEmpty else { return [:] }
        return await shardStore.content(for: ids, shards: shards)
    }

    private func fail(_ message: String) {
        // A decode failure is a programming or packaging error, not a user
        // condition, so make it loud in debug and recoverable in release.
        assertionFailure(message)
        index = []
        indexByID = [:]
        loadFailed = true
    }
}

private enum ShardLoadError: Error {
    case missingShardFile(Int)
}
```

- [ ] **Step 2: Build the app target to confirm it compiles**

Run: `cd BibleApp && xcodebuild build -project BibleApp.xcodeproj -scheme BibleApp -destination 'generic/platform=iOS Simulator' 2>&1 | tail -40`
Expected: `BUILD FAILED` — `FeedView.swift`, `VerseCard.swift`, and `LibraryView.swift` still reference the old `store.verses: [Verse]` API. This is expected; they get fixed in Tasks 7 and 8.

- [ ] **Step 3: Commit**

```bash
git add BibleApp/BibleApp/Content/ContentStore.swift
git commit -m "$(cat <<'EOF'
Load feed_index.json eagerly, fetch shard content on demand

ContentStore now exposes the lightweight index plus a
content(for:) accessor backed by ShardStore, instead of decoding
every verse's translations and context at launch.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

(The build failure in Step 2 is expected and intentionally committed through -- `FeedView`/`VerseCard`/`LibraryView` are fixed in the next two tasks. If you'd rather keep every commit green, do Tasks 6-8 as one combined commit instead; either way, do not skip Step 2's build check, it's what confirms `ContentStore`'s own code is correct in isolation.)

---

## Task 7: Update `FeedView` and `VerseCard` for lazy content + skeleton loading

**Files:**
- Modify: `BibleApp/BibleApp/Views/FeedView.swift`
- Modify: `BibleApp/BibleApp/Views/VerseCard.swift`

**Interfaces:**
- Consumes: `ContentStore.index`, `ContentStore.content(for:)` (from Task 6); `VerseIndexEntry`, `VerseContent`, `FeedEngine` (from Tasks 1-2).
- Produces: `VerseCard.init(entry: VerseIndexEntry, content: VerseContent?, translation: Translation, isSaved: Bool, onSave: () -> Void)` (replaces the old `verse: Verse` parameter).

- [ ] **Step 1: Replace `BibleApp/BibleApp/Views/VerseCard.swift`**

```swift
import SwiftUI
import BibleFeedKit

struct VerseCard: View {
    let entry: VerseIndexEntry
    let content: VerseContent?
    let translation: Translation
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            Group {
                if let content {
                    Text(content.translations[translation]?.displayText
                         ?? content.translations[.kjv]?.displayText ?? "")
                        .font(.system(.title2, design: .serif))
                        .lineSpacing(6)
                        .transition(.opacity)
                } else {
                    SkeletonBlock(lines: 3)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: content)

            Text(entry.reference)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Divider()

            Group {
                if let content {
                    Text(content.context)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .transition(.opacity)
                } else {
                    SkeletonBlock(lines: 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: content)

            Spacer()

            HStack {
                ForEach(entry.topics, id: \.self) { topic in
                    Text(topic.rawValue.capitalized)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                Spacer()
                Button(action: onSave) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.title3)
                }
                .accessibilityLabel(isSaved ? "Remove from saved" : "Save verse")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SkeletonBlock: View {
    let lines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<lines, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 16)
            }
        }
        .redacted(reason: .placeholder)
    }
}
```

- [ ] **Step 2: Replace `BibleApp/BibleApp/Views/FeedView.swift`**

```swift
import SwiftUI
import BibleFeedKit

struct FeedView: View {
    let store: ContentStore
    let state: UserState

    @State private var queue: [VerseIndexEntry] = []
    @State private var loadedContent: [String: VerseContent] = [:]
    @State private var isReplay = false
    @State private var seenTasks: [String: Task<Void, Never>] = [:]
    @State private var showLibrary = false

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                if isReplay {
                    MilestoneCard(count: store.index.count)
                        .containerRelativeFrame(.vertical)
                }
                ForEach(Array(queue.enumerated()), id: \.element.id) { position, entry in
                    VerseCard(entry: entry,
                              content: loadedContent[entry.id],
                              translation: state.preferredTranslation,
                              isSaved: state.savedSet.contains(entry.id),
                              onSave: { state.toggleSaved(entry.id) })
                        .containerRelativeFrame(.vertical)
                        .onAppear {
                            startSeenTimer(entry)
                            loadContent(around: position)
                        }
                        .onDisappear { cancelSeenTimer(entry) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            HStack {
                Label("\(state.streak)", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.streak > 0 ? .orange : .secondary)
                Spacer()
                Button {
                    showLibrary = true
                } label: {
                    Image(systemName: "bookmark")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Saved verses")
            }
            .padding(.horizontal, 24)
            .safeAreaPadding(.top, 8)
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView(store: store, state: state)
        }
        .onAppear(perform: rebuild)
    }

    private func rebuild() {
        let engine = FeedEngine(verses: store.index)
        let result = engine.queue(selectedTopics: state.topics,
                                  seen: state.seenSet,
                                  saved: state.savedSet,
                                  seed: UInt64.random(in: 0...UInt64.max))
        queue = result.verses
        isReplay = result.isReplay
        loadContent(around: 0)
    }

    /// Fetches content for the card at `position` plus the next one, since
    /// the feed pages forward through `queue` in order.
    private func loadContent(around position: Int) {
        guard queue.indices.contains(position) else { return }
        let end = min(queue.count, position + 2)
        let ids = queue[position..<end].map(\.id).filter { loadedContent[$0] == nil }
        guard !ids.isEmpty else { return }
        Task {
            let content = await store.content(for: ids)
            for (id, value) in content {
                loadedContent[id] = value
            }
        }
    }

    /// A card counts as seen only after two seconds on screen, so a flick
    /// past does not consume it.
    private func startSeenTimer(_ entry: VerseIndexEntry) {
        guard seenTasks[entry.id] == nil else { return }
        seenTasks[entry.id] = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            state.markSeen(entry.id)
        }
    }

    private func cancelSeenTimer(_ entry: VerseIndexEntry) {
        seenTasks[entry.id]?.cancel()
        seenTasks[entry.id] = nil
    }
}

private struct MilestoneCard: View {
    let count: Int

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("You've read all \(count) verses")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Starting again with the ones you saved.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
```

- [ ] **Step 3: Build the app target**

Run: `cd BibleApp && xcodebuild build -project BibleApp.xcodeproj -scheme BibleApp -destination 'generic/platform=iOS Simulator' 2>&1 | tail -40`
Expected: Still `BUILD FAILED` — `LibraryView.swift` still references the old API. Fixed in Task 8.

- [ ] **Step 4: Commit**

```bash
git add BibleApp/BibleApp/Views/FeedView.swift BibleApp/BibleApp/Views/VerseCard.swift
git commit -m "$(cat <<'EOF'
Load verse content lazily in the feed with a skeleton placeholder

Each card prefetches its own and the next card's content shard on
appear; VerseCard cross-fades from a redacted skeleton to the real
text once content resolves.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Update `LibraryView` for index-based filtering + on-demand content

**Files:**
- Modify: `BibleApp/BibleApp/Views/LibraryView.swift`

**Interfaces:**
- Consumes: `ContentStore.index`, `ContentStore.content(for:)` (from Task 6).

- [ ] **Step 1: Replace `BibleApp/BibleApp/Views/LibraryView.swift`**

```swift
import SwiftUI
import BibleFeedKit

struct LibraryView: View {
    let store: ContentStore
    let state: UserState

    @Environment(\.dismiss) private var dismiss
    @State private var filter: Topic?
    @State private var loadedContent: [String: VerseContent] = [:]

    private var savedEntries: [VerseIndexEntry] {
        let savedSet = state.savedSet
        return store.index
            .filter { savedSet.contains($0.id) }
            .filter { filter == nil || $0.topics.contains(filter!) }
    }

    private var availableTopics: [Topic] {
        let savedSet = state.savedSet
        let topics = store.index
            .filter { savedSet.contains($0.id) }
            .flatMap(\.topics)
        return Array(Set(topics)).sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if state.savedIDs.isEmpty {
                    ContentUnavailableView("Nothing saved yet",
                                           systemImage: "bookmark",
                                           description: Text("Tap the bookmark on a verse to keep it here."))
                } else {
                    List {
                        if !availableTopics.isEmpty {
                            Section {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 8) {
                                        FilterChip(title: "All", isOn: filter == nil) { filter = nil }
                                        ForEach(availableTopics, id: \.self) { topic in
                                            FilterChip(title: topic.rawValue.capitalized,
                                                       isOn: filter == topic) { filter = topic }
                                        }
                                    }
                                }
                                .scrollIndicators(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        }
                        ForEach(savedEntries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                if let content = loadedContent[entry.id] {
                                    Text(content.translations[state.preferredTranslation]?.displayText
                                         ?? content.translations[.kjv]?.displayText ?? "")
                                        .font(.system(.body, design: .serif))
                                } else {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.secondarySystemBackground))
                                        .frame(height: 18)
                                        .redacted(reason: .placeholder)
                                }
                                Text(entry.reference)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    state.toggleSaved(entry.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit topics") {
                        state.reopenTopicPicker()
                        dismiss()
                    }
                    .font(.subheadline)
                }
            }
            .task(id: savedEntries.map(\.id)) {
                let ids = savedEntries.map(\.id).filter { loadedContent[$0] == nil }
                guard !ids.isEmpty else { return }
                let content = await store.content(for: ids)
                for (id, value) in content {
                    loadedContent[id] = value
                }
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(isOn ? Color.accentColor : Color(.secondarySystemBackground))
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .clipShape(Capsule())
    }
}
```

- [ ] **Step 2: Build the app target**

Run: `cd BibleApp && xcodebuild build -project BibleApp.xcodeproj -scheme BibleApp -destination 'generic/platform=iOS Simulator' 2>&1 | tail -40`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add BibleApp/BibleApp/Views/LibraryView.swift
git commit -m "$(cat <<'EOF'
Load Library content on demand from the shared ShardStore

Saved verses are filtered from the lightweight index; their
translation text/context loads lazily and shares ShardStore's cache
with the feed.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Build and manually verify in the iOS Simulator

**Files:** none (verification only).

- [ ] **Step 1: Run the full automated test suite one more time**

```bash
cd packages/BibleFeedKit && swift test
cd /Users/vietdo/Documents/GitHub/BibleApp && python3 -m unittest tools.test_build_feed tools.test_validate_feed -v
```
Expected: everything green.

- [ ] **Step 2: Build for the simulator**

Run: `cd BibleApp && xcodebuild build -project BibleApp.xcodeproj -scheme BibleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -40`
Expected: `BUILD SUCCEEDED`. (If `iPhone 17 Pro` is not an available simulator on this machine, run `xcrun simctl list devices available` and substitute an available iPhone.)

- [ ] **Step 3: Launch in the simulator and verify the feed**

Use the iOS Simulator tool: attach to a booted simulator (boot one first if needed), then build/launch `BibleApp`. Confirm:
- The feed opens and shows real verse text within a moment (a very brief skeleton on the very first card is acceptable; text must not stay skeletonized).
- Swiping forward through several cards continues to show real text with no lingering skeletons more than a card ahead of the current scroll position.
- Tapping the bookmark icon saves a verse, then opening the Library sheet (bookmark icon top-right) shows that verse's real text, not a permanent placeholder.
- The topic filter chips in Library still work.

If any card shows a permanent skeleton, check the console log for `ShardLoadError.missingShardFile` (via `inspect`/simulator logs) -- that would mean the flat `feed_shard_NNNN.json` bundling assumption in the Global Constraints section was wrong for this Xcode project, and the fallback is to pass `subdirectory: "feed_shards"` (or wherever `xcodebuild` actually placed the files -- check with `find <DerivedData path>/Build/Products/Debug-iphonesimulator/BibleApp.app -name 'feed_shard*'`) to both `Bundle.main.url(forResource:withExtension:)` calls in `ContentStore.swift`.

- [ ] **Step 4: Report results**

No commit for this task -- it's verification only. If Step 3 uncovers a real bug, fix it in the relevant task's file, re-run that task's build/test commands, and commit the fix with a message describing what was wrong.
