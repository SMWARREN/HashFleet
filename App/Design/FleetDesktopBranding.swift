import SwiftUI

private struct FleetDesktopBrandingModifier: ViewModifier {
    let includesPrincipalBrand: Bool

    func body(content: Content) -> some View {
        content.environment(\.fleetStandalonePage, FleetLayout.isMac).toolbar {
            #if os(macOS)
                ToolbarItem(placement: FleetToolbarLocation.leading) {
                    FleetHeaderArtwork()
                        .frame(width: FleetMacChrome.targetSize, height: FleetMacChrome.targetSize)
                }
                .fleetUnadornedToolbarBackground()
                .fleetPersistentToolbarItem()
                if includesPrincipalBrand {
                    ToolbarItem(placement: .principal) {
                        FleetMacToolbarBrand()
                    }
                    .fleetUnadornedToolbarBackground()
                    .fleetPersistentToolbarItem()
                }
            #endif
        }
    }
}

extension View {
    /// The system owns the one sidebar toggle. Artwork stays leading and the wordmark
    /// stands alone in the center, as on iPad. Dashboard owns its title/search slot.
    func fleetDesktopBranding(sidebarVisible: Bool, includesPrincipalBrand: Bool = true) -> some View {
        modifier(FleetDesktopBrandingModifier(includesPrincipalBrand: includesPrincipalBrand))
    }
}
