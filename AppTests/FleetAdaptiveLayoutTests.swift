import Testing
import SwiftUI
@testable import HashFleet

struct FleetAdaptiveLayoutTests {
    @Test func dashboardContentBudgetIsNotReducedByTheSidebarTwice() {
        let detailWidth = FleetLayout.dashboardAvailableWidth(
            for: 1_650,
            maximumWidth: FleetLayout.pageMaximumWidth(1_180, forMac: true)
        )

        #expect(detailWidth == 1_650)
        #expect(FleetLayout.cardColumns(for: detailWidth) == 4)
    }

    @Test func nativeContentContinuesGrowingWithAnUltrawideWindow() {
        let detailWidth = FleetLayout.dashboardAvailableWidth(
            for: 3_300,
            maximumWidth: FleetLayout.pageMaximumWidth(1_180, forMac: true)
        )

        #expect(detailWidth == 3_300)
        #expect(FleetLayout.cardColumns(for: detailWidth) == 4)
    }

    @Test func narrowWidthsNeverBecomeNegative() {
        #expect(FleetLayout.availableContentWidth(
            viewportWidth: 320,
            maximumWidth: .infinity,
            reservedWidth: 350
        ) == 0)
    }

    @Test func cardColumnsCoverEveryBreakpointBoundary() {
        #expect(FleetLayout.cardColumns(for: 0) == 1)
        #expect(FleetLayout.cardColumns(for: 559) == 1)
        #expect(FleetLayout.cardColumns(for: 560) == 1)
        #expect(FleetLayout.cardColumns(for: 959) == 1)
        #expect(FleetLayout.cardColumns(for: 960) == 2)
        #expect(FleetLayout.cardColumns(for: 1_299) == 2)
        #expect(FleetLayout.cardColumns(for: 1_300) == 3)
        #expect(FleetLayout.cardColumns(for: 1_639) == 3)
        #expect(FleetLayout.cardColumns(for: 1_640) == 4)
    }

    @Test func macDashboardColumnsRespectPreferenceWithoutCrampingNarrowWindows() {
        #expect(FleetLayout.macDashboardCardColumns(for: 699, preferred: 3) == 1)
        #expect(FleetLayout.macDashboardCardColumns(for: 700, preferred: 3) == 2)
        #expect(FleetLayout.macDashboardCardColumns(for: 1_079, preferred: 3) == 2)
        #expect(FleetLayout.macDashboardCardColumns(for: 1_080, preferred: 2) == 2)
        #expect(FleetLayout.macDashboardCardColumns(for: 1_080, preferred: 3) == 3)
        #expect(FleetLayout.macDashboardCardColumns(for: 1_400, preferred: 99) == 3)
        #expect(FleetLayout.macDashboardCardColumns(for: 1_400, preferred: 1) == 1)
        #expect(!FleetLayout.canUseTwoMacDashboardColumns(availableWidth: 699))
        #expect(FleetLayout.canUseTwoMacDashboardColumns(availableWidth: 700))
        #expect(!FleetLayout.canUseThreeMacDashboardColumns(availableWidth: 1_079))
        #expect(FleetLayout.canUseThreeMacDashboardColumns(availableWidth: 1_080))
    }

    @Test func macDetailColumnsRespectPreferenceAndAvailableWidth() {
        #expect(FleetLayout.macDetailColumns(for: 759, preferred: 3) == 1)
        #expect(FleetLayout.macDetailColumns(for: 760, preferred: 3) == 2)
        #expect(FleetLayout.macDetailColumns(for: 1_179, preferred: 3) == 2)
        #expect(FleetLayout.macDetailColumns(for: 1_180, preferred: 2) == 2)
        #expect(FleetLayout.macDetailColumns(for: 1_180, preferred: 3) == 3)
        #expect(FleetLayout.macDetailColumns(for: 1_180, preferred: 1) == 1)
        #expect(FleetLayout.macDetailColumns(for: 2_000, preferred: 99) == 3)
        #expect(FleetLayout.canUseTwoMacDetailColumns(availableWidth: 760))
        #expect(!FleetLayout.canUseTwoMacDetailColumns(availableWidth: 759))
        #expect(!FleetLayout.canUseThreeMacDetailColumns(availableWidth: 1_179))
        #expect(FleetLayout.canUseThreeMacDetailColumns(availableWidth: 1_180))
    }

    @Test func dashboardMenuLayoutDependsOnlyOnWidthAndTextSize() {
        #expect(FleetLayout.dashboardMinerCardUsesHorizontalControls(availableWidth: 0, dynamicTypeSize: .large))
        #expect(FleetLayout.dashboardMinerCardUsesHorizontalControls(availableWidth: 370, dynamicTypeSize: .large))
        #expect(FleetLayout.dashboardMinerCardUsesHorizontalControls(availableWidth: 479, dynamicTypeSize: .large))
        #expect(!FleetLayout.dashboardMinerCardUsesHorizontalControls(availableWidth: 480, dynamicTypeSize: .large))
        #expect(!FleetLayout.dashboardMinerCardUsesHorizontalControls(availableWidth: 900, dynamicTypeSize: .xxLarge))
        #expect(FleetLayout.dashboardMinerCardUsesHorizontalControls(availableWidth: 900, dynamicTypeSize: .xxxLarge))
        #expect(FleetLayout.dashboardMinerCardUsesHorizontalControls(availableWidth: 900, dynamicTypeSize: .accessibility5))
    }

    @Test func allPageContainersShareOneOuterPaddingToken() {
        #expect(FleetLayout.pagePadding == 16)
        #expect(FleetLayout.pagePadding > 0)
    }

    @Test func namedDetailThresholdsRemainOrdered() {
        #expect(FleetLayout.quickControlsThreeColumnThreshold < FleetLayout.twoColumnThreshold)
        #expect(!FleetLayout.usesTwoColumns(width: 959))
        #expect(FleetLayout.usesTwoColumns(width: 960))
        #expect(FleetLayout.compactDetailWidth < FleetLayout.wideDetailWidth)
    }

    @Test func sharedVisualScalePreservesDefaultAndAccessibilitySizes() {
        #expect(FleetLayout.preferredDynamicTypeSize(.large, forMac: true) == .large)
        #expect(FleetLayout.preferredDynamicTypeSize(.accessibility2, forMac: true) == .accessibility2)
        #expect(FleetLayout.preferredDynamicTypeSize(.large, forMac: false) == .large)
        #expect(FleetLayout.iconSize(22, forMac: true) == 22)
        #expect(FleetLayout.iconSize(22, forMac: false) == 22)
    }

    @Test func readingMaximumWidthPlatformBehavior() {
        #expect(FleetLayout.readingMaximumWidth(forMac: true).isInfinite)
        #expect(FleetLayout.readingMaximumWidth(forMac: false) == 760)
    }

    @Test func explicitIPadPageCapsNeverConstrainNativeWorkspaceWidth() {
        for compactLimit: CGFloat in [760, 800, 1_180, 1_240] {
            #expect(FleetLayout.pageMaximumWidth(compactLimit, forMac: true).isInfinite)
            #expect(FleetLayout.pageMaximumWidth(compactLimit, forMac: false) == compactLimit)
            for windowWidth: CGFloat in [320, 640, 960, 1_650, 3_300] {
                #expect(FleetLayout.availableContentWidth(
                    viewportWidth: windowWidth,
                    maximumWidth: FleetLayout.pageMaximumWidth(compactLimit, forMac: true),
                    reservedWidth: 0
                ) == windowWidth)
            }
        }
    }

    @Test func sharedPageAndSectionSpacingUseTheSameRhythm() {
        #expect(FleetLayout.sectionSpacing == FleetLayout.pagePadding)
    }

    @Test func iconAndSidebarDimensions() {
        #expect(FleetLayout.sidebarIconSize == 16)
        #expect(FleetLayout.sidebarIconWidth == 20)
        #expect(FleetLayout.formRowHeight == 44)
    }

    @Test func macCardColumnsUseAutomaticByDefaultAndClampInvalidLimits() {
        #expect(FleetLayout.macDashboardCardColumns(for: 1_200, preferred: 0) == 3)
        #expect(FleetLayout.macDashboardCardColumns(for: 1_200, preferred: -5) == 1)
        #expect(FleetLayout.macDetailColumns(for: 1_200, preferred: 0) == 3)
        #expect(FleetLayout.macDetailColumns(for: 1_200, preferred: -3) == 1)
    }

    @Test func automaticColumnsReflowInBothResizeDirections() {
        let dashboardWidths: [CGFloat] = [1_600, 1_080, 1_079, 700, 699, 320, 699, 700, 1_079, 1_080, 1_600]
        let expected = [3, 3, 2, 2, 1, 1, 1, 2, 2, 3, 3]
        #expect(dashboardWidths.map { FleetLayout.macDashboardCardColumns(for: $0, preferred: 0) } == expected)
        let detailWidths: [CGFloat] = [1_600, 1_180, 1_179, 760, 759, 320, 759, 760, 1_179, 1_180, 1_600]
        #expect(detailWidths.map { FleetLayout.macDetailColumns(for: $0, preferred: 0) } == expected)
    }
}
