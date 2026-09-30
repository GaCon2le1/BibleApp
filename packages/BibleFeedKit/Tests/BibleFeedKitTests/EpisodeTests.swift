import Testing
import Foundation
@testable import BibleFeedKit

@Test func catalogDecodesEpisodes() throws {
    let json = """
    {"episodes": [{"id": "test", "title": "Test Episode", "subtitle": "Sample",
                   "file": "test.mp3", "durationSeconds": 1469.136}]}
    """
    let episodes = try EpisodeCatalog.decode(Data(json.utf8))
    #expect(episodes == [Episode(id: "test", title: "Test Episode", subtitle: "Sample",
                                 file: "test.mp3", durationSeconds: 1469.136)])
}

@Test func catalogWithoutEpisodesKeyThrows() {
    #expect(throws: (any Error).self) {
        try EpisodeCatalog.decode(Data(#"{"items": []}"#.utf8))
    }
}

@Test func catalogEpisodeMissingFieldThrows() {
    let json = #"{"episodes": [{"id": "test", "title": "T", "subtitle": "S", "file": "a.mp3"}]}"#
    #expect(throws: (any Error).self) {
        try EpisodeCatalog.decode(Data(json.utf8))
    }
}

@Test func playbackTimeFormatsMinutesAndHours() {
    #expect(PlaybackTime.format(0) == "0:00")
    #expect(PlaybackTime.format(9.9) == "0:09")
    #expect(PlaybackTime.format(65) == "1:05")
    #expect(PlaybackTime.format(1469.136) == "24:29")
    #expect(PlaybackTime.format(3600) == "1:00:00")
    #expect(PlaybackTime.format(3725) == "1:02:05")
}

@Test func playbackTimeShowsNegativeAndNonFiniteAsZero() {
    #expect(PlaybackTime.format(-3) == "0:00")
    #expect(PlaybackTime.format(.nan) == "0:00")
    #expect(PlaybackTime.format(.infinity) == "0:00")
}

@Test func catalogReadsOptionalTranscript() throws {
    let json = """
    {"episodes": [{"id": "a", "title": "A", "subtitle": "S", "file": "a.mp3",
                   "durationSeconds": 10, "transcript": "a.transcript.json"},
                  {"id": "b", "title": "B", "subtitle": "S", "file": "b.mp3",
                   "durationSeconds": 10}]}
    """
    let episodes = try EpisodeCatalog.decode(Data(json.utf8))
    #expect(episodes.map(\.transcript) == ["a.transcript.json", nil])
}
