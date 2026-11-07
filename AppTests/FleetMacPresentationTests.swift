import SwiftUI
import Testing
@testable import HashFleet

@Suite("Desktop sheet sizing")
struct FleetMacPresentationTests {
    @Test func onlyIPhoneUsesAppPageSheetsWhileIPadAndMacNavigateInApp() {
        #expect(!FleetPagePresentationPolicy.usesInAppNavigation(isPhone: true, forMac: false))
        #expect(FleetPagePresentationPolicy.usesInAppNavigation(isPhone: false, forMac: false))
        #expect(FleetPagePresentationPolicy.usesInAppNavigation(isPhone: false, forMac: true))
        #expect(FleetPagePresentationPolicy.usesInAppNavigation(isPhone: true, forMac: true))
    }

    @Test func desktopAcceptanceOverrideRequiresExplicitTestingMode() {
        #expect(FleetLayout.usesMacLayout(nativeMac: true, arguments: []))
        #expect(!FleetLayout.usesMacLayout(nativeMac: false, arguments: []))
        #expect(!FleetLayout.usesMacLayout(nativeMac: false, arguments: ["--ui-test-desktop-layout"]))
        #expect(!FleetLayout.usesMacLayout(nativeMac: false, arguments: ["--ui-testing"]))
        #expect(FleetLayout.usesMacLayout(nativeMac: false,
            arguments: ["--ui-testing", "--ui-test-desktop-layout"]))
    }

    @Test func normalDesktopSheetUsesMostOfTheWindow() {
        let size = FleetMacSheetLayout.preferredSize(in: CGSize(width: 1200, height: 900))
        #expect(size == CGSize(width: 1136, height: 852))
    }

    @Test func smallWindowsDoNotGetOversizedSheets() {
        for viewport in [CGSize(width: 600, height: 500), CGSize(width: 300, height: 240)] {
            let size = FleetMacSheetLayout.preferredSize(in: viewport)
            #expect(size.width < viewport.width && size.height < viewport.height)
            #expect(size.width > viewport.width * 0.85)
            #expect(size.height > viewport.height * 0.85)
        }
    }

    @Test func largeMonitorsDoNotLeavePopupsInANarrowCenteredPanel() {
        let size = FleetMacSheetLayout.preferredSize(in: CGSize(width: 3000, height: 1800))
        #expect(size == CGSize(width: 2936, height: 1752))
    }

    @Test func nativeReadingPagesFillTheirWindowAndIPadKeepsItsExistingPresentation() {
        #expect(FleetLayout.readingMaximumWidth(forMac: true).isInfinite)
        #expect(FleetLayout.readingMaximumWidth(forMac: false) == 760)
    }

    @Test func unavailableGeometryHasFiniteUsefulFallback() {
        for viewport in [CGSize.zero, CGSize(width: CGFloat.infinity, height: CGFloat.nan)] {
            let size = FleetMacSheetLayout.preferredSize(in: viewport)
            #expect(size == CGSize(width: 960, height: 720))
        }
    }

    @Test func fleetMacSheetLayoutPreferredSizeBoundaryConditions() {
        let size800x600 = FleetMacSheetLayout.preferredSize(in: CGSize(width: 800, height: 600))
        #expect(size800x600 == CGSize(width: 736, height: 552))

        let size500x400 = FleetMacSheetLayout.preferredSize(in: CGSize(width: 500, height: 400))
        #expect(size500x400 == CGSize(width: 460, height: 368))
    }

    @Test func fleetMacSheetLayoutNegativeOrZeroViewport() {
        let sizeNegative = FleetMacSheetLayout.preferredSize(in: CGSize(width: -100, height: 0))
        #expect(sizeNegative == CGSize(width: 960, height: 720))
    }
}
