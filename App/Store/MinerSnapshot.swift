import Foundation
import HashFleetCore

struct HashratePoint: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let value: Double
}

struct MinerSnapshot: Equatable, Sendable {
    var info: MinerInfo?
    /// The immediately preceding successful response. This is intentionally in-memory only and is
    /// never persisted or shared with widgets. It supports honest current-vs-previous UI without
    /// treating a missing field or a failed poll as a fabricated zero.
    var previousInfo: MinerInfo?
    var error: String?
    var updatedAt: Date?
    /// Last time a complete HTTP snapshot was received. Live WebSocket frames are partial and may
    /// keep arriving without updating every displayed metric, so they must not reset this clock.
    var completeSnapshotAt: Date?
    var powerObservedAt: Date?
    var history: [HashratePoint] = []
    var isCached = false
    /// Presentation-only: the last connection result is awaiting a foreground check.
    /// Keep errors and cached readings intact until that check actually completes.
    var isReconnecting = false
}

/// A newly reported difficulty share that is strictly better than the miner's previous successful
/// reading. This is a share milestone, not a solved block claim.
/// A persisted best-share baseline, so a new record can be detected across app launches and
/// from a background refresh rather than only within one live session.
struct MinerBestShareObservation: Codable, Equatable, Sendable {
    let bestDiff: String
    let bestSessionDiff: String

    init(info: MinerInfo) {
        bestDiff = info.bestDiff
        bestSessionDiff = info.bestSessionDiff
    }

    init(bestDiff: String, bestSessionDiff: String) {
        self.bestDiff = bestDiff
        self.bestSessionDiff = bestSessionDiff
    }

    func value(for kind: MinerBestShareEvent.Kind) -> String {
        switch kind {
        case .allTime: bestDiff
        case .session: bestSessionDiff
        }
    }
}

struct MinerBestShareEvent: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case allTime
        case session

        var title: String {
            switch self {
            case .allTime: "all-time"
            case .session: "session"
            }
        }

        var field: String {
            switch self {
            case .allTime: "bestDiff"
            case .session: "bestSessionDiff"
            }
        }
    }

    let id: UUID
    let deviceID: UUID
    let minerName: String
    let kind: Kind
    let displayValue: String
    let rawValue: String
    let occurredAt: Date

    init(
        id: UUID = UUID(),
        deviceID: UUID,
        minerName: String,
        kind: Kind,
        displayValue: String,
        rawValue: String,
        occurredAt: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.minerName = minerName
        self.kind = kind
        self.displayValue = displayValue
        self.rawValue = rawValue
        self.occurredAt = occurredAt
    }

    /// Requires a previous valid value so the first successful snapshot never celebrates a
    /// baseline. If both fields improve, the all-time milestone is the useful single notification.
    static func detect(
        device: MinerDevice,
        previous: MinerInfo?,
        current: MinerInfo,
        occurredAt: Date
    ) -> MinerBestShareEvent? {
        detect(
            device: device,
            previous: previous.map(MinerBestShareObservation.init),
            current: MinerBestShareObservation(info: current),
            occurredAt: occurredAt
        )
    }

    /// Detects a strictly greater best share against a baseline. The first observation is always
    /// a baseline and never alerts, matching the block-found rule.
    ///
    /// `allTimeFloor` is a persisted monotonic high-water mark for the all-time record. A miner
    /// reset or firmware flash wipes NVS, so the firmware's `bestDiff` can drop back toward 0 and
    /// then climb again, re-passing a record the fleet already celebrated. Requiring the all-time
    /// value to beat both the previous reading and this floor prevents that duplicate. Session best
    /// legitimately restarts each run, so it is only compared against the previous reading.
    static func detect(
        device: MinerDevice,
        previous: MinerBestShareObservation?,
        current: MinerBestShareObservation,
        occurredAt: Date,
        allTimeFloor: Decimal? = nil
    ) -> MinerBestShareEvent? {
        guard let previous else { return nil }

        for kind in [Kind.allTime, .session] {
            let oldRaw = previous.value(for: kind)
            let newRaw = current.value(for: kind)

            guard let oldValue = MiningDifficultyFormat.parse(oldRaw),
                let newValue = MiningDifficultyFormat.parse(newRaw)
            else { continue }

            // All-time must exceed the monotonic high-water mark, not just the last reading,
            // so a post-reset climb cannot re-celebrate a record that already happened.
            let threshold: Decimal
            if kind == .allTime, let floor = allTimeFloor {
                threshold = max(oldValue, floor)
            } else {
                threshold = oldValue
            }
            guard newValue > threshold else { continue }

            return MinerBestShareEvent(
                deviceID: device.id,
                minerName: device.name,
                kind: kind,
                displayValue: MiningDifficultyFormat.format(newValue),
                rawValue: newRaw,
                occurredAt: occurredAt
            )
        }
        return nil
    }
}

/// Explicit block evidence as reported by ESP-Miner. A difficulty share is deliberately not part
/// of this model: it is useful mining progress, but it is not proof that a block was solved.
struct MinerBlockFoundObservation: Codable, Equatable, Sendable {
    let count: Int?
    let showNewBlock: Bool
    let height: Int?
    let uptimeSeconds: Int?
    let bestDiff: String?
    let networkDifficulty: String?

    init(info: MinerInfo) {
        count = info.raw["blockFound"]?.intValue
        showNewBlock = info.raw["showNewBlock"]?.boolValue == true
        height = info.raw["blockHeight"]?.intValue
        uptimeSeconds = info.raw["uptimeSeconds"]?.intValue
        bestDiff = info.raw["bestDiff"]?.stringValue
        networkDifficulty = info.raw["networkDifficulty"]?.stringValue
    }

    init(
        count: Int?,
        showNewBlock: Bool,
        height: Int?,
        uptimeSeconds: Int? = nil,
        bestDiff: String? = nil,
        networkDifficulty: String? = nil
    ) {
        self.count = count
        self.showNewBlock = showNewBlock
        self.height = height
        self.uptimeSeconds = uptimeSeconds
        self.bestDiff = bestDiff
        self.networkDifficulty = networkDifficulty
    }
}

struct MinerBlockFoundEvent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let deviceID: UUID
    let minerName: String
    let coinLabel: String?
    let height: Int?
    let count: Int?
    let occurredAt: Date

    init(
        id: UUID = UUID(),
        deviceID: UUID,
        minerName: String,
        coinLabel: String?,
        height: Int?,
        count: Int?,
        occurredAt: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.minerName = minerName
        self.coinLabel = coinLabel
        self.height = height
        self.count = count
        self.occurredAt = occurredAt
    }

    /// Detects only a counter increase or a false-to-true explicit firmware notification flag.
    /// The first observation is always a baseline and never produces an alert.
    static func detect(
        device: MinerDevice,
        previous: MinerInfo?,
        current: MinerInfo,
        occurredAt: Date
    ) -> MinerBlockFoundEvent? {
        let previousObservation = previous.map(MinerBlockFoundObservation.init)
        let currentObservation = MinerBlockFoundObservation(info: current)
        return detect(
            device: device,
            previous: previousObservation,
            current: currentObservation,
            currentInfo: current,
            occurredAt: occurredAt
        )
    }

    static func detect(
        device: MinerDevice,
        previous: MinerBlockFoundObservation?,
        current: MinerBlockFoundObservation,
        currentInfo: MinerInfo,
        occurredAt: Date
    ) -> MinerBlockFoundEvent? {
        guard let previous else { return nil }

        // The firmware's blockFound counter resets to 0 on every reboot and then re-climbs.
        // A miner that was power-cycled or reflashed will therefore report the counter rising
        // even though no block was solved. Detect a reboot via an uptime decrease and, in that
        // case, refuse to treat a counter increase as evidence. This alone removes the phantom
        // blocks seen after restarts while still honoring genuine firmware block claims.
        let rebooted: Bool
        if let oldUp = previous.uptimeSeconds, let newUp = current.uptimeSeconds {
            rebooted = newUp < oldUp
        } else {
            rebooted = false
        }

        let counterIncreased = if let old = previous.count, let new = current.count { new > old } else { false }
        let flagRaised = current.showNewBlock && !previous.showNewBlock

        // Fire on the explicit firmware flag, or on a counter increase that did not coincide with
        // a reboot. The firmware only increments blockFound when it believes it solved a block, so
        // a reboot-guarded increment is the trustworthy signal; requiring an additional
        // best-share-versus-network-target proof would silently drop real blocks whenever the
        // firmware omits those fields.
        guard flagRaised || (counterIncreased && !rebooted) else { return nil }

        let pools = ConfiguredMiningPool.resolve(info: currentInfo)
        let selected =
            pools.first(where: { $0.isActive == true })
            ?? pools.first(where: { $0.role.localizedCaseInsensitiveContains("primary") })
            ?? pools.first
        return MinerBlockFoundEvent(
            deviceID: device.id,
            minerName: device.name,
            coinLabel: selected?.coin?.rawValue.uppercased(),
            height: current.height,
            count: current.count,
            occurredAt: occurredAt
        )
    }
}

/// Persisted connectivity and metric baseline used to detect state changes across app launches
/// and background refreshes, mirroring the block-found and best-share baselines. The first
/// observation is always a baseline and never alerts.
struct MinerFleetStateObservation: Codable, Equatable, Sendable {
    var isOnline: Bool
    var hashrate: Double?
    var power: Double?
    var observedAt: Date

    init(info: MinerInfo, isOnline: Bool, observedAt: Date) {
        self.isOnline = isOnline
        self.hashrate = (info.raw["hashRate"] ?? info.raw["hashrate"])?.doubleValue
        self.power = info.raw["power"]?.doubleValue
        self.observedAt = observedAt
    }

    init(isOnline: Bool, hashrate: Double?, power: Double?, observedAt: Date) {
        self.isOnline = isOnline
        self.hashrate = hashrate
        self.power = power
        self.observedAt = observedAt
    }
}

/// A miner connectivity transition: dropped offline or came back online. Fires once per
/// transition; a repeated failed poll while already offline never re-alerts.
struct MinerStateChangeEvent: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case offline
        case backOnline

        var title: String {
            switch self {
            case .offline: "went offline"
            case .backOnline: "is back online"
            }
        }
    }

    let id: UUID
    let deviceID: UUID
    let minerName: String
    let kind: Kind
    let detail: String?
    let occurredAt: Date

    init(
        id: UUID = UUID(),
        deviceID: UUID,
        minerName: String,
        kind: Kind,
        detail: String? = nil,
        occurredAt: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.minerName = minerName
        self.kind = kind
        self.detail = detail
        self.occurredAt = occurredAt
    }
}

/// A significant dashboard metric change (hashrate, power, efficiency) that moves outside the
/// expected range relative to the miner's own previous reading. Temperature is excluded; it has
/// its own per-miner threshold policy in FleetTemperatureAlertPreferences.
struct MinerMetricAlertEvent: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case hashrateStopped
        case hashrateDrop
        case powerSpike
        case efficiencyDrop
    }

    let id: UUID
    let deviceID: UUID
    let minerName: String
    let kind: Kind
    let title: String
    let detail: String
    let occurredAt: Date

    init(
        id: UUID = UUID(),
        deviceID: UUID,
        minerName: String,
        kind: Kind,
        title: String,
        detail: String,
        occurredAt: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.minerName = minerName
        self.kind = kind
        self.title = title
        self.detail = detail
        self.occurredAt = occurredAt
    }
}

/// Relative-change thresholds for metric alerts. Only movements of this size or larger are
/// worth a notification; noise from normal hashrate fluctuation stays silent.
enum FleetMetricAlertThresholds {
    static let hashrateDropFraction = 0.30
    static let powerSpikeFraction = 0.25
    static let efficiencyDropFraction = 0.30
}

extension MinerMetricAlertEvent {
    /// Compares the current reading with the miner's own baseline. A hashrate stop outranks a
    /// partial drop, and efficiency only alerts when both readings reported hashrate and power
    /// so a firmware omission never fabricates a degraded-efficiency claim.
    static func detect(
        device: MinerDevice,
        previous: MinerFleetStateObservation,
        current: MinerInfo,
        occurredAt: Date
    ) -> MinerMetricAlertEvent? {
        let currentHashrate = FleetFormat.sensor(current, keys: "hashRate", "hashrate")
        let currentPower = FleetFormat.sensor(current, keys: "power")

        if let before = previous.hashrate, before.isFinite, before > 0, let now = currentHashrate {
            if now == 0 {
                return MinerMetricAlertEvent(
                    deviceID: device.id, minerName: device.name, kind: .hashrateStopped,
                    title: "\(device.name) hashrate stopped",
                    detail: "Hashrate dropped from \(FleetFormat.hashrateWithUnit(before)) to zero while the miner is still reachable.",
                    occurredAt: occurredAt)
            }
            if now < before * (1 - FleetMetricAlertThresholds.hashrateDropFraction) {
                return MinerMetricAlertEvent(
                    deviceID: device.id, minerName: device.name, kind: .hashrateDrop,
                    title: "\(device.name) hashrate dropped",
                    detail: "Hashrate fell from \(FleetFormat.hashrateWithUnit(before)) to \(FleetFormat.hashrateWithUnit(now)).",
                    occurredAt: occurredAt)
            }
        }
        if let before = previous.power, before.isFinite, before > 0, let now = currentPower, now > 0,
            now > before * (1 + FleetMetricAlertThresholds.powerSpikeFraction) {
            return MinerMetricAlertEvent(
                deviceID: device.id, minerName: device.name, kind: .powerSpike,
                title: "\(device.name) power draw spiked",
                detail: "Power rose from \(Self.format(before, unit: "W")) to \(Self.format(now, unit: "W")).",
                occurredAt: occurredAt)
        }
        // Efficiency in J/TH: watts per GH/s scaled. Higher is worse.
        if let beforeHash = previous.hashrate, beforeHash.isFinite, beforeHash > 0,
            let beforePower = previous.power, beforePower.isFinite, beforePower > 0,
            let nowHash = currentHashrate, nowHash > 0,
            let nowPower = currentPower, nowPower > 0 {
            let beforeEfficiency = beforePower / beforeHash
            let nowEfficiency = nowPower / nowHash
            if beforeEfficiency.isFinite, nowEfficiency.isFinite,
                nowEfficiency > beforeEfficiency * (1 + FleetMetricAlertThresholds.efficiencyDropFraction) {
                return MinerMetricAlertEvent(
                    deviceID: device.id, minerName: device.name, kind: .efficiencyDrop,
                    title: "\(device.name) efficiency dropped",
                    detail: "Efficiency worsened from \(Self.format(beforeEfficiency * 1_000, unit: "J/TH")) to \(Self.format(nowEfficiency * 1_000, unit: "J/TH")).",
                    occurredAt: occurredAt)
            }
        }
        return nil
    }

    private static func format(_ value: Double, unit: String) -> String {
        guard value.isFinite, value >= 0 else { return "Not reported" }
        let text = value.formatted(
            .number.precision(.fractionLength(0...1))
                .grouping(.never).locale(Locale(identifier: "en_US_POSIX"))
        )
        return "\(text) \(unit)"
    }
}
