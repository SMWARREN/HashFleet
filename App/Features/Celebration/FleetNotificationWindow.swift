#if canImport(UIKit)
import UIKit

/// Only banners are interactive unless a full-screen celebration is visible. The rest of the
/// window passes taps and scrolling to whichever screen or sheet the user is working in.
final class FleetNotificationWindow: UIWindow {
    var interactiveRegions: [CGRect] = []
    var capturesAllTouches = false

    /// SwiftUI measures the named root inside its safe area. UIKit hit-test points use
    /// window coordinates, so register the actual screen-space rectangles, not the inset ones.
    func updateInteractiveRegions(_ regions: [CGRect], contentInsets: UIEdgeInsets) {
        interactiveRegions = regions.map {
            $0.offsetBy(dx: contentInsets.left, dy: contentInsets.top)
        }
    }

    func handles(_ point: CGPoint) -> Bool {
        capturesAllTouches || interactiveRegions.contains { $0.contains(point) }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard handles(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}
#endif
