import GoogleMobileAds
import UIKit

/// Loads and presents Interstitial Ads. Shown only when the user switches
/// tabs in the root nav bar, subject to a cooldown so repeated tab
/// switching doesn't spam the user with ads.
final class InterstitialAdManager: NSObject {
    private let gate: AdPresentationGate
    private var ad: InterstitialAd?
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
                let loadedAd = try await InterstitialAd.load(with: AdsConfig.interstitialAdUnitID, request: Request())
                loadedAd.fullScreenContentDelegate = self
                ad = loadedAd
            } catch {
                print("InterstitialAdManager: failed to load - \(error.localizedDescription)")
            }
        }
    }

    /// Never blocks the tab switch itself: if no ad is ready or the
    /// cooldown hasn't elapsed yet, this simply does nothing.
    func showIfEligible(from rootViewController: UIViewController) {
        guard let ad else {
            loadAd()
            return
        }
        if let lastShownAt, Date().timeIntervalSince(lastShownAt) < AdsConfig.interstitialCooldown {
            return
        }
        guard gate.begin() else { return }
        ad.present(from: rootViewController)
    }
}

extension InterstitialAdManager: FullScreenContentDelegate {
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
