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
