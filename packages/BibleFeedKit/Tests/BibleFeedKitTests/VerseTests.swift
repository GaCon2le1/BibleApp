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
