import SwiftUI

/// Banner frames in the notification window, not the underlying sheet's coordinate space.
struct FleetNotificationHitRegions: PreferenceKey {
    static let coordinateSpace = "fleetNotificationWindow"
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}
