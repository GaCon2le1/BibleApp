import Foundation

/// Ad unit IDs and pacing constants for the base ads integration.
///
/// These are Google's public test ad unit IDs. Swap them for the app's real
/// AdMob ad unit IDs before shipping to the App Store.
enum AdsConfig {
    static let appOpenAdUnitID = "ca-app-pub-3940256099942544/5575463023"
    static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"

    /// Minimum time between two App Open Ad presentations.
    static let appOpenCooldown: TimeInterval = 60
    /// An App Open Ad older than this is stale and gets reloaded instead of
    /// shown, per AdMob's guidance.
    static let appOpenMaxCacheAge: TimeInterval = 4 * 60 * 60
    /// Minimum time between two Interstitial Ad presentations, so switching
    /// tabs repeatedly doesn't spam the user with ads.
    static let interstitialCooldown: TimeInterval = 60
}
