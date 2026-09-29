import Foundation

/// One listenable audio episode bundled with the app.
public struct Episode: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    /// Bundle file name including its extension, e.g. "test.mp3".
    public let file: String
    public let durationSeconds: Double

    public init(id: String, title: String, subtitle: String, file: String, durationSeconds: Double) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.file = file
        self.durationSeconds = durationSeconds
    }
}

/// Reads `episodes.json`: `{"episodes": [Episode]}`.
public enum EpisodeCatalog {
    private struct Root: Decodable {
        let episodes: [Episode]
    }

    public static func decode(_ data: Data) throws -> [Episode] {
        try JSONDecoder().decode(Root.self, from: data).episodes
    }
}
