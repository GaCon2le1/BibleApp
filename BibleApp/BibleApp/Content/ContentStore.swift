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
