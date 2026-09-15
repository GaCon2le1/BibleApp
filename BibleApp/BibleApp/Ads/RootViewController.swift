import UIKit

/// Google Mobile Ads needs a `UIViewController` to present full-screen ads
/// from; this finds the one currently on screen.
enum RootViewController {
    static func current() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
