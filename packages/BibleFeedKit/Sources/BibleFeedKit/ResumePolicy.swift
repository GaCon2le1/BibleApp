/// Where an episode picks up again, and when it counts as heard.
public enum ResumePolicy {
    /// Positions this early aren't worth resuming.
    public static let minimumResume: Double = 5
    /// Positions this close to the end restart the episode instead.
    public static let restartWindow: Double = 30
    public static let finishedFraction: Double = 0.95

    public static func startPosition(saved: Double?, duration: Double) -> Double {
        guard let saved, saved >= minimumResume, saved < duration - restartWindow else { return 0 }
        return saved
    }

    public static func isFinished(position: Double, duration: Double) -> Bool {
        duration > 0 && position >= duration * finishedFraction
    }

    public static func fraction(position: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}
