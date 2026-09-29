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

    private enum CodingKeys: String, CodingKey {
        case ids, endDate, position
    }

    /// Rejects a file the initializer could never have produced, so a
    /// corrupt session can't trap `current`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ids = try container.decode([String].self, forKey: .ids)
        let position = try container.decode(Int.self, forKey: .position)
        guard ids.indices.contains(position) else {
            throw DecodingError.dataCorruptedError(
                forKey: .position, in: container,
                debugDescription: "Session position is outside its ids.")
        }
        self.ids = ids
        self.endDate = try container.decode(Date.self, forKey: .endDate)
        self.position = position
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
