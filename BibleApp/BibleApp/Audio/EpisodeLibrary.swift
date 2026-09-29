import Foundation
import BibleFeedKit

/// The episodes listed in the bundled `episodes.json` whose audio file is
/// actually in the bundle.
struct EpisodeLibrary {
    let episodes: [Episode]

    static let bundled = EpisodeLibrary(bundle: .main)

    init(bundle: Bundle) {
        guard let url = bundle.url(forResource: "episodes", withExtension: "json") else {
            assertionFailure("episodes.json is missing from the bundle")
            episodes = []
            return
        }
        do {
            let all = try EpisodeCatalog.decode(Data(contentsOf: url))
            episodes = all.filter { episode in
                let found = Self.fileURL(for: episode, in: bundle) != nil
                assert(found, "\(episode.file) is missing from the bundle")
                return found
            }
        } catch {
            assertionFailure("episodes.json failed to decode: \(error)")
            episodes = []
        }
    }

    static func fileURL(for episode: Episode, in bundle: Bundle = .main) -> URL? {
        let name = (episode.file as NSString).deletingPathExtension
        let ext = (episode.file as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: ext)
    }
}
