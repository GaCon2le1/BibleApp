import Foundation

/// Picks the verse shown by the widget for a given day. Deterministic: the
/// same calendar day always yields the same verse, and consecutive days walk
/// the eligible list with a stride coprime to its length so the order does
/// not follow the canon.
public enum VerseOfTheDay {
    public static func entry(in verses: [VerseIndexEntry],
                             on date: Date,
                             calendar: Calendar = .current) -> VerseIndexEntry? {
        let tierOne = verses.filter { $0.tier == 1 }
        let pool = tierOne.isEmpty ? verses : tierOne
        guard !pool.isEmpty else { return nil }

        let epoch = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let today = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: epoch, to: today).day ?? 0

        let count = pool.count
        var stride = 7919
        while gcd(stride, count) != 1 { stride += 1 }
        let index = (((days % count) * (stride % count)) % count + count) % count
        return pool[index]
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}
