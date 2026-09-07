import Foundation
import SwiftData
import BibleFeedKit

@Model
final class UserState {
    var seenIDs: [String] = []
    var savedIDs: [String] = []
    var topicsRaw: [String] = []
    var activeDays: [Date] = []
    var hasCompletedOnboarding: Bool = false

    init() {}

    var topics: Set<Topic> {
        Set(topicsRaw.compactMap(Topic.init(rawValue:)))
    }

    var seenSet: Set<String> { Set(seenIDs) }
    var savedSet: Set<String> { Set(savedIDs) }

    var streak: Int {
        StreakCalculator.currentStreak(activeDays: Set(activeDays), today: .now)
    }

    func setTopics(_ topics: Set<Topic>) {
        topicsRaw = topics.map(\.rawValue).sorted()
        hasCompletedOnboarding = true
    }

    /// Marking a card seen is also what counts a day toward the streak.
    func markSeen(_ id: String) {
        if !seenIDs.contains(id) {
            seenIDs.append(id)
        }
        let today = Calendar.current.startOfDay(for: .now)
        if !activeDays.contains(where: { Calendar.current.isDate($0, inSameDayAs: today) }) {
            activeDays.append(today)
        }
    }

    func toggleSaved(_ id: String) {
        if let index = savedIDs.firstIndex(of: id) {
            savedIDs.remove(at: index)
        } else {
            savedIDs.append(id)
        }
    }

    func reopenTopicPicker() {
        hasCompletedOnboarding = false
    }
}
