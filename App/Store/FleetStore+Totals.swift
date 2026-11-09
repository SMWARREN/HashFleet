import Foundation
import Observation
import HashFleetCore

/// Release-only presentation policy. Keep saved devices, credentials, adapters and tests intact.
/// Flip this single flag to restore the XMRig add/dashboard/detail/history entry points.
enum FleetReleaseFeatures {
    static let xmrigEnabled = false

    static func includes(_ kind: MinerDevice.Kind, xmrigEnabled: Bool = xmrigEnabled) -> Bool {
        kind != .xmrig || xmrigEnabled
    }

    static func visibleDevices(_ devices: [MinerDevice], xmrigEnabled: Bool = xmrigEnabled) -> [MinerDevice] {
        devices.filter { includes($0.kind, xmrigEnabled: xmrigEnabled) }
    }
}

/// Fleet-wide metric aggregation types used by FleetStore and the dashboard cards.
/// A missing reading is never a zero, and a subtotal never presents as the whole fleet.

struct PollResult: Sendable {
    let id: UUID
    let info: MinerInfo?
    let error: String?
}

/// One aggregate metric plus how much of the online fleet it actually covers.
///
/// A valid firmware response is not a promise that every metric is present: audited ESP-Miner
/// emits `-1`/`0` placeholders for uninitialized sensors, older firmware omits keys entirely, and a
/// partial payload may carry nothing but a hostname. Absent readings are excluded rather than summed
/// as zero, so a subtotal is never presented as the whole fleet.
struct FleetMetricTotal: Equatable, Sendable {
    /// Sum of usable reported values. Zero when nothing was reported, paired with `reporting == 0`.
    let value: Double
    /// Online miners that reported a usable value for this metric.
    let reporting: Int
    /// Online miners considered, whether or not they reported this metric.
    let online: Int

    static let empty = FleetMetricTotal(value: 0, reporting: 0, online: 0)

    /// True when at least one online miner reported this metric.
    var hasReading: Bool { reporting > 0 }
    /// True when every online miner reported it, so the sum covers the whole online fleet.
    var isComplete: Bool { reporting == online }
    /// True when some but not all online miners reported it, so the sum is a labelled subtotal.
    var isPartial: Bool { hasReading && !isComplete }
    var missing: Int { max(0, online - reporting) }

    /// Sums only finite, non-negative values found at `keys`, in order of preference per miner.
    /// Negative and non-finite readings are firmware placeholders or corruption, never real totals.
    init(snapshots: [MinerSnapshot], keys: [String]) {
        var sum = 0.0
        var counted = 0
        for snapshot in snapshots {
            guard let reading = Self.reading(snapshot.info, keys: keys) else { continue }
            sum += reading
            counted += 1
        }
        value = counted > 0 ? sum : 0
        reporting = counted
        online = snapshots.count
    }

    init(value: Double, reporting: Int, online: Int) {
        self.value = value
        self.reporting = reporting
        self.online = online
    }

    /// A usable reading at the first present key, or nil.
    ///
    /// `JSONValue.doubleValue` deliberately parses finite numeric strings, and both `FleetFormat.sensor`
    /// on the cards and the refresh history already accept them from older or custom firmware. Totals
    /// use exactly the same rule so one screen never disagrees with another about whether a miner
    /// reported a value. Booleans, null, objects, arrays and non-numeric strings yield nil, as do
    /// negative and non-finite numbers, which are firmware placeholders rather than real readings.
    static func reading(_ info: MinerInfo?, keys: [String]) -> Double? {
        guard let info else { return nil }
        for key in keys {
            guard let raw = info.raw[key] else { continue }
            // A bool is numerically coercible in some encodings but is never a metric.
            if case .bool = raw { return nil }
            guard let number = raw.doubleValue, number.isFinite, number >= 0 else { return nil }
            return number
        }
        return nil
    }
}

/// Fleet efficiency in joules per terahash.
///
/// Reported only when every online miner contributed both a hashrate and a power reading. A partial
/// pair would divide one subset's watts by another subset's terahashes, which is not the fleet's
/// efficiency and cannot be corrected by a caption. Incomplete coverage is "Not reported" instead.
struct FleetEfficiencyTotal: Equatable, Sendable {
    /// J/TH, or nil when pair coverage is incomplete or a pair total is unusable.
    let value: Double?
    /// Online miners that reported both metrics.
    let reporting: Int
    let online: Int

    static let empty = FleetEfficiencyTotal(value: nil, reporting: 0, online: 0)

    var hasReading: Bool { value != nil }
    /// Coverage is complete whenever every online miner reported both metrics, even if the resulting
    /// figure is undefined because the fleet reported a zero hashrate.
    var isComplete: Bool { online > 0 && reporting == online }
    /// Some but not all online miners reported both metrics, so no figure is shown.
    var isPartial: Bool { reporting > 0 && reporting < online }

    init(value: Double?, reporting: Int, online: Int) {
        self.value = value
        self.reporting = reporting
        self.online = online
    }

    init(snapshots: [MinerSnapshot]) {
        var hashrate = 0.0
        var power = 0.0
        var paired = 0
        for snapshot in snapshots {
            guard let rate = FleetMetricTotal.reading(snapshot.info, keys: FleetTotals.hashrateKeys),
                let watts = FleetMetricTotal.reading(snapshot.info, keys: FleetTotals.powerKeys)
            else { continue }
            hashrate += rate
            power += watts
            paired += 1
        }
        online = snapshots.count
        reporting = paired
        // Hashrate is GH/s, so scale to TH/s. A zero-hashrate pair has no defined efficiency.
        guard paired > 0, paired == online, hashrate > 0, power > 0 else {
            value = nil
            return
        }
        let result = power / (hashrate / 1_000)
        value = result.isFinite ? result : nil
    }
}

/// Aggregates over the online snapshots, keeping completeness alongside every sum.
struct FleetTotals: Equatable, Sendable {
    /// Audited ESP-Miner emits `hashRate`; `hashrate` covers older and third-party firmware.
    static let hashrateKeys = ["hashRate", "hashrate"]
    static let powerKeys = ["power"]

    let hashrate: FleetMetricTotal
    let power: FleetMetricTotal
    let efficiency: FleetEfficiencyTotal

    init(snapshots: [MinerSnapshot]) {
        hashrate = FleetMetricTotal(snapshots: snapshots, keys: Self.hashrateKeys)
        power = FleetMetricTotal(snapshots: snapshots, keys: Self.powerKeys)
        efficiency = FleetEfficiencyTotal(snapshots: snapshots)
    }

    /// Safe to publish to widgets and Live Activities only when nothing is online, or when both
    /// metrics cover every online miner. The shared FleetGlance carries no completeness field, so a
    /// partial subtotal there would be indistinguishable from a true fleet total.
    var isPublishable: Bool {
        hashrate.online == 0 || (hashrate.isComplete && power.isComplete)
    }
}

enum FleetError: LocalizedError {
    case duplicate
    case recoveryFailed
    case invalidName
    case missingDevice
    case demoReadOnly
    var errorDescription: String? {
        switch self {
        case .duplicate: "This miner is already in your fleet."
        case .recoveryFailed:
            "The unreadable fleet could not be backed up. The original saved data has not been changed."
        case .invalidName: "Use a name of up to 64 characters without line breaks or control characters."
        case .missingDevice: "This miner is no longer in your fleet."
        case .demoReadOnly: "Demo miners are read only. Exit the demo to manage your saved fleet."
        }
    }
}
