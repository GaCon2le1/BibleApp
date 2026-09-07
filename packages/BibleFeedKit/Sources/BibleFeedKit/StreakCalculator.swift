import Foundation

public enum StreakCalculator {
    /// Counts back from today over consecutive days that saw activity.
    /// A today with no activity yet does not break the streak; a full
    /// calendar day with none does.
    public static func currentStreak(activeDays: Set<Date>,
                                     today: Date,
                                     calendar: Calendar = .current) -> Int {
        let days = Set(activeDays.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        let start = calendar.startOfDay(for: today)
        var cursor = days.contains(start)
            ? start
            : calendar.date(byAdding: .day, value: -1, to: start)!

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }
}
