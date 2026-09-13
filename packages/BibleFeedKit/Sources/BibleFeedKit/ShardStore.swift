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
    ///
    /// Each shard's matching content is collected immediately after it
    /// loads, before moving to the next shard, so that a later shard's
    /// load evicting an earlier shard from the LRU cache can't erase data
    /// already gathered for this result.
    public func content(for ids: [String], shards shardIndices: Set<Int>) async -> [String: VerseContent] {
        let wanted = Set(ids)
        var result: [String: VerseContent] = [:]
        for shard in shardIndices {
            try? await ensureLoaded(shard)
            guard let decoded = cache[shard] else { continue }
            for (id, content) in decoded where wanted.contains(id) {
                result[id] = content
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
            let decoded = try await existing.value
            store(decoded, for: shard)
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
            inFlight[shard] = nil
            store(decoded, for: shard)
        } catch {
            inFlight[shard] = nil
            throw error
        }
    }

    private func store(_ decoded: [String: VerseContent], for shard: Int) {
        cache[shard] = decoded
        touch(shard)
        evictIfNeeded()
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
