/// Clock-style labels for playback positions: "4:05", or "1:02:05" from an hour.
public enum PlaybackTime {
    public static func format(_ seconds: Double) -> String {
        let total = seconds.isFinite ? Int(max(seconds, 0)) : 0
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let secs = total % 60
        let paddedSeconds = secs < 10 ? "0\(secs)" : "\(secs)"
        if hours > 0 {
            let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(paddedMinutes):\(paddedSeconds)"
        }
        return "\(minutes):\(paddedSeconds)"
    }
}
