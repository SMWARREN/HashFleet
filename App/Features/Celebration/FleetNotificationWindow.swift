#if canImport(UIKit)
import UIKit

/// Only banners are interactive unless a full-screen celebration is visible. The rest of the
/// window passes taps and scrolling to whichever screen or sheet the user is working in.
final class FleetNotificationWindow: UIWindow {
    var interactiveRegions: [CGRect] = []
    var capturesAllTouches = false

    func handles(_ point: CGPoint) -> Bool {
        capturesAllTouches || interactiveRegions.contains { $0.contains(point) }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard handles(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}
#endif
