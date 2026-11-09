import SwiftUI

private struct FleetStandalonePageKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// A Mac sidebar destination is a page, not a dismissible modal.
    var fleetStandalonePage: Bool {
        get { self[FleetStandalonePageKey.self] }
        set { self[FleetStandalonePageKey.self] = newValue }
    }
}
