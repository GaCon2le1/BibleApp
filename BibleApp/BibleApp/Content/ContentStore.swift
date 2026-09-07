import Foundation
import BibleFeedKit

@Observable
final class ContentStore {
    private(set) var verses: [Verse] = []
    private(set) var loadFailed = false

    func load() {
        guard let url = Bundle.main.url(forResource: "feed_verses",
                                        withExtension: "json") else {
            fail("feed_verses.json is missing from the bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let content = try JSONDecoder().decode(FeedContent.self, from: data)
            verses = content.verses
            loadFailed = false
        } catch {
            fail("feed_verses.json failed to decode: \(error)")
        }
    }

    private func fail(_ message: String) {
        // A decode failure is a programming or packaging error, not a user
        // condition, so make it loud in debug and recoverable in release.
        assertionFailure(message)
        verses = []
        loadFailed = true
    }
}
