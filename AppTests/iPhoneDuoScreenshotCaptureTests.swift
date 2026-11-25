import Foundation
import Testing
import SwiftUI
import HashFleetCore
@testable import HashFleet

@Suite(.serialized)
@MainActor
struct IPhoneDuoScreenshotCaptureTests {
    private static let outputDir = URL(
        fileURLWithPath: "/Users/saint/dev/hashfleet-iphone-duo/docs/screenshots/duo"
    )

    @Test
    func captureIPhoneDuoOuterAndInnerDisplays() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        await fixture.insights.refresh()

        try? FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)

        // 1. Folded Outer Display (Compact, 466 x 678 pt)
        let outerView = NavigationStack {
            DashboardView(store: fixture.store, insights: fixture.insights)
        }
        .environment(\.horizontalSizeClass, .compact)

        let outerRendered = try await FleetViewRenderHarness.render(
            outerView,
            width: 466,
            height: 678
        )
        #expect(
            outerRendered.visibleText.contains("Sample fleet hashrate") ||
            outerRendered.visibleText.contains("Hash Fleet")
        )
        let outerURL = Self.outputDir.appendingPathComponent("iphone-duo-outer-dashboard.png")
        try outerRendered.pngData.write(to: outerURL)
        Attachment.record(outerRendered.pngData, named: "iphone-duo-outer-dashboard.png")

        // 2. Unfolded Inner Display (Regular, 669 x 951 pt - 2-column balanced fold layout)
        let innerView = NavigationStack {
            DashboardView(store: fixture.store, insights: fixture.insights)
        }
        .environment(\.horizontalSizeClass, .regular)

        let innerRendered = try await FleetViewRenderHarness.render(
            innerView,
            width: 669,
            height: 951
        )
        #expect(
            innerRendered.visibleText.contains("Sample fleet hashrate") ||
            innerRendered.visibleText.contains("Hash Fleet")
        )
        let innerURL = Self.outputDir.appendingPathComponent("iphone-duo-inner-dashboard.png")
        try innerRendered.pngData.write(to: innerURL)
        Attachment.record(innerRendered.pngData, named: "iphone-duo-inner-dashboard.png")

        // 3. Unfolded Inner Display - Miner Detail View
        let device = try #require(fixture.store.devices.first)
        let detailView = NavigationStack {
            MinerDetailView(device: device, store: fixture.store, insights: fixture.insights)
        }
        .environment(\.horizontalSizeClass, .regular)

        let detailRendered = try await FleetViewRenderHarness.render(
            detailView,
            width: 669,
            height: 951
        )
        #expect(!detailRendered.visibleText.isEmpty)
        let detailURL = Self.outputDir.appendingPathComponent("iphone-duo-inner-detail.png")
        try detailRendered.pngData.write(to: detailURL)
        Attachment.record(detailRendered.pngData, named: "iphone-duo-inner-detail.png")

        // 4. Unfolded Inner Display - full app with the menu filling the left panel
        let splitView = FleetSplitView(
            store: fixture.store,
            insights: fixture.insights,
            coordinator: nil,
            startupReady: true,
            fleetPath: .constant(NavigationPath()),
            sidebarSelection: .constant(.overview)
        )
        .environment(\.horizontalSizeClass, .regular)

        let splitRendered = try await FleetViewRenderHarness.render(
            splitView,
            width: 669,
            height: 951
        )
        #expect(!splitRendered.visibleText.isEmpty)
        let splitURL = Self.outputDir.appendingPathComponent("iphone-duo-inner-menu-split.png")
        try splitRendered.pngData.write(to: splitURL)
        Attachment.record(splitRendered.pngData, named: "iphone-duo-inner-menu-split.png")
    }

    @Test
    func foldSidebarTakesLeftPanelOnlyOnUnfoldedPhones() {
        #expect(FleetLayout.foldSidebarWidth(forWindowWidth: 669, isPhone: true) == 334)
        #expect(FleetLayout.foldSidebarWidth(forWindowWidth: 466, isPhone: true) == nil)
        #expect(FleetLayout.foldSidebarWidth(forWindowWidth: 1024, isPhone: true) == nil)
        #expect(FleetLayout.foldSidebarWidth(forWindowWidth: 669, isPhone: false) == nil)
    }
}
