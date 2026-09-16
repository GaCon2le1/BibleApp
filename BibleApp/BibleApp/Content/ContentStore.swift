import Foundation
import BibleFeedKit

@Observable
final class ContentStore {
    private(set) var index: [VerseIndexEntry] = []
    private(set) var loadFailed = false
    private var indexByID: [String: VerseIndexEntry] = [:]
    private var audioIDs: Set<String> = []
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
        loadAudioIndex()
    }

    /// Whether `id` has a narrated (KJV) clip bundled. `VerseCard` uses this
    /// to hide its Listen control on a card with no audio, rather than
    /// showing a control that would silently do nothing.
    func hasAudio(for id: String) -> Bool {
        audioIDs.contains(id)
    }

    /// `nil` if `id` has no bundled clip (see `hasAudio`) — callers that
    /// reach this without checking `hasAudio` first (e.g. a stale queue
    /// built before a data update) get a safe nil rather than a URL to a
    /// missing file.
    func audioURL(for id: String) -> URL? {
        guard audioIDs.contains(id) else { return nil }
        return Bundle.main.url(forResource: id, withExtension: "m4a", subdirectory: "Audio")
    }

    /// A missing or corrupt `audio_index.json` disables Listen mode only —
    /// unlike `feed_index.json`, it does not fail the whole app, since the
    /// feed itself does not depend on audio.
    private func loadAudioIndex() {
        guard let url = Bundle.main.url(forResource: "audio_index", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AudioIndex.self, from: data)
        else {
            audioIDs = []
            return
        }
        audioIDs = Set(decoded.entries.map(\.id))
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
