import Foundation

/// One karaoke line: shown from `start` until the next line begins.
public struct TranscriptLine: Codable, Hashable, Sendable {
    public let start: Double
    public let text: String

    public init(start: Double, text: String) {
        self.start = start
        self.text = text
    }
}

/// Timed lines for an episode, written by `tools/transcribe_audio.py`.
public struct Transcript: Codable, Hashable, Sendable {
    /// Sorted by `start`.
    public let lines: [TranscriptLine]

    public init(lines: [TranscriptLine]) {
        self.lines = lines.sorted { $0.start < $1.start }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(lines: try container.decode([TranscriptLine].self, forKey: .lines))
    }

    public static func decode(_ data: Data) throws -> Transcript {
        try JSONDecoder().decode(Transcript.self, from: data)
    }

    /// Position in `lines` of the line being spoken at `seconds`: the last
    /// one that has started, so a line stays up through the pause after it.
    /// Nil before the first line.
    public func index(at seconds: Double) -> Int? {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].start <= seconds {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low == 0 ? nil : low - 1
    }

    /// The line being spoken at `seconds`; nil before the first line.
    public func line(at seconds: Double) -> TranscriptLine? {
        index(at: seconds).map { lines[$0] }
    }

    /// The spoken line with the lines either side of it, for the lyrics card.
    public func window(at seconds: Double) -> LyricWindow {
        guard let index = index(at: seconds) else {
            return LyricWindow(previous: nil, current: nil, next: lines.first?.text)
        }
        return LyricWindow(previous: index > 0 ? lines[index - 1].text : nil,
                           current: lines[index].text,
                           next: index + 1 < lines.count ? lines[index + 1].text : nil)
    }
}

/// Three consecutive transcript lines around the playback position.
public struct LyricWindow: Equatable, Sendable {
    public let previous: String?
    public let current: String?
    public let next: String?

    public init(previous: String?, current: String?, next: String?) {
        self.previous = previous
        self.current = current
        self.next = next
    }
}
