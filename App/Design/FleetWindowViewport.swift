import SwiftUI

private struct FleetWindowViewportKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 1024, height: 768)
}

extension EnvironmentValues {
    var fleetWindowViewport: CGSize {
        get { self[FleetWindowViewportKey.self] }
        set { self[FleetWindowViewportKey.self] = newValue }
    }
}

/// Sheets inherit their actual owning window's dimensions, not the entire monitor's bounds.
struct FleetWindowViewportModifier: ViewModifier {
    @State private var size = FleetWindowViewportKey.defaultValue

    func body(content: Content) -> some View {
        content
            .environment(\.fleetWindowViewport, size)
            // Whole points: sheets only need the window's size class, not sub-point drift.
            .onGeometryChange(for: CGSize.self) {
                CGSize(width: $0.size.width.rounded(), height: $0.size.height.rounded())
            } action: { size = $0 }
    }
}

extension View {
    func fleetWindowViewport() -> some View {
        modifier(FleetWindowViewportModifier())
    }
}
