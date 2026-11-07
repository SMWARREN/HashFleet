import Foundation

// MARK: - Pure Cadence Accumulator (Testable without Wallclock/CADisplayLink)

public struct CadenceAccumulator: Sendable {
    public static let defaultMaxSamples = 600

    public struct FrameSample: Sendable {
        public let gap: CFTimeInterval
        public let isSlow: Bool

        public init(gap: CFTimeInterval, isSlow: Bool) {
            self.gap = gap
            self.isSlow = isSlow
        }
    }

    public struct Summary: Sendable, Equatable {
        public let callbackFPS: Double
        public let averageFrameMs: Double
        public let p95GapMs: Double
        public let maxGapMs: Double
        public let slowGapsCount: Int
        public let totalSamples: Int

        public init(
            callbackFPS: Double,
            averageFrameMs: Double,
            p95GapMs: Double,
            maxGapMs: Double,
            slowGapsCount: Int,
            totalSamples: Int
        ) {
            self.callbackFPS = callbackFPS
            self.averageFrameMs = averageFrameMs
            self.p95GapMs = p95GapMs
            self.maxGapMs = maxGapMs
            self.slowGapsCount = slowGapsCount
            self.totalSamples = totalSamples
        }
    }

    private let maxSamples: Int
    private var lastTimestamp: CFTimeInterval?
    private var lastTargetInterval: CFTimeInterval?
    public private(set) var samples: [FrameSample] = []
    public private(set) var totalSlowGaps: Int = 0

    public init(maxSamples: Int = defaultMaxSamples) {
        self.maxSamples = max(10, maxSamples)
    }

    public mutating func reset() {
        lastTimestamp = nil
        lastTargetInterval = nil
        samples.removeAll(keepingCapacity: true)
        totalSlowGaps = 0
    }

    public mutating func resetBaseline() {
        lastTimestamp = nil
        lastTargetInterval = nil
    }

    /// Records a new frame timing sample.
    ///
    /// - Parameters:
    ///   - timestamp: Callback start timestamp.
    ///   - targetTimestamp: Next scheduled callback timestamp supplied by the driver.
    ///   - duration: Driver interval (for example, a display-link or timer interval).
    public mutating func recordFrame(
        timestamp: CFTimeInterval,
        targetTimestamp: CFTimeInterval,
        duration: CFTimeInterval
    ) {
        guard timestamp.isFinite, targetTimestamp.isFinite, duration.isFinite,
              timestamp >= 0, targetTimestamp > timestamp, duration > 0 else {
            resetBaseline()
            return
        }
        let expected = targetTimestamp - timestamp
        guard let prev = lastTimestamp else {
            lastTimestamp = timestamp
            lastTargetInterval = expected
            return
        }

        let gap = timestamp - prev
        lastTimestamp = timestamp

        // Only accept positive non-zero gaps
        guard gap > 0 else { return }

        // Rate transitions are not hitches. Compare against both adjacent scheduled intervals,
        // never against duration (which is the display's maximum-rate interval).
        let slowThreshold = max(expected, lastTargetInterval ?? expected) * 1.5
        lastTargetInterval = expected
        let isSlow = gap > slowThreshold

        if isSlow {
            totalSlowGaps += 1
        }

        if samples.count >= maxSamples {
            samples.removeFirst()
        }
        samples.append(FrameSample(gap: gap, isSlow: isSlow))
    }

    /// Computes summary statistics across bounded collected samples.
    public func computeSummary() -> Summary? {
        guard !samples.isEmpty else { return nil }

        let count = samples.count
        var totalGap: CFTimeInterval = 0
        var maxGap: CFTimeInterval = 0
        var gaps: [CFTimeInterval] = []
        gaps.reserveCapacity(count)

        var slowCount = 0
        for sample in samples {
            totalGap += sample.gap
            if sample.gap > maxGap {
                maxGap = sample.gap
            }
            if sample.isSlow {
                slowCount += 1
            }
            gaps.append(sample.gap)
        }

        let avgGap = totalGap / Double(count)
        let callbackFPS = avgGap > 0 ? (1.0 / avgGap) : 0.0

        // p95 calculation (nearest-rank)
        gaps.sort()
        let p95Index = min(max(0, Int(ceil(Double(count) * 0.95)) - 1), count - 1)
        let p95Gap = gaps[p95Index]

        return Summary(
            callbackFPS: callbackFPS,
            averageFrameMs: avgGap * 1000.0,
            p95GapMs: p95Gap * 1000.0,
            maxGapMs: maxGap * 1000.0,
            slowGapsCount: slowCount,
            totalSamples: count
        )
    }
}
