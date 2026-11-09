import SwiftUI
import Testing
#if os(macOS)
@testable import HashFleetMac
#else
@testable import HashFleet
#endif

@Suite("Responsive miner detail rows")
struct FleetMinerDetailGridTests {
    @Test(arguments: [320, 480, 728, 1028, 2056] as [CGFloat])
    func metricPairsUseTheEntireWidthAndMatchHeight(_ width: CGFloat) {
        let frames = FleetMinerDetailGeometry.frames(configuration: .init(itemCount: 2, width: width,
            maximumColumns: 2, minimumColumnWidth: 140, spacing: 10)) { index, _ in index == 0 ? 60 : 95 }
        #expect(frames.count == 2)
        #expect(frames[0].height == 95 && frames[1].height == 95)
        #expect(frames[0].width == (width - 10) / 2)
        #expect(frames[1].maxX == width)
        #expect(frames[0].minY == frames[1].minY)
    }

    @Test(arguments: [320, 480, 728, 1028, 2056] as [CGFloat])
    func allFourActionsHaveRealEqualWidthColumns(_ width: CGFloat) {
        let frames = FleetMinerDetailGeometry.frames(configuration: .init(itemCount: 4, width: width,
            maximumColumns: 4, minimumColumnWidth: 130, spacing: 8)) { index, _ in 72 + CGFloat(index * 5) }
        let columns = width >= 544 ? 4 : 2
        #expect(frames.count == 4)
        #expect(frames.allSatisfy { $0.width == (width - CGFloat(columns - 1) * 8) / CGFloat(columns) })
        for row in Dictionary(grouping: frames, by: \.minY).values {
            #expect(Set(row.map(\.height)).count == 1)
            #expect(row.map(\.maxX).max() == width)
        }
    }

    @Test func oddSensorCountAndSingleCardFillTheirLastRow() {
        let frames = FleetMinerDetailGeometry.frames(configuration: .init(itemCount: 5, width: 728,
            maximumColumns: 2, minimumColumnWidth: 140, spacing: 10)) { _, width in width < 400 ? 90 : 60 }
        #expect(frames.last?.width == 728)
        #expect(frames.last?.height == 60, "Measure the unpaired sensor at its actual full-row width")
        #expect(frames.last?.minY == 200)
        let single = FleetMinerDetailGeometry.frames(configuration: .init(itemCount: 1, width: 2056,
            maximumColumns: 4, minimumColumnWidth: 130, spacing: 8)) { _, _ in 72 }
        #expect(single == [CGRect(x: 0, y: 0, width: 2056, height: 72)])
    }

    @Test func desktopMinerCardsKeepThreeColumnsAndMeasureEachRowIndependently() {
        let heights: [CGFloat] = [180, 420, 240, 160]
        let frames = FleetMinerDetailGeometry.frames(configuration: .init(itemCount: 4, width: 1028,
            maximumColumns: 3, minimumColumnWidth: 320, spacing: 14,
            balancesFourItems: false)) { index, _ in heights[index] }
        #expect(frames.count == 4)
        #expect(frames.prefix(3).allSatisfy { $0.minY == 0 && $0.height == 420 })
        #expect(frames[2].maxX == 1028)
        #expect(frames[3] == CGRect(x: 0, y: 434, width: 1028, height: 160))
    }

    @Test func expandedControlAndTelemetryUseTheLargestNaturalHeightInEitherColumn() {
        for heights: [CGFloat] in [[900, 320], [340, 1100]] {
            let frames = FleetMinerDetailGeometry.frames(configuration: .init(itemCount: 2, width: 1028,
                maximumColumns: 2, minimumColumnWidth: 320, spacing: 14)) { index, _ in heights[index] }
            #expect(frames.allSatisfy { $0.height == heights.max() && $0.minY == 0 })
            #expect(frames[0].maxY == frames[1].maxY)
        }
    }

    @Test func accessibilityAndNarrowRowsStackWithoutFixedHeights() {
        for width in [180.0, 480, 2056] {
            let frames = FleetMinerDetailGeometry.frames(configuration: .init(itemCount: 2, width: width,
                maximumColumns: 1, minimumColumnWidth: 140, spacing: 10)) { index, _ in index == 0 ? 160 : 220 }
            #expect(frames[0] == CGRect(x: 0, y: 0, width: width, height: 160))
            #expect(frames[1] == CGRect(x: 0, y: 170, width: width, height: 220))
        }
    }

    @Test func degenerateInputsRemainFiniteAndNonnegative() {
        #expect(FleetMinerDetailGeometry.frames(configuration: .init(itemCount: 0, width: 480, maximumColumns: 4,
            minimumColumnWidth: 130, spacing: 8)) { _, _ in 72 }.isEmpty)
        for width in [CGFloat.zero, -1, .infinity, .nan] {
            let frames = FleetMinerDetailGeometry.frames(configuration: .init(itemCount: 3, width: width,
                maximumColumns: -1, minimumColumnWidth: .nan, spacing: .infinity)) { index, _ in
                index == 0 ? .infinity : index == 1 ? .nan : -5
            }
            #expect(frames.count == 3)
            #expect(frames.allSatisfy { [$0.minX, $0.minY, $0.width, $0.height].allSatisfy { $0.isFinite && $0 >= 0 } })
        }
    }
}
