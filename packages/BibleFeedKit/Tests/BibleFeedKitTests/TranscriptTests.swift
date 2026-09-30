import Testing
import Foundation
@testable import BibleFeedKit

private let transcript = Transcript(lines: [
    TranscriptLine(start: 2, text: "Một"),
    TranscriptLine(start: 5, text: "Hai"),
    TranscriptLine(start: 9, text: "Ba"),
])

@Test func noLineBeforeTheFirstStarts() {
    #expect(transcript.line(at: 0) == nil)
    #expect(transcript.line(at: 1.99) == nil)
}

@Test func lineStartsExactlyAtItsStart() {
    #expect(transcript.line(at: 2)?.text == "Một")
    #expect(transcript.line(at: 5)?.text == "Hai")
}

@Test func lineStaysUpUntilTheNextOne() {
    #expect(transcript.line(at: 4.99)?.text == "Một")
    #expect(transcript.line(at: 8)?.text == "Hai")
}

@Test func lastLineStaysUpAfterItStarts() {
    #expect(transcript.line(at: 500)?.text == "Ba")
}

@Test func emptyTranscriptHasNoLine() {
    #expect(Transcript(lines: []).line(at: 3) == nil)
}

@Test func linesAreSortedByStart() {
    let unsorted = Transcript(lines: [TranscriptLine(start: 5, text: "B"), TranscriptLine(start: 1, text: "A")])
    #expect(unsorted.lines.map(\.text) == ["A", "B"])
    #expect(unsorted.line(at: 2)?.text == "A")
}

@Test func decodesToolOutputIgnoringEnd() throws {
    let json = #"{"lines": [{"start": 5.5, "end": 7, "text": "Hai"}, {"start": 1.25, "end": 5.5, "text": "Một"}]}"#
    let decoded = try Transcript.decode(Data(json.utf8))
    #expect(decoded.lines == [TranscriptLine(start: 1.25, text: "Một"), TranscriptLine(start: 5.5, text: "Hai")])
}
