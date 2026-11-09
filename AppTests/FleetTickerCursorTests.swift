import Foundation
import Testing
@testable import HashFleet
import HashFleetCore

@MainActor
struct FleetTickerCursorTests {
    @Test func cursorAdvancesAndWraps() {
        var cursor = FleetTickerCursor()
        cursor.advance(itemCount: 3)
        cursor.advance(itemCount: 3)
        #expect(cursor.selected(itemCount: 3) == 2)
        cursor.advance(itemCount: 3)
        #expect(cursor.selected(itemCount: 3) == 0)
    }

    @Test func cursorManualSelectionClamps() {
        var cursor = FleetTickerCursor()
        cursor.select(9, itemCount: 2)
        #expect(cursor.selected(itemCount: 2) == 1)
        cursor.select(-4, itemCount: 2)
        #expect(cursor.selected(itemCount: 2) == 0)
    }

    @Test func cursorHandlesEmptyAndShrinkingFleets() {
        var cursor = FleetTickerCursor()
        #expect(cursor.selected(itemCount: 0) == nil)
        cursor.advance(itemCount: 0)
        #expect(cursor.selected(itemCount: 0) == nil)
        (0..<5).forEach { _ in cursor.advance(itemCount: 5) }
        // The fleet shrank to 2 miners; the cursor must still land on a real item.
        #expect(cursor.selected(itemCount: 2)! < 2)
    }
    @Test func marqueeClockFreezesResumesAndResetsWithoutLosingPausePosition() {
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        var clock = FleetMarqueeClock()
        clock.setRunning(true, at: origin)
        clock.setRunning(false, at: origin.addingTimeInterval(3))
        #expect(clock.elapsed(at: origin.addingTimeInterval(8)) == 3)
        #expect(clock.remaining(in: 12, at: origin.addingTimeInterval(8)) == 9)
        clock.setRunning(false, at: origin.addingTimeInterval(9))
        #expect(clock.elapsed(at: origin.addingTimeInterval(10)) == 3)
        clock.setRunning(true, at: origin.addingTimeInterval(10))
        #expect(clock.elapsed(at: origin.addingTimeInterval(12)) == 5)
        #expect(clock.remaining(in: 12, at: origin.addingTimeInterval(12)) == 7)
        #expect(clock.remaining(in: 12, at: origin.addingTimeInterval(30)) == 0)
        clock.reset(at: origin.addingTimeInterval(12))
        #expect(clock.elapsed(at: origin.addingTimeInterval(13)) == 1)
    }

    @Test func marqueeClockPreservesPhysicalOffsetWhenReadingWidthChanges() {
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        let oldWidth: CGFloat = 300
        let newWidth: CGFloat = 420
        let gap: CGFloat = 30
        let speed = 30.0
        let sampleDate = origin.addingTimeInterval(5)
        var clock = FleetMarqueeClock()
        clock.setRunning(true, at: origin)

        let oldOffset = FleetMarqueeLayout.offset(
            elapsed: clock.elapsed(at: sampleDate),
            copyWidth: oldWidth,
            gap: gap,
            pixelsPerSecond: speed
        )
        clock.preserveOffset(
            from: oldWidth,
            to: newWidth,
            gap: gap,
            at: sampleDate,
            pixelsPerSecond: speed
        )
        let newOffset = FleetMarqueeLayout.offset(
            elapsed: clock.elapsed(at: sampleDate),
            copyWidth: newWidth,
            gap: gap,
            pixelsPerSecond: speed
        )

        #expect(abs(oldOffset - newOffset) < 0.001)
        #expect(clock.isRunning)
    }

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
            abs(
                FleetMarqueeLayout.offset(
                    elapsed: duration,
                    copyWidth: copyWidth,
                    gap: gap,
                    pixelsPerSecond: speed
                )
            ) < 0.001
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

}
