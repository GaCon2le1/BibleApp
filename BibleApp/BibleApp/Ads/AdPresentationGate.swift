import Foundation

/// Lets the App Open and Interstitial ad managers share one "is an ad on
/// screen right now" flag, so they never try to present over each other.
final class AdPresentationGate {
    private(set) var isPresenting = false

    /// Claims the gate for a presentation. Returns `false` (and claims
    /// nothing) if another ad is already showing.
    func begin() -> Bool {
        guard !isPresenting else { return false }
        isPresenting = true
        return true
    }

    func end() {
        isPresenting = false
    }
}
