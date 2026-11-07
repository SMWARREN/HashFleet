import CoreGraphics
import Testing
@testable import HashFleet

struct FleetBalancedColumnsLayoutTests {
    @Test(arguments: [1, 3, 5, 7])
    func unpairedFinalSectionUsesTheFullRow(count: Int) {
        let frames = FleetBalancedRowGeometry.frames(
            itemCount: count, width: 1_000, columns: 2, spacing: 14
        ) { _, _ in 40 }
        #expect(frames.count == count)
        #expect(frames.last?.minX == 0)
        #expect(frames.last?.width == 1_000)
        #expect(frames.last?.minY == CGFloat(count / 2) * 54)
    }

    @Test(arguments: [2, 4, 6])
    func pairedSectionsShareTheRowEqually(count: Int) {
        let frames = FleetBalancedRowGeometry.frames(
            itemCount: count, width: 1_000, columns: 2, spacing: 14
        ) { _, _ in 40 }
        #expect(frames.allSatisfy { $0.width == 493 })
        for index in stride(from: 0, to: count, by: 2) {
            #expect(frames[index].minY == frames[index + 1].minY)
            #expect(frames[index].minX == 0)
            #expect(frames[index + 1].maxX == 1_000)
        }
    }

    @Test func rowHeightUsesTheTallerSectionAndFullSpanIsRemeasured() {
        var assignedWidths: [CGFloat] = []
        let frames = FleetBalancedRowGeometry.frames(
            itemCount: 3, width: 1_000, columns: 2, spacing: 14
        ) { index, width in
            assignedWidths.append(width)
            return [40, 80, 25][index]
        }
        #expect(assignedWidths == [493, 493, 1_000])
        #expect(frames[2].minY == 94)
        #expect(frames[2].maxY == 119)
    }

    @Test func substantiallyUnevenMacRowsSpanAndPreserveFollowingPairs() {
        var measuredWidths: [(Int, CGFloat)] = []
        let frames = FleetBalancedRowGeometry.frames(
            itemCount: 3, width: 1_000, columns: 2, spacing: 14, avoidsUnevenRows: true
        ) { index, width in
            measuredWidths.append((index, width))
            return index == 0 ? (width == 1_000 ? 180 : 300) : 60
        }
        #expect(frames.map(\.width) == [1_000, 493, 493])
        #expect(frames.map(\.minY) == [0, 194, 194])
        #expect(measuredWidths.contains { $0.0 == 0 && $0.1 == 1_000 })
        #expect(frames[1].maxX + 14 == frames[2].minX)
    }

    @Test func shortSectionBeforeTallSectionCannotLeaveAnEmptyColumn() {
        let frames = FleetBalancedRowGeometry.frames(
            itemCount: 3, width: 1_000, columns: 2, spacing: 14, avoidsUnevenRows: true
        ) { index, _ in [60, 300, 60][index] }
        #expect(frames.map(\.width) == [1_000, 1_000, 1_000])
        #expect(frames.map(\.minY) == [0, 74, 388])
    }

    @Test func smallWrappingDifferencesDoNotCollapseGoodPairs() {
        #expect(!FleetBalancedRowGeometry.needsFullRow(heights: [200, 240]))
        #expect(FleetBalancedRowGeometry.needsFullRow(heights: [60, 300]))
        #expect(!FleetBalancedRowGeometry.needsFullRow(heights: []))
        #expect(!FleetBalancedRowGeometry.needsFullRow(heights: [.nan, .infinity]))
    }

    @Test func oneColumnAndEmptyListsNeverLeaveAnUnusedCell() {
        let empty = FleetBalancedRowGeometry.frames(
            itemCount: 0, width: 1_000, columns: 2, spacing: 14
        ) { _, _ in
            Issue.record("An empty layout must not request measurements")
            return 0
        }
        #expect(empty.isEmpty)
        let frames = FleetBalancedRowGeometry.frames(
            itemCount: 3, width: 400, columns: 1, spacing: 10
        ) { _, _ in 20 }
        #expect(frames.map(\.width) == [400, 400, 400])
        #expect(frames.map(\.minY) == [0, 30, 60])
    }

    @Test(arguments: [2, 99])
    func invalidPreferencesAndSmallWidthsStayWithinTheRow(columns: Int) {
        let frames = FleetBalancedRowGeometry.frames(
            itemCount: 3, width: 10, columns: columns, spacing: 50
        ) { _, _ in 20 }
        #expect(frames.count == 3)
        #expect(frames.allSatisfy { $0.width >= 0 && $0.maxX <= 10 })
        if columns == 2 {
            #expect(frames.last?.width == 10)
        } else {
            #expect(frames.map(\.width) == [0, 0, 0])
            #expect(frames.map(\.minX) == [0, 5, 10])
        }
    }

    @Test func oddAndEvenCountsWithReflowAndSpacing() {
        let frames5 = FleetBalancedRowGeometry.frames(
            itemCount: 5, width: 800, columns: 2, spacing: 20
        ) { _, _ in 50 }
        #expect(frames5.count == 5)
        #expect(frames5[0].width == 390 && frames5[1].width == 390)
        #expect(frames5[2].width == 390 && frames5[3].width == 390)
        #expect(frames5[4].width == 800 && frames5[4].minX == 0)

        let frames4 = FleetBalancedRowGeometry.frames(
            itemCount: 4, width: 800, columns: 2, spacing: 20
        ) { _, _ in 50 }
        #expect(frames4.count == 4)
        #expect(frames4.allSatisfy { $0.width == 390 })
    }

    @Test func nanAndInfiniteInputsHandledSafelyInGeometry() {
        let frames = FleetBalancedRowGeometry.frames(
            itemCount: 3, width: .nan, columns: -2, spacing: .infinity
        ) { _, _ in 30 }
        #expect(frames.count == 3)
        #expect(frames.allSatisfy { $0.width == 0 && $0.height == 30 })
    }

    @Test func heightClosureReturningNanOrNegativeHandledSafely() {
        let frames = FleetBalancedRowGeometry.frames(
            itemCount: 2, width: 600, columns: 2, spacing: 10
        ) { index, _ in index == 0 ? .nan : -50 }
        #expect(frames.count == 2)
        #expect(frames[0].height == 0)
        #expect(frames[1].height == 0)
    }

    @Test func needsFullRowThresholdBoundaries() {
        #expect(!FleetBalancedRowGeometry.needsFullRow(heights: [100, 184]))
        #expect(FleetBalancedRowGeometry.needsFullRow(heights: [100, 185]))
        #expect(!FleetBalancedRowGeometry.needsFullRow(heights: [400, 540]))
        #expect(FleetBalancedRowGeometry.needsFullRow(heights: [400, 650]))
    }

    @Test func fittingColumnCountChangesAtAvailableWidthBoundaries() {
        func columns(_ width: CGFloat) -> Int {
            FleetBalancedColumnsLayout.fittingColumnCount(
                availableWidth: width,
                maximumColumns: 3,
                itemCount: 6,
                minimumColumnWidth: 320,
                spacing: 14
            )
        }

        #expect(columns(653.99) == 1)
        #expect(columns(654) == 2)
        #expect(columns(987.99) == 2)
        #expect(columns(988) == 3)
        #expect(columns(1_400) == 3)
    }

    @Test func fittingColumnCountRespectsRequestedAndItemLimits() {
        #expect(FleetBalancedColumnsLayout.fittingColumnCount(
            availableWidth: 1_400, maximumColumns: 2, itemCount: 8,
            minimumColumnWidth: 320, spacing: 14
        ) == 2)
        #expect(FleetBalancedColumnsLayout.fittingColumnCount(
            availableWidth: 1_400, maximumColumns: 3, itemCount: 2,
            minimumColumnWidth: 320, spacing: 14
        ) == 2)
        #expect(FleetBalancedColumnsLayout.fittingColumnCount(
            availableWidth: 1_400, maximumColumns: 99, itemCount: 8,
            minimumColumnWidth: 320, spacing: 14
        ) == 3)
        #expect(FleetBalancedColumnsLayout.fittingColumnCount(
            availableWidth: 1_400, maximumColumns: 3, itemCount: 0,
            minimumColumnWidth: 320, spacing: 14
        ) == 0)
    }

    @Test func threeColumnRowsPreserveOrderSpacingAndBounds() {
        let frames = FleetBalancedRowGeometry.frames(
            itemCount: 7, width: 1_000, columns: 3, spacing: 14
        ) { _, _ in 40 }

        #expect(frames.count == 7)
        #expect(frames.prefix(3).map(\.width) == [324, 324, 324])
        #expect(frames.prefix(3).map(\.minX) == [0, 338, 676])
        #expect(frames.prefix(3).allSatisfy { $0.minY == 0 && $0.maxX <= 1_000 })
        // Seven items flow as 3 + 3 + 1. Only the incomplete final row expands.
        #expect(frames[3...5].map(\.width) == [324, 324, 324])
        #expect(frames[3...5].map(\.minX) == [0, 338, 676])
        #expect(frames[3...5].allSatisfy { $0.minY == 54 })
        #expect(frames[6].width == 1_000 && frames[6].minX == 0)
        #expect(frames[6].minY == 108)

        for lhs in frames.indices {
            for rhs in frames.indices where rhs > lhs {
                #expect(!frames[lhs].intersects(frames[rhs]))
            }
        }
        #expect(frames.allSatisfy { $0.minX >= 0 && $0.maxX <= 1_000 })
    }

    @Test func threeColumnPartialRowsUseFullWidthOrEqualHalves() {
        let single = FleetBalancedRowGeometry.frames(
            itemCount: 1, width: 900, columns: 3, spacing: 18
        ) { _, _ in 50 }
        let pair = FleetBalancedRowGeometry.frames(
            itemCount: 2, width: 900, columns: 3, spacing: 18
        ) { _, _ in 50 }
        let fullRowThenPair = FleetBalancedRowGeometry.frames(
            itemCount: 5, width: 900, columns: 3, spacing: 18
        ) { _, _ in 50 }

        #expect(single.map(\.width) == [900])
        #expect(pair.map(\.width) == [441, 441])
        #expect(pair.map(\.minX) == [0, 459])
        #expect(pair[0].minY == pair[1].minY)
        #expect(fullRowThenPair.prefix(3).map(\.width) == [288, 288, 288])
        #expect(fullRowThenPair.suffix(2).map(\.width) == [441, 441])
        #expect(fullRowThenPair.suffix(2).map(\.minX) == [0, 459])
        #expect(fullRowThenPair.suffix(2).allSatisfy { $0.minY == 68 })
    }

    @Test func responsiveColumnCountReflowsAcrossWidthsWithoutChangingOrder() {
        let widths: [CGFloat] = [640, 800, 1_000]
        let columnCounts = widths.map { width in
            FleetBalancedColumnsLayout.fittingColumnCount(
                availableWidth: width,
                maximumColumns: 3,
                itemCount: 5,
                minimumColumnWidth: 320,
                spacing: 14
            )
        }
        #expect(columnCounts == [1, 2, 3])

        for (width, columns) in zip(widths, columnCounts) {
            let frames = FleetBalancedRowGeometry.frames(
                itemCount: 5, width: width, columns: columns, spacing: 14
            ) { _, _ in 40 }
            #expect(frames.count == 5)
            #expect(frames.allSatisfy { $0.minX >= 0 && $0.maxX <= width })
            #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.0.minY <= $0.1.minY })
        }
    }

    @Test func threeColumnLayoutClampsInvalidWidthsSpacingAndColumnRequests() {
        let frames = FleetBalancedRowGeometry.frames(
            itemCount: 5, width: 10, columns: 99, spacing: 50
        ) { _, _ in 20 }
        #expect(frames.count == 5)
        #expect(frames.allSatisfy { $0.width >= 0 && $0.minX >= 0 && $0.maxX <= 10 })

        #expect(FleetBalancedColumnsLayout.fittingColumnCount(
            availableWidth: .nan, maximumColumns: 3, itemCount: 5,
            minimumColumnWidth: 320, spacing: 14
        ) == 1)
        #expect(FleetBalancedColumnsLayout.fittingColumnCount(
            availableWidth: 1_000, maximumColumns: 3, itemCount: 5,
            minimumColumnWidth: .infinity, spacing: 14
        ) == 1)
        #expect(FleetBalancedColumnsLayout.fittingColumnCount(
            availableWidth: 1_000, maximumColumns: 3, itemCount: 5,
            minimumColumnWidth: 320, spacing: .infinity
        ) == 3)
    }
}
