import Foundation

/// Groups a single reading's inputs to `MinerTemperatureAlertState.observe` so the API stays
/// under the parameter-count lint limit while keeping every field explicit at call sites.
public struct MinerTemperatureAlertObservation: Sendable {
    public var deviceID: UUID
    public var minerName: String
    public var temperatureCelsius: Double?
    public var observedAt: Date?
    public var isOnline: Bool
    public var isCached: Bool
    public var policy: MinerTemperatureAlertPolicy
    public var now: Date

    public init(
        deviceID: UUID, minerName: String, temperatureCelsius: Double?, observedAt: Date?,
        isOnline: Bool, isCached: Bool, policy: MinerTemperatureAlertPolicy, now: Date
    ) {
        self.deviceID = deviceID
        self.minerName = minerName
        self.temperatureCelsius = temperatureCelsius
        self.observedAt = observedAt
        self.isOnline = isOnline
        self.isCached = isCached
        self.policy = policy
        self.now = now
    }
}

/// One miner's persisted suppression state. A first fresh hot observation alerts immediately.
/// There is only one alert per hot episode: a fresh reading at least 5 °C below the threshold
/// rearms it, and a new hot observation must also be at least 30 minutes after the previous alert.
/// Offline, cached, missing, duplicate, out-of-order and invalid readings never rearm an episode.
public struct MinerTemperatureAlertState: Codable, Equatable, Sendable {
    public private(set) var lastObservedAt: Date?
    public private(set) var lastAlertAt: Date?
    public private(set) var isHotEpisodeActive = false

    public init() {}

    /// Editing or disabling a policy permits a new episode, but never bypasses the cooldown.
    public mutating func policyDidChange() {
        isHotEpisodeActive = false
    }

    /// Groups the inputs of a single reading so the observe API stays under the parameter-count
    /// lint limit while keeping every field explicit at call sites.
    public mutating func observe(_ reading: MinerTemperatureAlertObservation) -> MinerTemperatureAlertEvent? {
        guard reading.policy.isEnabled, reading.isOnline, !reading.isCached,
            reading.now.timeIntervalSinceReferenceDate.isFinite,
            let observedAt = reading.observedAt, observedAt.timeIntervalSinceReferenceDate.isFinite,
            let temperatureCelsius = reading.temperatureCelsius, temperatureCelsius.isFinite,
            temperatureCelsius > 0, temperatureCelsius <= 150
        else { return nil }
        let age = reading.now.timeIntervalSince(observedAt)
        guard age >= 0, age <= MinerTemperatureAlertPolicy.maximumReadingAge,
            lastObservedAt.map({ observedAt > $0 }) ?? true
        else { return nil }
        lastObservedAt = observedAt

        let policy = reading.policy
        if temperatureCelsius <= policy.thresholdCelsius - MinerTemperatureAlertPolicy.hysteresisCelsius {
            isHotEpisodeActive = false
            return nil
        }
        guard temperatureCelsius >= policy.thresholdCelsius, !isHotEpisodeActive,
            lastAlertAt.map({ reading.now.timeIntervalSince($0) >= MinerTemperatureAlertPolicy.cooldown }) ?? true
        else { return nil }

        isHotEpisodeActive = true
        lastAlertAt = reading.now
        return MinerTemperatureAlertEvent(
            deviceID: reading.deviceID, minerName: reading.minerName, temperatureCelsius: temperatureCelsius,
            thresholdCelsius: policy.thresholdCelsius, occurredAt: observedAt
        )
    }

    private enum CodingKeys: String, CodingKey { case lastObservedAt, lastAlertAt, isHotEpisodeActive }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        lastObservedAt = try values.decodeIfPresent(Date.self, forKey: .lastObservedAt)
        lastAlertAt = try values.decodeIfPresent(Date.self, forKey: .lastAlertAt)
        isHotEpisodeActive = try values.decode(Bool.self, forKey: .isHotEpisodeActive)
        guard lastObservedAt.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true,
            lastAlertAt.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true,
            !isHotEpisodeActive || (lastAlertAt != nil && lastObservedAt != nil)
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid temperature-alert suppression state"))
        }
    }
}
