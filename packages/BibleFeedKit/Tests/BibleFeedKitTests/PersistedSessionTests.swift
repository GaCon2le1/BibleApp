import Testing
import Foundation
@testable import BibleFeedKit

private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "PersistedSessionTests-\(UUID().uuidString)")
        .appending(path: "session.json")
}

private func sampleSession() -> PersistedSession {
    PersistedSession(activityID: "activity-1",
                     queue: SessionQueue(ids: ["A", "B"],
                                         endDate: Date(timeIntervalSince1970: 1_000))!)
}

@Test func savedSessionLoadsBack() throws {
    let url = temporaryURL()
    let session = sampleSession()
    try session.save(to: url)
    #expect(PersistedSession.load(from: url) == session)
}

@Test func missingFileLoadsNil() {
    #expect(PersistedSession.load(from: temporaryURL()) == nil)
}

@Test func corruptFileLoadsNil() throws {
    let url = temporaryURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    #expect(PersistedSession.load(from: url) == nil)
}

@Test func deleteRemovesTheFile() throws {
    let url = temporaryURL()
    try sampleSession().save(to: url)
    PersistedSession.delete(at: url)
    #expect(PersistedSession.load(from: url) == nil)
}
