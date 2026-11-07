import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

extension FleetStatusTickerTests {
    // MARK: - Continuous marquee geometry

    @Test func marqueeTravelIncludesTheCopyGap() {
        #expect(FleetMarqueeLayout.travelDistance(copyWidth: 420, gap: 30) == 450)
        #expect(FleetMarqueeLayout.travelDistance(copyWidth: -1, gap: -2) == 0)
    }

    @Test func marqueeOffsetLoopsAtTheSecondCopyBoundary() {
        let copyWidth: CGFloat = 300
        let gap: CGFloat = 30
        let speed = 30.0
        let duration = Double(copyWidth + gap) / speed
        #expect(FleetMarqueeLayout.offset(elapsed: 0, copyWidth: copyWidth, gap: gap, pixelsPerSecond: speed) == 0)
        #expect(
            abs(
                FleetMarqueeLayout.offset(
                    elapsed: duration / 2,
                    copyWidth: copyWidth,
                    gap: gap,
                    pixelsPerSecond: speed
                ) - 165
            ) < 0.001
        )
        #expect(
            abs(FleetMarqueeLayout.offset(elapsed: duration, copyWidth: copyWidth, gap: gap, pixelsPerSecond: speed))
                < 0.001
        )
    }

    // MARK: - Geometry transition adjustments (jump prevention)

    @Test func firstMeasuredWidthRestartsTheClockSoTheTrackDoesNotJumpOnAppear() {
        // Before any width arrives the track renders pinned at offset 0. If the clock kept its
        // accumulated time, the first scrollable frame would reinterpret it against the new
        // travel distance and teleport the text. A reset keeps offset 0 continuous.
        let adjustment = FleetMarqueeLayout.adjustment(
            oldCopyWidth: 0,
            newCopyWidth: 420,
            wasScrollable: false,
            isScrollable: true
        )
        #expect(adjustment == .reset)

        let origin = Date(timeIntervalSinceReferenceDate: 0)
        var clock = FleetMarqueeClock()
        clock.setRunning(true, at: origin)
        let widthArrivesAt = origin.addingTimeInterval(3)
        clock.reset(at: widthArrivesAt)
        let offset = FleetMarqueeLayout.offset(
            elapsed: clock.elapsed(at: widthArrivesAt),
            copyWidth: 420,
            gap: 30,
            pixelsPerSecond: 30
        )
        #expect(offset == 0)
        #expect(clock.elapsed(at: widthArrivesAt) == 0)
        #expect(clock.isRunning)
    }

    @Test func shortTrackThatBecomesScrollableRestartsInsteadOfJumpingToMidPhase() {
        // Telemetry grew the text so the track now exceeds the viewport. It displayed offset 0
        // while unscrollable, so scrolling must also begin at offset 0.
        #expect(
            FleetMarqueeLayout.adjustment(
                oldCopyWidth: 300,
                newCopyWidth: 900,
                wasScrollable: false,
                isScrollable: true
            ) == .reset
        )
        // Growing the track while already unscrollable changes nothing visible.
        #expect(
            FleetMarqueeLayout.adjustment(
                oldCopyWidth: 100,
                newCopyWidth: 300,
                wasScrollable: false,
                isScrollable: false
            ) == .none
        )
    }

    @Test func widthChangeWhileScrollingPreservesThePhysicalOffset() {
        #expect(
            FleetMarqueeLayout.adjustment(
                oldCopyWidth: 900,
                newCopyWidth: 940,
                wasScrollable: true,
                isScrollable: true
            ) == .preserveOffset
        )
    }

    @Test func unscrollableWidthKeepsGeometryUntouched() {
        #expect(
            FleetMarqueeLayout.adjustment(
                oldCopyWidth: 200,
                newCopyWidth: 0,
                wasScrollable: false,
                isScrollable: false
            ) == .none
        )
    }

    @Test func pausedClockKeepsDisplayedOffsetWhenWidthChanges() {
        // Paused means frozen pixels; a new reading must not move them either.
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        var clock = FleetMarqueeClock()
        clock.setRunning(true, at: origin)
        clock.setRunning(false, at: origin.addingTimeInterval(5))
        let sample = origin.addingTimeInterval(9)
        let before = FleetMarqueeLayout.offset(
            elapsed: clock.elapsed(at: sample),
            copyWidth: 300,
            gap: 30,
            pixelsPerSecond: 30
        )
        clock.preserveOffset(from: 300, to: 460, gap: 30, at: sample, pixelsPerSecond: 30)
        let after = FleetMarqueeLayout.offset(
            elapsed: clock.elapsed(at: sample),
            copyWidth: 460,
            gap: 30,
            pixelsPerSecond: 30
        )
        #expect(abs(before - after) < 0.001)
        #expect(!clock.isRunning)
        // Still true later: pausing is not a slow drift.
        let later = FleetMarqueeLayout.offset(
            elapsed: clock.elapsed(at: origin.addingTimeInterval(60)),
            copyWidth: 460,
            gap: 30,
            pixelsPerSecond: 30
        )
        #expect(abs(before - later) < 0.001)
    }

    @Test func repeatedWidthChangesKeepOffsetContinuousAcrossCycles() {
        // Simulate several telemetry-driven width updates while running; every step must land
        // within a sub-point of the pre-change physical offset, and the sequence must never
        // reset to the origin.
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        let gap: CGFloat = 30
        let speed = 34.0
        var clock = FleetMarqueeClock()
        clock.setRunning(true, at: origin)
        let widths: [CGFloat] = [640, 700, 655, 812]
        var previousWidth = widths[0]
        for (index, width) in widths.dropFirst().enumerated() {
            let sample = origin.addingTimeInterval(Double(index + 1) * 2.5)
            let before = FleetMarqueeLayout.offset(
                elapsed: clock.elapsed(at: sample),
                copyWidth: previousWidth,
                gap: gap,
                pixelsPerSecond: speed
            )
            clock.preserveOffset(
                from: previousWidth,
                to: width,
                gap: gap,
                at: sample,
                pixelsPerSecond: speed
            )
            let after = FleetMarqueeLayout.offset(
                elapsed: clock.elapsed(at: sample),
                copyWidth: width,
                gap: gap,
                pixelsPerSecond: speed
            )
            #expect(abs(before - after) < 0.001)
            #expect(before > 0)  // the track had genuinely scrolled, so continuity matters
            previousWidth = width
        }
    }

    @Test func scrollingStatusMatchesWhatTheTrackRenders() {
        #expect(FleetMarqueeLayout.isScrollable(copyWidth: 400, gap: 30, viewportWidth: 320))
        #expect(!FleetMarqueeLayout.isScrollable(copyWidth: 280, gap: 30, viewportWidth: 320))
        #expect(!FleetMarqueeLayout.isScrollable(copyWidth: 289, gap: 30, viewportWidth: 320))
        #expect(FleetMarqueeLayout.isScrollable(copyWidth: 320, gap: 30, viewportWidth: 320))
    }

    // MARK: - Previous sample cooling context

    @Test func coolingComparisonUsesOnlyFieldsReportedInBothSamples() {
        let previous = MinerInfo(raw: [
            "temp": .number(62), "vrTemp": .number(64), "fanspeed": .number(60)
        ])
        let current = MinerInfo(raw: [
            "temp": .number(59), "fanspeed": .number(65)
        ])

        let readings = MinerCoolingComparison.readings(current: current, previous: previous)
        #expect(readings.map(\.id) == ["chipTemp", "fanSpeed"])
        #expect(readings.first?.direction == .decreased)
        #expect(readings.first?.delta == -3)
        #expect(readings.last?.direction == .increased)
    }

    @Test func coolingComparisonIsEmptyWithoutAPreviousSuccessfulSample() {
        let current = MinerInfo(raw: ["temp": .number(59), "fanspeed": .number(65)])
        #expect(MinerCoolingComparison.readings(current: current, previous: nil).isEmpty)
    }

    // MARK: - Browser destinations

    @Test func browserDestinationRemovesMiningCredentialsAndStratumPort() {
        let destination = FleetBrowserURL.destination(
            for: "stratum+tcp://worker:secret@pool.example:3333/path?token=hidden#fragment"
        )
        #expect(destination?.absoluteString == "https://pool.example")
    }

    @Test func browserDestinationKeepsExplicitLocalWebSchemeAndPathWithoutQuery() {
        let destination = FleetBrowserURL.destination(for: "http://10.0.0.8/api/system/info?token=hidden")
        #expect(destination?.absoluteString == "http://10.0.0.8/api/system/info")
    }

    @Test func browserDestinationRejectsUnknownSchemesAndEmptyValues() {
        #expect(FleetBrowserURL.destination(for: "javascript://alert") == nil)
        #expect(FleetBrowserURL.destination(for: "   ") == nil)
        #expect(FleetBrowserURL.destination(for: "Not reported") == nil)
    }

    @Test func marqueeOffsetEdgeCasesWithNegativeElapsedAndZeroSpeed() {
        #expect(FleetMarqueeLayout.offset(elapsed: -5, copyWidth: 300, gap: 30, pixelsPerSecond: 30) == 0)
        #expect(FleetMarqueeLayout.offset(elapsed: 10, copyWidth: 300, gap: 30, pixelsPerSecond: 0) == 0)
        #expect(FleetMarqueeLayout.offset(elapsed: 10, copyWidth: 0, gap: 30, pixelsPerSecond: 30) == 0)
    }

    @Test func coolingComparisonEqualReadingsBecomesUnchanged() {
        let previous = MinerInfo(raw: ["temp": .number(60), "fanspeed": .number(50)])
        let current = MinerInfo(raw: ["temp": .number(60), "fanspeed": .number(50)])
        let readings = MinerCoolingComparison.readings(current: current, previous: previous)
        #expect(readings.count == 2)
        #expect(readings.allSatisfy { $0.direction == .unchanged })
        #expect(readings.allSatisfy { $0.delta == 0 })
    }
}
