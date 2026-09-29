import Foundation

/// The verses of one timed reflection session and how far the reader has
/// got. Captured from the Feed queue when the session starts.
public struct SessionQueue: Codable, Equatable, Sendable {
    public let ids: [String]
    public let endDate: Date
    public private(set) var position: Int

    public init?(ids: [String], endDate: Date) {
        guard !ids.isEmpty else { return nil }
        self.ids = ids
        self.endDate = endDate
        self.position = 0
    }

    public var current: String { ids[position] }

    /// Verses reached so far, counting the one on screen.
    public var versesRead: Int { position + 1 }

    /// Moves to the next verse. Returns false, leaving the position alone,
    /// when the current verse is the last one.
    public mutating func advance() -> Bool {
        guard position + 1 < ids.count else { return false }
        position += 1
        return true
    }

    public func isExpired(now: Date) -> Bool {
        now >= endDate
    }
}
