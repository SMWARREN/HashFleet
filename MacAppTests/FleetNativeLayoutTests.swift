import SwiftUI
import Testing
@testable import HashFleetMac

@Suite("Native Mac familiar layout")
struct FleetNativeLayoutTests {
    @Test func nativeTourHighlightLeavesClearanceAndStaysInsideItsViewport() throws {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let target = CGRect(x: 100, y: 120, width: 220, height: 44)
        #expect(FleetTourGeometry.highlightOutset == 12)
        let highlight = try #require(FleetTourGeometry.clippedTarget(
            target, outset: FleetTourGeometry.highlightOutset, in: bounds
        ))
        #expect(highlight == CGRect(x: 88, y: 108, width: 244, height: 68))
        #expect(highlight.contains(target))

        let edgeTarget = CGRect(x: 0, y: 2, width: 100, height: 44)
        let clipped = try #require(FleetTourGeometry.clippedTarget(
            edgeTarget, outset: FleetTourGeometry.highlightOutset, in: bounds
        ))
        #expect(bounds.contains(clipped))
        #expect(clipped.contains(edgeTarget))
        #expect(FleetTourGeometry.clippedTarget(
            CGRect(x: 900, y: 100, width: 40, height: 40),
            outset: FleetTourGeometry.highlightOutset, in: bounds
        ) == nil)
        #expect(FleetTourGeometry.clippedTarget(
            CGRect(x: CGFloat.nan, y: 100, width: 40, height: 40),
            outset: FleetTourGeometry.highlightOutset, in: bounds
        ) == nil)
    }

    /// Regression for the 2026-10-27 miner-detail hang: width noise must not re-render the page,
    /// and a width hovering at a column boundary must not flip the arrangement back and forth.
    @Test func minerDetailWidthOnlySettlesOnColumnChangesWithHysteresis() {
        let policy = MinerDetailWidthPolicy.self
        // Mac boundaries in raw content width: 760 + 32 and 1180 + 32.
        #expect(policy.thresholds(isMac: true) == [792, 1_212])
        // First measurement is always accepted.
        #expect(policy.settledWidth(previous: 0, measured: 1_000, isMac: true) == 1_000)
        // Same arrangement: keep the stored width, so no state write and no re-render.
        #expect(policy.settledWidth(previous: 1_000, measured: 1_100, isMac: true) == 1_000)
        #expect(policy.settledWidth(previous: 1_000, measured: 800, isMac: true) == 1_000)
        // Barely crossing a boundary is ignored in both directions.
        #expect(policy.settledWidth(previous: 1_000, measured: 1_215, isMac: true) == 1_000)
        #expect(policy.settledWidth(previous: 1_000, measured: 785, isMac: true) == 1_000)
        // Clearly crossing it is accepted.
        #expect(policy.settledWidth(previous: 1_000, measured: 1_240, isMac: true) == 1_240)
        #expect(policy.settledWidth(previous: 1_000, measured: 700, isMac: true) == 700)
        // Oscillating across a boundary settles on one value.
        var width: CGFloat = 1_000
        for measured: CGFloat in [1_213, 1_205, 1_220, 1_210, 1_213] {
            width = policy.settledWidth(previous: width, measured: measured, isMac: true)
        }
        #expect(width == 1_000)
        // Invalid measurements never replace a good width.
        #expect(policy.settledWidth(previous: 1_000, measured: .infinity, isMac: true) == 1_000)
        #expect(policy.settledWidth(previous: 1_000, measured: .nan, isMac: true) == 1_000)
    }

    @Test func nativeAutomaticColumnsReflowWithTheDetailViewport() {
        #expect(FleetLayout.macDashboardCardColumns(for: 1_400, preferred: 0) == 3)
        #expect(FleetLayout.macDashboardCardColumns(for: 900, preferred: 0) == 2)
        #expect(FleetLayout.macDashboardCardColumns(for: 500, preferred: 0) == 1)
        #expect(FleetLayout.macDetailColumns(for: 1_400, preferred: 0) == 3)
        #expect(FleetLayout.macDetailColumns(for: 900, preferred: 0) == 2)
        #expect(FleetLayout.macDetailColumns(for: 500, preferred: 0) == 1)
    }

    @Test func nativeWorkspaceUsesEveryAvailableWindowWidthWithoutAPageCap() {
        #expect(FleetLayout.dashboardContentWidth.isInfinite)
        for width: CGFloat in [320, 640, 960, 1_650, 3_300] {
            #expect(FleetLayout.dashboardAvailableWidth(for: width) == width)
        }
        for iPadLimit: CGFloat in [760, 800, 1_180, 1_240] {
            #expect(FleetLayout.pageMaximumWidth(iPadLimit).isInfinite)
        }
    }

    @Test func nativeDesignMetricsMatchTheSharedIPadDesign() {
        for metric: CGFloat in [8, 16, 20, 32, 44, 50] {
            #expect(FleetLayout.desktopPointSize(metric) == metric)
            #expect(FleetLayout.iconSize(metric, forMac: true) == metric)
            #expect(FleetLayout.iconSize(metric, forMac: false) == metric)
        }
        for category in FleetTypography.categories {
            #expect(FleetLayout.preferredDynamicTypeSize(category, forMac: true) == category)
            #expect(FleetLayout.preferredDynamicTypeSize(category, forMac: false) == category)
        }
        #expect(FleetLayout.formRowHeight == 44)
        #expect(FleetLayout.sidebarIconSize == 16)
        #expect(FleetLayout.sidebarIconWidth == 20)
        #expect(FleetLayout.pagePadding == 16)
        #expect(FleetLayout.sectionSpacing == FleetLayout.pagePadding)
        #expect(FleetLayout.readingMaximumWidth(forMac: true).isInfinite)
        #expect(FleetLayout.readingMaximumWidth(forMac: false) == 760)
        #expect(FleetLayout.macDashboardCardColumns(for: 700, preferred: 2) == 2)
        #expect(FleetLayout.macDashboardCardColumns(for: 699, preferred: 2) == 1)
        #expect(FleetLayout.sidebarAddTargetSize >= 44)
    }

    @Test func sharedReadingRolesKeepTheFamiliarTypeHierarchy() {
        #expect(FleetTypography.pointSize(for: .title2) == 22)
        #expect(FleetTypography.pointSize(for: .headline) == 17)
        #expect(FleetTypography.pointSize(for: .body) == 17)
        #expect(FleetTypography.pointSize(for: .subheadline) == 15)
        #expect(FleetTypography.pointSize(for: .footnote) == 13)
        #expect(FleetTypography.pointSize(for: .caption) == 12)
    }

    @MainActor
    @Test func nativeReadingFontsRenderAtTheirBaselineAndGrowForAccessibility() throws {
        func size(_ style: Font.TextStyle, category: DynamicTypeSize) throws -> CGSize {
            let renderer = ImageRenderer(content:
                Text("Hash Fleet readings")
                    .fleetFont(style)
                    .fixedSize()
                    .environment(\.dynamicTypeSize, category)
            )
            return try #require(renderer.nsImage).size
        }

        let body = try size(.body, category: .large)
        let reference = ImageRenderer(content:
            Text("Hash Fleet readings").font(.system(size: 17)).fixedSize()
        )
        let referenceSize = try #require(reference.nsImage).size
        #expect(abs(body.width - referenceSize.width) <= 1)
        #expect(abs(body.height - referenceSize.height) <= 1)

        let support = try size(.footnote, category: .large)
        let heading = try size(.title2, category: .large)
        #expect(support.height < body.height)
        #expect(body.height < heading.height)

        let accessibilityBody = try size(.body, category: .accessibility3)
        #expect(accessibilityBody.width > body.width)
        #expect(accessibilityBody.height > body.height)
    }
}
