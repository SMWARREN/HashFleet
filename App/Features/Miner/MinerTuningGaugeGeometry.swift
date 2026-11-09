import SwiftUI

/// Shared angle and value math used by the production 240 degree tuning dials.
/// Kept independent of view state so mapping and snapping can be tested directly.
enum MinerTuningDialGeometry {
    static let startDegrees = 150.0
    static let sweepDegrees = 240.0

    static func radius(in size: CGSize) -> CGFloat { min(size.width, size.height) / 2 * 0.95 }

    static func fraction(_ value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    static func angle(_ fraction: Double) -> Angle { .degrees(startDegrees + sweepDegrees * fraction) }

    static func point(_ fraction: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let radians = angle(fraction).radians
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    /// The open gap at the bottom snaps to the nearest end, including the original tie rule.
    static func fraction(at location: CGPoint, center: CGPoint) -> Double {
        let degrees = atan2(location.y - center.y, location.x - center.x) * 180 / .pi
        var relative = (degrees - startDegrees).truncatingRemainder(dividingBy: 360)
        if relative < 0 { relative += 360 }
        if relative <= sweepDegrees { return relative / sweepDegrees }
        return relative < sweepDegrees + (360 - sweepDegrees) / 2 ? 1 : 0
    }

    static func snapped(_ value: Double, step: Double, in range: ClosedRange<Double>) -> Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard step > 0 else { return clamped }
        let snapped = range.lowerBound + ((clamped - range.lowerBound) / step).rounded() * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    /// A "nice" major tick interval giving roughly eight labelled divisions.
    static func majorInterval(span: Double, step: Double) -> Double {
        let raw = max(span / 8, step, 0.000_1)
        let magnitude = pow(10, floor(log10(raw)))
        for factor in [1.0, 2, 2.5, 5] where factor * magnitude >= raw { return factor * magnitude }
        return 10 * magnitude
    }
}
