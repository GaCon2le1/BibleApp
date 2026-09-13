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
    let (firstResult, secondResult) = await (first, second)
    #expect(firstResult["a0"]?.id == "a0")
    #expect(secondResult["a0"]?.id == "a0")
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

@Test func requestSpanningMoreShardsThanCapacityReturnsAllIds() async {
    let store = ShardStore(capacity: 5) { shard in shardData(shard, ids: ["v\(shard)"]) }
    let ids = (0..<10).map { "v\($0)" }
    let shards = Set(0..<10)
    let result = await store.content(for: ids, shards: shards)
    for id in ids {
        #expect(result[id]?.id == id, "missing or wrong content for \(id)")
    }
}
