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

@Test func indexFollowsLineStarts() {
    #expect(transcript.index(at: 1) == nil)
    #expect(transcript.index(at: 2) == 0)
    #expect(transcript.index(at: 6) == 1)
    #expect(transcript.index(at: 99) == 2)
}

@Test func windowBeforeTheFirstLineShowsItAsNext() {
    #expect(transcript.window(at: 0) == LyricWindow(previous: nil, current: nil, next: "Một"))
}

@Test func windowInTheMiddleHasBothNeighbours() {
    #expect(transcript.window(at: 6) == LyricWindow(previous: "Một", current: "Hai", next: "Ba"))
}

@Test func windowAtTheFirstAndLastLines() {
    #expect(transcript.window(at: 2) == LyricWindow(previous: nil, current: "Một", next: "Hai"))
    #expect(transcript.window(at: 99) == LyricWindow(previous: "Hai", current: "Ba", next: nil))
}

@Test func windowOfEmptyTranscriptIsEmpty() {
    #expect(Transcript(lines: []).window(at: 5) == LyricWindow(previous: nil, current: nil, next: nil))
}
