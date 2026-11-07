import SwiftUI

/// Shared responsive layout rules. Native Mac pages use the width offered by their window.
/// The existing phone and iPad reading limits remain part of their presentation.
enum FleetLayout {
    static let sidebarAddTargetSize: CGFloat = 44

    /// Design points are shared across every target. A native window may choose more columns,
    /// but must not shrink typography, artwork, row spacing, or interaction targets.
    static func desktopPointSize(_ value: CGFloat) -> CGFloat {
        value
    }

    static var sidebarMinimumWidth: CGFloat {
        260
    }

    static var sidebarIdealWidth: CGFloat {
        300
    }

    static var sidebarMaximumWidth: CGFloat {
        400
    }
    /// Native workspaces are fluid, including pages that specify an iPad reading limit.
    static var readableWidth: CGFloat { readingMaximumWidth(forMac: isMac) }
    static var listContentWidth: CGFloat { readingMaximumWidth(forMac: isMac) }

    static func readingMaximumWidth(forMac: Bool) -> CGFloat {
        pageMaximumWidth(760, forMac: forMac)
    }

    static func pageMaximumWidth(_ compactMaximumWidth: CGFloat, forMac: Bool = isMac) -> CGFloat {
        forMac ? .infinity : compactMaximumWidth
    }
    /// Dashboard and other multi-card screens.
    static let wideContentWidth: CGFloat = 1180
    /// Miner detail in its two-column arrangement.
    static let wideDetailWidth: CGFloat = 1240
    static let compactDetailWidth: CGFloat = 800
    /// Window width at which multi-column arrangements switch on.
    static let twoColumnThreshold: CGFloat = 960
    static let quickControlsThreeColumnThreshold: CGFloat = 700

    /// Viewport width tiers for responsive dashboard layouts.
    /// Phones are unaffected (all caps exceed iPhone width).
    static let tier1Threshold: CGFloat = 560   // Single column, phone-like
    static let tier2Threshold: CGFloat = 960   // Two columns (== twoColumnThreshold)
    static let tier3Threshold: CGFloat = 1300  // Three columns
    static let tier4Threshold: CGFloat = 1640  // Four columns
    /// Mac dashboard thresholds preserve useful card widths beside the persistent sidebar.
    static let macTwoColumnThreshold: CGFloat = 700
    static let macThreeColumnThreshold: CGFloat = 1080
    static let macDetailTwoColumnThreshold: CGFloat = 760
    static let macDetailThreeColumnThreshold: CGFloat = 1180

    /// Number of card columns for a given viewport width.
    static func cardColumns(for width: CGFloat) -> Int {
        switch width {
        case ..<tier1Threshold: return 1
        case ..<tier2Threshold: return 1
        case ..<tier3Threshold: return 2
        case ..<tier4Threshold: return 3
        default: return 4
        }
    }

    /// NavigationSplitView reports the full app viewport to some iOS-on-Mac descendants even
    /// though the persistent sidebar consumes part of it. Use the conservative detail width for
    /// dashboard breakpoints so cards do not become a cramped extra column beside the sidebar.
    static func availableContentWidth(
        viewportWidth: CGFloat,
        maximumWidth: CGFloat,
        reservedWidth: CGFloat
    ) -> CGFloat {
        max(0, min(viewportWidth, maximumWidth) - reservedWidth)
    }

    static func dashboardAvailableWidth(for viewportWidth: CGFloat) -> CGFloat {
        dashboardAvailableWidth(for: viewportWidth, maximumWidth: dashboardContentWidth)
    }

    static func dashboardAvailableWidth(for viewportWidth: CGFloat, maximumWidth: CGFloat) -> CGFloat {
        // Geometry is measured inside the detail column, so never subtract the sidebar again.
        availableContentWidth(
            viewportWidth: viewportWidth,
            maximumWidth: maximumWidth,
            reservedWidth: 0
        )
    }

    static func dashboardCardColumns(for viewportWidth: CGFloat) -> Int {
        cardColumns(for: dashboardAvailableWidth(for: viewportWidth))
    }

    /// Automatic is the default. An optional user limit never prevents narrower windows
    /// from stepping down, and never changes a card's fonts or design-point metrics.
    static func macDashboardCardColumns(for availableWidth: CGFloat, preferred: Int) -> Int {
        responsiveColumns(
            availableWidth: availableWidth,
            twoColumnThreshold: macTwoColumnThreshold,
            threeColumnThreshold: macThreeColumnThreshold,
            preferred: preferred
        )
    }

    static func canUseTwoMacDashboardColumns(availableWidth: CGFloat) -> Bool {
        availableWidth >= macTwoColumnThreshold
    }

    static func canUseThreeMacDashboardColumns(availableWidth: CGFloat) -> Bool {
        availableWidth >= macThreeColumnThreshold
    }

    /// Keep the card's presenting Menu independent of changing telemetry, live errors,
    /// and miner names. Narrow cards put the controls below the readings rather than
    /// asking content-fit branches to create different instances of the same Menu.
    static func dashboardMinerCardUsesHorizontalControls(
        availableWidth: CGFloat,
        dynamicTypeSize: DynamicTypeSize
    ) -> Bool {
        availableWidth < 480 || dynamicTypeSize >= .xxxLarge
    }

    static func macDetailColumns(for availableWidth: CGFloat, preferred: Int) -> Int {
        responsiveColumns(
            availableWidth: availableWidth,
            twoColumnThreshold: macDetailTwoColumnThreshold,
            threeColumnThreshold: macDetailThreeColumnThreshold,
            preferred: preferred
        )
    }

    static func canUseTwoMacDetailColumns(availableWidth: CGFloat) -> Bool {
        availableWidth >= macDetailTwoColumnThreshold
    }

    static func canUseThreeMacDetailColumns(availableWidth: CGFloat) -> Bool {
        availableWidth >= macDetailThreeColumnThreshold
    }

    private static func responsiveColumns(
        availableWidth: CGFloat,
        twoColumnThreshold: CGFloat,
        threeColumnThreshold: CGFloat,
        preferred: Int
    ) -> Int {
        guard availableWidth.isFinite, availableWidth >= twoColumnThreshold else { return 1 }
        let fittingColumns = availableWidth >= threeColumnThreshold ? 3 : 2
        let limit = preferred == 0 ? 3 : min(max(preferred, 1), 3)
        return min(fittingColumns, limit)
    }

    /// Production uses the real platform. Native UI acceptance can explicitly
    /// exercise the same desktop branch with isolated demo preferences on a simulator.
    /// Launch arguments never change, so resolve once. This was re-read (a fresh bridged
    /// array plus two linear scans) from ~40 view bodies on every render pass.
    static let isMac: Bool = {
        #if os(macOS)
        usesMacLayout(nativeMac: true, arguments: ProcessInfo.processInfo.arguments)
        #else
        usesMacLayout(nativeMac: false, arguments: ProcessInfo.processInfo.arguments)
        #endif
    }()

    static func usesMacLayout(nativeMac: Bool, arguments: [String]) -> Bool {
        nativeMac || (arguments.contains("--ui-testing") && arguments.contains("--ui-test-desktop-layout"))
    }

    static func usesTwoColumns(width: CGFloat) -> Bool {
        width >= twoColumnThreshold
    }

    static var dashboardContentWidth: CGFloat {
        pageMaximumWidth(wideContentWidth)
    }

    static var formRowHeight: CGFloat {
        44
    }

    /// Preserve the selected category. Available space changes columns, never the user's text size.
    static func preferredDynamicTypeSize(
        _ current: DynamicTypeSize,
        forMac: Bool = isMac
    ) -> DynamicTypeSize {
        current
    }

    /// Fixed artwork uses the same design metric on every platform.
    static func iconSize(_ base: CGFloat, forMac: Bool = isMac) -> CGFloat {
        base
    }

    static var sidebarIconSize: CGFloat { 16 }
    static var sidebarIconWidth: CGFloat { 20 }

    /// One outer gutter for every page, independent of destination or platform.
    /// Card interiors and 44-point interaction targets are separate design metrics.
    static let pagePadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 16

    /// Card grid spacing.
    static let cardGridSpacing: CGFloat = 14
    /// Card internal padding.
    static let cardPadding: CGFloat = 14
}

extension View {
    /// The common page shell. Call this once on scroll content, never on individual cards.
    /// No destination can choose its own outer margins or native width cap.
    func fleetPageContainer(
        compactMaxWidth: CGFloat = .infinity
    ) -> some View {
        modifier(FleetPageContainerModifier(compactMaxWidth: compactMaxWidth))
    }

    /// Caps phone/iPad content while Mac pages use their full detail-column width.
    func fleetReadableWidth(_ maxWidth: CGFloat = FleetLayout.readableWidth) -> some View {
        frame(maxWidth: FleetLayout.pageMaximumWidth(maxWidth)).frame(maxWidth: .infinity)
    }

    /// Native forms fill the available detail column. Phone/iPad reading caps stay unchanged.
    func fleetReadableForm(_ maxWidth: CGFloat = FleetLayout.readableWidth) -> some View {
        modifier(FleetReadableFormModifier(maxWidth: maxWidth))
    }

    /// Shared control sizing without introducing a platform-specific text or density scale.
    func fleetMacScreenSizing() -> some View {
        modifier(FleetMacScreenSizingModifier())
    }

    /// Pointer feedback for tappable cards when a trackpad or mouse is used (Mac, iPad).
    func fleetPointerHover() -> some View {
        #if os(macOS)
        modifier(FleetNativePointerHoverModifier())
        #else
        hoverEffect(.highlight)
        #endif
    }
}

#if os(macOS)
private struct FleetNativePointerHoverModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.015 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
#endif

private struct FleetPageContainerModifier: ViewModifier {
    let compactMaxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .fleetFont(.body)
            .padding(FleetLayout.pagePadding)
            .frame(maxWidth: FleetLayout.pageMaximumWidth(compactMaxWidth))
            .frame(maxWidth: .infinity)
    }
}

private struct FleetMacScreenSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.defaultMinListRowHeight, FleetLayout.formRowHeight)
            .controlSize(.regular)
    }
}

private struct FleetReadableFormModifier: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if FleetLayout.isMac {
            // The owning window determines the width. An iPad reading limit must not
            // become a native page cap or prevent settings from growing with the window.
            content
                // Control-heavy forms still need a scrolling container on native Mac.
                // Scope this here, rather than applying a form style to every destination.
                .formStyle(.grouped)
                .contentMargins(.all, FleetLayout.pagePadding, for: .scrollContent)
                .frame(maxWidth: .infinity)
                .background(FleetTheme.canvas)
                .fleetFont(.body)
        } else {
            let inset = max(0, (width - maxWidth) / 2)
            content
                .safeAreaPadding(.horizontal, inset)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }
}

extension View {
    /// Desktop sheets use the owning window's available space. iPad and phone behavior stays
    /// unchanged, including the iOS 17 fallback.
    func fleetPageSheet() -> some View {
        modifier(FleetMacPageSheetModifier())
    }
}
