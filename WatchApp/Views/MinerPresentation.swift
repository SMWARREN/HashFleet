import Foundation
import HashFleetWatchCore
import SwiftUI

/// How a miner should be presented right now, derived from cached readings and the latest fetch outcome.
/// `unreachable` only means the Watch could not fetch. It is not proof the hardware is offline.
enum MinerStatus: Equatable {
    case current
    case stale
    case unreachable
    case notChecked

    var title: String {
        switch self {
        case .current: "Current"
        case .stale: "Stale"
        case .unreachable: "Can't reach"
        case .notChecked: "Not checked yet"
        }
    }

    var symbol: String {
        switch self {
        case .current: "checkmark.circle.fill"
        case .stale: "clock.badge.exclamationmark"
        case .unreachable: "wifi.exclamationmark"
        case .notChecked: "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .current: .hashGold
        case .stale, .unreachable: .hashCaution
        case .notChecked: .secondary
        }
    }
}

@MainActor
struct MinerSnapshot {
    let miner: WatchMiner
    let reading: WatchMinerReading?
    let failure: String?
    let status: MinerStatus

    init(miner: WatchMiner, store: WatchFleetStore, now: Date) {
        self.miner = miner
        let reading = store.readings[miner.id]
        self.reading = reading
        self.failure = store.failures[miner.id]
        if store.failures[miner.id] != nil {
            // The latest fetch failed. Any saved reading keeps its original observation time.
            self.status = .unreachable
        } else if let reading {
            self.status = reading.isStale(at: now) ? .stale : .current
        } else {
            self.status = .notChecked
        }
    }

    var hasFailure: Bool { failure != nil }
}

/// Totals over fresh readings only. Missing fields are never counted as zero, and each metric tracks its own
/// reporter count so a partial subtotal is always disclosed per metric.
struct FleetTotals {
    private(set) var minerCount = 0
    private(set) var currentCount = 0
    private(set) var hashrateGHs = 0.0
    private(set) var hashrateReporters = 0
    private(set) var powerWatts = 0.0
    private(set) var powerReporters = 0
    private(set) var attentionCount = 0

    @MainActor
    init(store: WatchFleetStore, now: Date) {
        minerCount = store.miners.count
        for miner in store.miners {
            let snapshot = MinerSnapshot(miner: miner, store: store, now: now)
            switch snapshot.status {
            case .current:
                currentCount += 1
                if let value = Self.usable(snapshot.reading?.hashrateGHs) {
                    hashrateGHs = Self.boundedSum(hashrateGHs, value)
                    hashrateReporters += 1
                }
                if let value = Self.usable(snapshot.reading?.powerWatts) {
                    powerWatts = Self.boundedSum(powerWatts, value)
                    powerReporters += 1
                }
            case .stale, .unreachable:
                attentionCount += 1
            case .notChecked:
                break
            }
        }
    }

    /// True when some miners are not current, so every total covers fewer miners than the fleet.
    var isPartialFleet: Bool { currentCount < minerCount }
    /// True when a current miner did not report hashrate.
    var isHashratePartial: Bool { hashrateReporters < currentCount }
    /// True when a current miner did not report power.
    var isPowerPartial: Bool { powerReporters < currentCount }
    var isPartial: Bool { isPartialFleet || isHashratePartial || isPowerPartial }

    private static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Adds without ever producing infinity from huge reported values.
    private static func boundedSum(_ total: Double, _ value: Double) -> Double {
        let sum = total + value
        return sum.isFinite ? sum : Double.greatestFiniteMagnitude
    }
}

enum WatchFormat {
    static let notReported = "Not reported"

    private static func nonNegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    static func hashrate(_ gigahashPerSecond: Double?) -> String {
        guard let value = nonNegative(gigahashPerSecond) else { return notReported }
        if value >= 1_000 {
            return String(format: "%.2f TH/s", value / 1_000)
        }
        return String(format: "%.1f GH/s", value)
    }

    static func power(_ watts: Double?) -> String {
        guard let watts = nonNegative(watts) else { return notReported }
        return String(format: "%.1f W", watts)
    }

    static func temperature(_ celsius: Double?) -> String {
        guard let celsius, celsius.isFinite, celsius >= 0 else { return notReported }
        return String(format: "%.0f°C", celsius)
    }

    static func count(_ value: Int?) -> String {
        guard let value, value >= 0 else { return notReported }
        return value.formatted()
    }

    /// Clamps a finite, non-negative duration to a whole number of seconds that cannot trap `Int(_:)`.
    private static func wholeSeconds(_ seconds: Double?) -> Int? {
        guard let seconds = nonNegative(seconds) else { return nil }
        // 1e15 seconds is far beyond any real uptime or cached age and safely below Int.max.
        return Int(min(seconds, 1e15))
    }

    static func uptime(_ seconds: Double?) -> String {
        guard let total = wholeSeconds(seconds) else { return notReported }
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Plain-language age, recomputed from the timeline date so it advances without any network work.
    /// Invalid or substantially future dates are not represented as a recent observation.
    static func age(of date: Date, now: Date) -> String {
        let interval = now.timeIntervalSince(date)
        guard interval.isFinite, interval >= -5 else { return "time unknown" }
        guard let seconds = wholeSeconds(interval.isFinite ? max(0, interval) : nil) else { return "time unknown" }
        switch seconds {
        case ..<10: return "just now"
        case ..<60: return "\(seconds) sec ago"
        case ..<3_600: return "\(seconds / 60) min ago"
        case ..<86_400: return "\(seconds / 3_600) hr ago"
        default: return "\(seconds / 86_400) d ago"
        }
    }
}
