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
