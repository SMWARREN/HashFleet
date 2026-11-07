import Foundation

/// One successful read of a miner. Every metric is optional: a missing or invalid value is `nil`, never zero.
public struct WatchMinerReading: Codable, Equatable, Sendable {
    /// Readings older than this many seconds are no longer current.
    public static let freshnessInterval: TimeInterval = 60
    /// Allowance for the UI clock sampling slightly before the fetch timestamp.
    static let clockSkewTolerance: TimeInterval = 5
    /// Temperatures at or below zero are "no sensor" sentinels, and anything above this is bad data.
    static let maximumTemperatureC = 200.0

    public let minerID: UUID
    /// When the Watch actually read the miner. Preserved across failures and relaunch.
    public let observedAt: Date
    public let hashrateGHs: Double?
    public let powerWatts: Double?
    public let chipTemperatureC: Double?
    public let vrTemperatureC: Double?
    public let uptimeSeconds: Double?
    public let acceptedShares: Int?
    public let rejectedShares: Int?
    public let isMiningPaused: Bool?

    /// Values that are not finite or are negative are stored as `nil`.
    public init(
        minerID: UUID,
        observedAt: Date,
        hashrateGHs: Double? = nil,
        powerWatts: Double? = nil,
        chipTemperatureC: Double? = nil,
        vrTemperatureC: Double? = nil,
        uptimeSeconds: Double? = nil,
        acceptedShares: Int? = nil,
        rejectedShares: Int? = nil,
        isMiningPaused: Bool? = nil
    ) {
        self.minerID = minerID
        self.observedAt = observedAt
        self.hashrateGHs = Self.metric(hashrateGHs)
        self.powerWatts = Self.metric(powerWatts)
        self.chipTemperatureC = Self.temperature(chipTemperatureC)
        self.vrTemperatureC = Self.temperature(vrTemperatureC)
        self.uptimeSeconds = Self.metric(uptimeSeconds)
        self.acceptedShares = acceptedShares.flatMap { $0 >= 0 ? $0 : nil }
        self.rejectedShares = rejectedShares.flatMap { $0 >= 0 ? $0 : nil }
        self.isMiningPaused = isMiningPaused
    }

    private enum CodingKeys: String, CodingKey {
        case minerID, observedAt, hashrateGHs, powerWatts, chipTemperatureC, vrTemperatureC
        case uptimeSeconds, acceptedShares, rejectedShares, isMiningPaused
    }

    /// Lenient about individual metrics (a damaged field becomes `nil`) but strict about identity and time.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            minerID: try c.decode(UUID.self, forKey: .minerID),
            observedAt: try c.decode(Date.self, forKey: .observedAt),
            hashrateGHs: (try? c.decodeIfPresent(Double.self, forKey: .hashrateGHs)) ?? nil,
            powerWatts: (try? c.decodeIfPresent(Double.self, forKey: .powerWatts)) ?? nil,
            chipTemperatureC: (try? c.decodeIfPresent(Double.self, forKey: .chipTemperatureC)) ?? nil,
            vrTemperatureC: (try? c.decodeIfPresent(Double.self, forKey: .vrTemperatureC)) ?? nil,
            uptimeSeconds: (try? c.decodeIfPresent(Double.self, forKey: .uptimeSeconds)) ?? nil,
            acceptedShares: (try? c.decodeIfPresent(Int.self, forKey: .acceptedShares)) ?? nil,
            rejectedShares: (try? c.decodeIfPresent(Int.self, forKey: .rejectedShares)) ?? nil,
            isMiningPaused: (try? c.decodeIfPresent(Bool.self, forKey: .isMiningPaused)) ?? nil
        )
    }

    /// True when the reading is older than 60 seconds (exactly 60 is still current), or its time is invalid
    /// or in the future beyond a small clock-skew allowance.
    public func isStale(at date: Date) -> Bool {
        let age = date.timeIntervalSince(observedAt)
        guard age.isFinite else { return true }
        if age < -Self.clockSkewTolerance { return true }
        return age > Self.freshnessInterval
    }

    static func temperature(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value <= maximumTemperatureC else { return nil }
        return value
    }

    private static func metric(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
