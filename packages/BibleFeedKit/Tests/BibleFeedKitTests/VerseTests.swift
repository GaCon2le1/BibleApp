import Testing
import Foundation
@testable import BibleFeedKit

private let sampleJSON = """
{
  "schemaVersion": 1,
  "contentVersion": "test",
  "translation": "KJV",
  "verses": [
    {
      "id": "JHN.3.16", "reference": "John 3:16",
      "book": "JHN", "chapter": 3, "verse": 16,
      "text": "A Psalm of David. For God so loved the world",
      "displayText": "For God so loved the world",
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
    #expect(content.verses[0].id == "JHN.3.16")
    #expect(content.verses[0].topics == [.love, .hope])
    #expect(content.verses[0].tier == 1)
    // displayText is the card-facing form; text keeps the source prefix.
    #expect(content.verses[0].displayText == "For God so loved the world")
    #expect(content.verses[0].text.hasSuffix(content.verses[0].displayText))
}

@Test func topicHasTwelveCases() {
    #expect(Topic.allCases.count == 12)
}

@Test func unknownTopicFailsDecoding() {
    let bad = """
    {"schemaVersion":1,"contentVersion":"t","translation":"KJV","verses":[
      {"id":"A.1.1","reference":"A 1:1","book":"A","chapter":1,"verse":1,
       "text":"x","displayText":"x","context":"y","topics":["prosperity"],"tier":1}]}
    """.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(FeedContent.self, from: bad)
    }
}
