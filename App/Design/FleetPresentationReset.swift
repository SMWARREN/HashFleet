import SwiftUI

private struct FleetPresentationResetKey: EnvironmentKey {
    static let defaultValue = UUID()
}

extension EnvironmentValues {
    var fleetPresentationResetID: UUID {
        get { self[FleetPresentationResetKey.self] }
        set { self[FleetPresentationResetKey.self] = newValue }
    }
}

/// Reset the actual SwiftUI bindings, not just their UIKit presentation controllers. The
/// request is inherited by the real view owners so dismissed sheets can be opened again safely.
private struct FleetPresentationResetModifier: ViewModifier {
    @Environment(\.fleetPresentationResetID) private var requestID
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: requestID) { _, _ in dismiss() }
    }
}

extension View {
    func fleetDismissPresentationsOnNavigation(_ dismiss: @escaping () -> Void) -> some View {
        modifier(FleetPresentationResetModifier(dismiss: dismiss))
    }
}
