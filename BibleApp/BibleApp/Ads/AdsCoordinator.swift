import AppTrackingTransparency
import GoogleMobileAds

/// Single entry point the app uses to drive the base ads integration:
/// starts the SDK, requests App Tracking Transparency, and fans out the
/// two triggers this app cares about - app foregrounding and nav bar tab
/// switches - to the matching ad manager.
@Observable
final class AdsCoordinator {
    private let gate = AdPresentationGate()
    private let appOpenAd: AppOpenAdManager
    private let interstitialAd: InterstitialAdManager
    private var isOnboardingComplete = false

    init() {
        appOpenAd = AppOpenAdManager(gate: gate)
        interstitialAd = InterstitialAdManager(gate: gate)
    }

    /// Starts the Google Mobile Ads SDK and preloads both ad types. Call
    /// once, at app launch.
    func start() {
        MobileAds.shared.start()
        appOpenAd.loadAd()
        interstitialAd.loadAd()
    }

    func requestTrackingAuthorizationIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { _ in
                continuation.resume()
            }
        }
    }

    func setOnboardingComplete(_ complete: Bool) {
        isOnboardingComplete = complete
    }

    /// Called when the app becomes active, either at cold start or after
    /// returning from the background. Skipped while an episode is playing,
    /// since an ad with sound would cut into it.
    func showAppOpenAdIfEligible() {
        guard isOnboardingComplete, !AudioPlayer.shared.isPlaying,
              let rootViewController = RootViewController.current() else { return }
        appOpenAd.showIfEligible(from: rootViewController)
    }

    /// Called every time the user switches tabs in the root nav bar.
    /// Skipped while an episode is playing.
    func tabDidChange() {
        guard isOnboardingComplete, !AudioPlayer.shared.isPlaying,
              let rootViewController = RootViewController.current() else { return }
        interstitialAd.showIfEligible(from: rootViewController)
    }
}
