import Foundation

/// How far into each episode the listener got, in seconds. Written every few
/// seconds while playing, so it lives in `UserDefaults` rather than SwiftData.
struct PlaybackProgressStore {
    private let defaults: UserDefaults
    private let key = "audio.positions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func position(for episodeID: String) -> Double? {
        positions[episodeID]
    }

    func save(_ seconds: Double, for episodeID: String) {
        var all = positions
        all[episodeID] = seconds
        defaults.set(all, forKey: key)
    }

    private var positions: [String: Double] {
        defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }
}
