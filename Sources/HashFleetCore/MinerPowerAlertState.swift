import Foundation

/// Groups a single reading's inputs to `MinerPowerAlertState.observe` so the API stays
/// under the parameter-count lint limit while keeping every field explicit at call sites.
public struct MinerPowerAlertObservation: Sendable {
    public var deviceID: UUID
    public var minerName: String
    public var watts: Double?
    public var observedAt: Date?
    public var isOnline: Bool
    public var isCached: Bool
    public var policy: MinerPowerAlertPolicy
    public var now: Date

    public init(
        deviceID: UUID, minerName: String, watts: Double?, observedAt: Date?,
        isOnline: Bool, isCached: Bool, policy: MinerPowerAlertPolicy, now: Date
    ) {
        self.deviceID = deviceID
        self.minerName = minerName
        self.watts = watts
        self.observedAt = observedAt
        self.isOnline = isOnline
        self.isCached = isCached
        self.policy = policy
        self.now = now
    }
}

/// One miner's persisted suppression state. A first fresh high reading alerts immediately.
/// A fresh reading at least `hysteresisWatts` below the threshold resolves the episode and
/// emits a `.resolved` event so the user hears that the alarm cleared. A new high episode must
/// also be at least `cooldown` after the previous alert. Offline, cached, missing, duplicate,
/// out-of-order and invalid readings never alert, resolve, or rearm an episode.
public struct MinerPowerAlertState: Codable, Equatable, Sendable {
    public private(set) var lastObservedAt: Date?
    public private(set) var lastAlertAt: Date?
    public private(set) var isHighEpisodeActive = false

    public init() {}

    /// Editing or disabling a policy permits a new episode, but never bypasses the cooldown.
    public mutating func policyDidChange() {
        isHighEpisodeActive = false
    }

    /// Groups the inputs of a single reading so the observe API stays under the parameter-count
    /// lint limit while keeping every field explicit at call sites.
    public mutating func observe(_ reading: MinerPowerAlertObservation) -> MinerPowerAlertEvent? {
        guard reading.policy.isEnabled, reading.isOnline, !reading.isCached,
            reading.now.timeIntervalSinceReferenceDate.isFinite,
            let observedAt = reading.observedAt, observedAt.timeIntervalSinceReferenceDate.isFinite,
            let watts = reading.watts, watts.isFinite, watts >= 0, watts <= 10_000
        else { return nil }
        let age = reading.now.timeIntervalSince(observedAt)
        guard age >= 0, age <= MinerPowerAlertPolicy.maximumReadingAge,
            lastObservedAt.map({ observedAt > $0 }) ?? true
        else { return nil }
        lastObservedAt = observedAt

        let policy = reading.policy

        if watts <= policy.thresholdWatts - MinerPowerAlertPolicy.hysteresisWatts {
            guard isHighEpisodeActive else { return nil }
            isHighEpisodeActive = false
            return MinerPowerAlertEvent(
                deviceID: reading.deviceID, minerName: reading.minerName, kind: .resolved,
                watts: watts, thresholdWatts: policy.thresholdWatts, occurredAt: observedAt
            )
        }

        guard watts >= policy.thresholdWatts, !isHighEpisodeActive,
            lastAlertAt.map({ reading.now.timeIntervalSince($0) >= MinerPowerAlertPolicy.cooldown }) ?? true
        else { return nil }

        isHighEpisodeActive = true
        lastAlertAt = reading.now
        return MinerPowerAlertEvent(
            deviceID: reading.deviceID, minerName: reading.minerName, kind: .exceeded,
            watts: watts, thresholdWatts: policy.thresholdWatts, occurredAt: observedAt
        )
    }

    private enum CodingKeys: String, CodingKey { case lastObservedAt, lastAlertAt, isHighEpisodeActive }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        lastObservedAt = try values.decodeIfPresent(Date.self, forKey: .lastObservedAt)
        lastAlertAt = try values.decodeIfPresent(Date.self, forKey: .lastAlertAt)
        isHighEpisodeActive = try values.decode(Bool.self, forKey: .isHighEpisodeActive)
        guard lastObservedAt.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true,
            lastAlertAt.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true,
            !isHighEpisodeActive || (lastAlertAt != nil && lastObservedAt != nil)
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid power-alert suppression state"))
        }
    }
}
