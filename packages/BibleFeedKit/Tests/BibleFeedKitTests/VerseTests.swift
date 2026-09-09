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
