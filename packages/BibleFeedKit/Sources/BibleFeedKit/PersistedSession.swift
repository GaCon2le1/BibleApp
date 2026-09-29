import Foundation

/// The running session as written to disk, so a Lock Screen button can pick
/// it up again after the app has been terminated.
public struct PersistedSession: Codable, Equatable, Sendable {
    public let activityID: String
    public var queue: SessionQueue

    public init(activityID: String, queue: SessionQueue) {
        self.activityID = activityID
        self.queue = queue
    }

    public static func load(from url: URL) -> PersistedSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedSession.self, from: data)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
