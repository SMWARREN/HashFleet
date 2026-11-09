import SwiftUI

enum FleetMacSheetLayout {
    static func preferredSize(in viewport: CGSize) -> CGSize {
        let width = viewport.width.isFinite && viewport.width > 0 ? viewport.width : 1024
        let height = viewport.height.isFinite && viewport.height > 0 ? viewport.height : 768
        // Keep a visible margin around desktop sheets without forcing a narrow Mac window to grow.
        return CGSize(width: max(1, width - min(64, width * 0.08)),
                      height: max(1, height - min(48, height * 0.08)))
    }
}

struct FleetMacPageSheetModifier: ViewModifier {
    @Environment(\.fleetWindowViewport) private var viewport
    @Environment(\.fleetFullWindowPresentation) private var fillsWindow

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        if fillsWindow {
            content
                .environment(\.fleetStandalonePage, false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let size = FleetMacSheetLayout.preferredSize(in: viewport)
            if #available(macOS 15.0, *) {
                content
                    .environment(\.fleetStandalonePage, false)
                    .frame(width: size.width, height: size.height)
                    .presentationSizing(.fitted)
                    .presentationDetents([.large])
            } else {
                content
                    .environment(\.fleetStandalonePage, false)
                    .frame(idealWidth: size.width, idealHeight: size.height)
                    .presentationDetents([.large])
            }
        }
        #else
        if fillsWindow {
            content
                .environment(\.fleetStandalonePage, false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if FleetLayout.isMac {
            let size = FleetMacSheetLayout.preferredSize(in: viewport)
            if #available(iOS 18.0, *) {
                content
                    .environment(\.fleetStandalonePage, false)
                    .frame(width: size.width, height: size.height)
                    .presentationSizing(.fitted)
                    .presentationDetents([.large])
            } else {
                content
                    .environment(\.fleetStandalonePage, false)
                    .frame(idealWidth: size.width, idealHeight: size.height)
                    .presentationDetents([.large])
            }
        } else if #available(iOS 18.0, *) {
            content.environment(\.fleetStandalonePage, false).presentationSizing(.page)
        } else {
            content.environment(\.fleetStandalonePage, false)
        }
        #endif
    }
}
