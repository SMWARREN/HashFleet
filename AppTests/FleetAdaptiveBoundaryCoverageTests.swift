import Testing
import SwiftUI
import Foundation
@testable import HashFleet

@Suite("Adaptive Boundary Coverage")
struct FleetAdaptiveBoundaryCoverageTests {

    @Test("Card columns compute safely for non-finite, zero, and exact-threshold widths")
    func testCardColumnsWidthBoundaries() {
        // Less than tier1
        #expect(FleetLayout.cardColumns(for: -50) == 1)
        #expect(FleetLayout.cardColumns(for: 0) == 1)
        #expect(FleetLayout.cardColumns(for: 1) == 1)

        // Non-finite
        #expect(FleetLayout.cardColumns(for: .nan) == 4) // nan falls through to default in switch
        #expect(FleetLayout.cardColumns(for: .infinity) == 4)
        #expect(FleetLayout.cardColumns(for: -.infinity) == 1) // -.infinity is < tier1Threshold

        // Exactly on tier1
        #expect(FleetLayout.cardColumns(for: 560) == 1)

        // Below tier2
        #expect(FleetLayout.cardColumns(for: 959.99) == 1)

        // Exactly on tier2 (two columns)
        #expect(FleetLayout.cardColumns(for: 960) == 2)

        // Exactly on tier3 (three columns)
        #expect(FleetLayout.cardColumns(for: 1300) == 3)

        // Exactly on tier4 (four columns)
        #expect(FleetLayout.cardColumns(for: 1640) == 4)

        // Huge widths
        #expect(FleetLayout.cardColumns(for: 5000) == 4)
    }

    @Test("Mac dashboard column layout limits preferred inputs and respects minimums")
    func testMacDashboardCardColumnsBoundaries() {
        // Under threshold (700) forces 1 column
        #expect(FleetLayout.macDashboardCardColumns(for: 699, preferred: 2) == 1)
        #expect(FleetLayout.macDashboardCardColumns(for: 0, preferred: 5) == 1)
        #expect(FleetLayout.macDashboardCardColumns(for: -.infinity, preferred: 2) == 1)
        #expect(FleetLayout.macDashboardCardColumns(for: .nan, preferred: 2) == 1) // nan >= 700 is false

        // Automatic fits the available width. Explicit choices remain upper limits.
        #expect(FleetLayout.macDashboardCardColumns(for: 700, preferred: 0) == 2)
        #expect(FleetLayout.macDashboardCardColumns(for: 700, preferred: 1) == 1)
        #expect(FleetLayout.macDashboardCardColumns(for: 700, preferred: 2) == 2)
        #expect(FleetLayout.macDashboardCardColumns(for: 700, preferred: 5) == 2)
        #expect(FleetLayout.macDashboardCardColumns(for: 1_080, preferred: 0) == 3)
        #expect(FleetLayout.macDashboardCardColumns(for: 1_080, preferred: 5) == 3)
        #expect(FleetLayout.macDashboardCardColumns(for: 1_080, preferred: 2) == 2)

        #expect(FleetLayout.macDashboardCardColumns(for: .infinity, preferred: 2) == 1)
    }

    @Test("Mac detail columns limits preferred inputs and respects minimums")
    func testMacDetailColumnsBoundaries() {
        let threshold = FleetLayout.macDetailTwoColumnThreshold // 760
        #expect(FleetLayout.macDetailColumns(for: threshold - 1, preferred: 2) == 1)
        #expect(FleetLayout.macDetailColumns(for: threshold, preferred: 0) == 2)
        #expect(FleetLayout.macDetailColumns(for: threshold, preferred: 3) == 2)
        #expect(FleetLayout.macDetailColumns(for: .nan, preferred: 2) == 1)
        #expect(FleetLayout.macDetailColumns(for: .infinity, preferred: 0) == 1)
        #expect(FleetLayout.macDetailColumns(for: 1_180, preferred: 0) == 3)
        #expect(FleetLayout.macDetailColumns(for: 1_180, preferred: 2) == 2)
    }

    @Test("Available content width defends against negative layouts and absurd inputs")
    func testAvailableContentWidthProtections() {
        // viewport < reserved causes negative, constrained to 0
        #expect(FleetLayout.availableContentWidth(viewportWidth: 100, maximumWidth: 500, reservedWidth: 200) == 0)

        // normal case
        #expect(FleetLayout.availableContentWidth(viewportWidth: 800, maximumWidth: 1000, reservedWidth: 300) == 500)

        // max width constraints
        #expect(FleetLayout.availableContentWidth(viewportWidth: 1500, maximumWidth: 1000, reservedWidth: 200) == 800)

        // non-finite
        #expect(FleetLayout.availableContentWidth(viewportWidth: .nan, maximumWidth: 1000, reservedWidth: 200) == 0) // min(nan, 1000) = nan, nan - 200 = nan, max(0, nan) = 0
    }

    @Test("Dynamic type categories are identical on Mac and iPad")
    func testDynamicTypeSizeMacBehavior() {
        // forMac = false leaves it alone
        #expect(FleetLayout.preferredDynamicTypeSize(.medium, forMac: false) == .medium)
        #expect(FleetLayout.preferredDynamicTypeSize(.accessibility3, forMac: false) == .accessibility3)

        // A wider canvas must not force a different type size.
        #expect(FleetLayout.preferredDynamicTypeSize(.xSmall, forMac: true) == .xSmall)
        #expect(FleetLayout.preferredDynamicTypeSize(.large, forMac: true) == .large)

        // forMac = true preserves xLarge and above
        #expect(FleetLayout.preferredDynamicTypeSize(.xLarge, forMac: true) == .xLarge)
        #expect(FleetLayout.preferredDynamicTypeSize(.xxLarge, forMac: true) == .xxLarge)
        #expect(FleetLayout.preferredDynamicTypeSize(.accessibility1, forMac: true) == .accessibility1)
    }

    @Test("Icon design points are identical on Mac and iPad")
    func testIconSizeBehavior() {
        #expect(FleetLayout.iconSize(10, forMac: false) == 10)
        #expect(FleetLayout.iconSize(10, forMac: true) == 10)
        #expect(FleetLayout.iconSize(15, forMac: true) == 15)
    }

    @Test("Dashboard Miner Card horizontal control limits")
    func testDashboardMinerCardHorizontalControlsBoundaries() {
        // Always true for width < 480 regardless of Dynamic Type
        #expect(FleetLayout.dashboardMinerCardUsesHorizontalControls(availableWidth: 479, dynamicTypeSize: .medium) == true)

        // false for width >= 480 AND small Dynamic Type
        #expect(FleetLayout.dashboardMinerCardUsesHorizontalControls(availableWidth: 480, dynamicTypeSize: .large) == false)

        // true for width >= 480 but xxxLarge Dynamic Type
        #expect(FleetLayout.dashboardMinerCardUsesHorizontalControls(availableWidth: 1000, dynamicTypeSize: .xxxLarge) == true)
    }
}
