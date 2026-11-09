import AppKit
import SwiftUI

/// Mac window chrome is opaque, unlike the lightly blue shared reading canvas.
/// Keeping these tokens separate also preserves the user's Light appearance choice.
enum FleetMacChrome {
    static let controlRadius: CGFloat = 12
    static let menuRadius: CGFloat = 16
    static let targetSize: CGFloat = 44
    static let visualControlHeight: CGFloat = 36
    static let sidebarRadius: CGFloat = 24
    static let sidebarTopInset: CGFloat = 8

    static let background = Color(nsColor: backgroundColor)
    static let foreground = Color(nsColor: NSColor(name: "HashFleetChromeInk") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 244 / 255, green: 246 / 255, blue: 247 / 255, alpha: 1)
            : NSColor(srgbRed: 33 / 255, green: 32 / 255, blue: 30 / 255, alpha: 1)
    })
    static let backgroundColor = NSColor(name: "HashFleetChrome") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    }

    static func statusTitle(compactTitle: String) -> String {
        compactTitle
    }

    @MainActor
    static func configure(_ window: NSWindow) {
        // Keep AppKit's real traffic lights, title and sidebar ownership. No custom
        // title-bar views, window-button coordinates or per-window-size offsets.
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
        if !window.backgroundColor.isEqual(backgroundColor) { window.backgroundColor = backgroundColor }
        if window.toolbarStyle != .unified { window.toolbarStyle = .unified }
    }
}

struct FleetMacToolbarBrand: View {
    var body: some View {
        FleetHeaderTitle()
            .foregroundStyle(FleetMacChrome.foreground)
            .frame(minHeight: FleetMacChrome.targetSize)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Hash Fleet")
            .accessibilityIdentifier("desktop.brandMark")
    }
}

/// One shape and inset for toolbar buttons, menu triggers and status-panel actions.
/// The 36pt visible shape sits within a 44pt target, not a second system glass pill.
struct FleetMacToolbarControl<Content: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    var isPressed = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(FleetMacChrome.foreground.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, FleetSurfaceSpacing.pill.leading)
            .padding(.vertical, FleetSurfaceSpacing.pill.top)
            .frame(minWidth: FleetMacChrome.visualControlHeight,
                   minHeight: FleetMacChrome.visualControlHeight)
            .background {
                RoundedRectangle(cornerRadius: FleetMacChrome.controlRadius, style: .continuous)
                    .fill(FleetMacChrome.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: FleetMacChrome.controlRadius, style: .continuous)
                            .fill(FleetMacChrome.foreground.opacity(
                                isEnabled && (isPressed || isHovering) ? 0.10 : 0))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: FleetMacChrome.controlRadius, style: .continuous)
                            .strokeBorder(FleetMacChrome.foreground.opacity(isEnabled ? 0.16 : 0.08))
                    }
            }
            .frame(minWidth: FleetMacChrome.targetSize, minHeight: FleetMacChrome.targetSize)
            .contentShape(RoundedRectangle(cornerRadius: FleetMacChrome.controlRadius, style: .continuous))
            .onHover { isHovering = $0 }
    }
}

struct FleetMacToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FleetMacToolbarControl(isPressed: configuration.isPressed) { configuration.label }
    }
}

extension View {
    /// Clip the complete navigation surface, including the List and pinned footer.
    /// Clipping only a background leaves the List's rectangular top visible at Fleet.
    func fleetMacSidebarSurface(fill: Color) -> some View {
        padding(.top, FleetMacChrome.sidebarTopInset)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: FleetMacChrome.sidebarRadius, style: .continuous))
            .padding(.top, FleetMacChrome.sidebarTopInset)
            .background(FleetMacChrome.background)
    }

    func fleetMacMenuSurface() -> some View {
        foregroundStyle(FleetMacChrome.foreground)
            .background(FleetMacChrome.background, in:
                RoundedRectangle(cornerRadius: FleetMacChrome.menuRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: FleetMacChrome.menuRadius, style: .continuous))
    }
}
