import Testing
import Foundation
@testable import BibleFeedKit

private let sampleJSON = """
{
  "schemaVersion": 1,
  "contentVersion": "test",
  "entries": [
    { "id": "PSA.23.1", "durationMs": 8200 },
    { "id": "JHN.3.16", "durationMs": 11400 }
  ]
}
""".data(using: .utf8)!

@Test func decodesAudioIndex() throws {
    let index = try JSONDecoder().decode(AudioIndex.self, from: sampleJSON)
    #expect(index.schemaVersion == 1)
    #expect(index.entries.count == 2)
    #expect(index.entries[0].id == "PSA.23.1")
    #expect(index.entries[0].durationMs == 8200)
}

@Test func roundTripsThroughEncodeDecode() throws {
    let entry = VerseAudioEntry(id: "PSA.23.1", durationMs: 8200)
    let data = try JSONEncoder().encode(entry)
    let decoded = try JSONDecoder().decode(VerseAudioEntry.self, from: data)
    #expect(decoded == entry)
}
