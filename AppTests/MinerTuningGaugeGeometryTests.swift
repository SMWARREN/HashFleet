import Foundation
import SwiftUI
import Testing
@testable import HashFleet

@Suite("Production tuning dial geometry")
struct MinerTuningGaugeGeometryTests {
    @Test("Configured values map and clamp to the actual sweep", arguments: [
        (300.0, 0.0), (325.0, 0.0), (425.0, 0.25), (525.0, 0.5),
        (675.0, 0.875), (725.0, 1.0), (800.0, 1.0)
    ])
    func valueFraction(value: Double, expected: Double) {
        #expect(MinerTuningDialGeometry.fraction(value, in: 325...725) == expected)
    }

    @Test("A zero-width reference range does not divide by zero", arguments: [-1.0, 0.0, 500.0, 600.0])
    func zeroWidthRange(value: Double) {
        #expect(MinerTuningDialGeometry.fraction(value, in: 500...500) == 0)
    }

    @Test("Angle mapping preserves the 150 degree start and 240 degree sweep", arguments: [
        (0.0, 150.0), (0.25, 210.0), (0.5, 270.0), (0.75, 330.0), (1.0, 390.0)
    ])
    func sweepAngles(fraction: Double, expected: Double) {
        #expect(abs(MinerTuningDialGeometry.angle(fraction).degrees - expected) < 0.000_000_001)
    }

    @Test("Sweep points round-trip through touch mapping across quadrants", arguments: [
        0.0, 0.001, 0.125, 0.25, 0.5, 0.75, 0.875, 0.999, 1.0
    ])
    func sweepRoundTrip(fraction: Double) {
        let center = CGPoint(x: 201, y: 299)
        let radius: CGFloat = 135.2
        let point = MinerTuningDialGeometry.point(fraction, center: center, radius: radius)
        #expect(abs(hypot(point.x - center.x, point.y - center.y) - radius) < 0.000_001)
        #expect(abs(MinerTuningDialGeometry.fraction(at: point, center: center) - fraction) < 0.000_001)
    }

    @Test("The bottom gap snaps to the nearest sweep endpoint, with the original midpoint tie", arguments: [
        (31.0, 1.0), (60.0, 1.0), (89.9, 1.0), (90.0, 0.0), (90.1, 0.0), (120.0, 0.0), (149.0, 0.0)
    ])
    func bottomGap(degrees: Double, expected: Double) {
        let radians = degrees * .pi / 180
        let point = CGPoint(x: 100 * cos(radians), y: 100 * sin(radians))
        #expect(MinerTuningDialGeometry.fraction(at: point, center: .zero) == expected)
    }

    @Test("Radius fits the smaller dimension and keeps the original artwork margin", arguments: [
        (338.0, 338.0, 160.55), (800.0, 200.0, 95.0), (200.0, 800.0, 95.0), (0.0, 200.0, 0.0)
    ])
    func radius(width: Double, height: Double, expected: Double) {
        let actual = MinerTuningDialGeometry.radius(in: CGSize(width: width, height: height))
        #expect(abs(actual - expected) < 0.000_001)
    }

    @Test("Voltage snapping is anchored to the lower bound and clamps both endpoints", arguments: [
        (899.0, 910.0), (910.0, 910.0), (1149.0, 1150.0),
        (1152.5, 1155.0), (1209.0, 1210.0), (1225.0, 1210.0)
    ])
    func voltageSnapping(value: Double, expected: Double) {
        #expect(MinerTuningDialGeometry.snapped(value, step: 5, in: 910...1210) == expected)
    }

    @Test("Non-positive step sizes clamp without division", arguments: [0.0, -5.0])
    func disabledSnapping(step: Double) {
        #expect(MinerTuningDialGeometry.snapped(525.25, step: step, in: 325...725) == 525.25)
        #expect(MinerTuningDialGeometry.snapped(800, step: step, in: 325...725) == 725)
        #expect(MinerTuningDialGeometry.snapped(300, step: step, in: 325...725) == 325)
    }

    @Test("Non-multiple upper endpoints never snap outside the allowed range")
    func nonMultipleUpperBound() {
        #expect(MinerTuningDialGeometry.snapped(1199, step: 25, in: 910...1200) == 1200)
        #expect(MinerTuningDialGeometry.snapped(925, step: 25, in: 910...1200) == 935)
    }

    @Test("Major tick thresholds exercise each nice interval and the fallback", arguments: [
        (8.0, 0.1, 1.0), (9.0, 0.1, 2.0), (17.0, 0.1, 2.5),
        (21.0, 0.1, 5.0), (41.0, 0.1, 10.0), (400.0, 5.0, 50.0),
        (300.0, 5.0, 50.0), (0.0, 0.0, 0.0001), (100.0, 60.0, 100.0)
    ])
    func majorTickIntervals(span: Double, step: Double, expected: Double) {
        let actual = MinerTuningDialGeometry.majorInterval(span: span, step: step)
        #expect(abs(actual - expected) < 0.000_000_1)
        #expect(actual >= max(span / 8, step))
    }

    @Test("The real rim-drag mapping stages 525 to 675 without involving a write path")
    func stagedFrequencyDragMapping() {
        let center = CGPoint(x: 201, y: 299)
        let point = MinerTuningDialGeometry.point(0.875, center: center, radius: 135.2)
        let fraction = MinerTuningDialGeometry.fraction(at: point, center: center)
        let raw = 325 + fraction * 400
        #expect(MinerTuningDialGeometry.snapped(raw, step: 5, in: 325...725) == 675)
    }
}
