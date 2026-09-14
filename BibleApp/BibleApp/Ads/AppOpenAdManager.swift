import GoogleMobileAds
import UIKit

/// Loads and presents App Open Ads: shown at cold start and whenever the
/// app returns to the foreground from the background, subject to a
/// cooldown and AdMob's cache-age limit.
final class AppOpenAdManager: NSObject {
    private let gate: AdPresentationGate
    private var ad: AppOpenAd?
    private var loadedAt: Date?
    private var lastShownAt: Date?
    private var isLoading = false

    init(gate: AdPresentationGate) {
        self.gate = gate
    }

    func loadAd() {
        guard !isLoading, ad == nil else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let loadedAd = try await AppOpenAd.load(with: AdsConfig.appOpenAdUnitID, request: Request())
                loadedAd.fullScreenContentDelegate = self
                ad = loadedAd
                loadedAt = Date()
            } catch {
                print("AppOpenAdManager: failed to load - \(error.localizedDescription)")
            }
        }
    }

    /// Presents the ad if one is ready, still fresh, and the cooldown since
    /// the last presentation has elapsed. Otherwise does nothing.
    func showIfEligible(from rootViewController: UIViewController) {
        guard let ad, let loadedAt else {
            loadAd()
            return
        }
        guard Date().timeIntervalSince(loadedAt) < AdsConfig.appOpenMaxCacheAge else {
            self.ad = nil
            loadAd()
            return
        }
        if let lastShownAt, Date().timeIntervalSince(lastShownAt) < AdsConfig.appOpenCooldown {
            return
        }
        guard gate.begin() else { return }
        ad.present(from: rootViewController)
    }
}

extension AppOpenAdManager: FullScreenContentDelegate {
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        gate.end()
        self.ad = nil
        loadAd()
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        gate.end()
        lastShownAt = Date()
        self.ad = nil
        loadAd()
    }
}
