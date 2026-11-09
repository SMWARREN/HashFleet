import Foundation

/// A read-only, cross-platform view of the latest miner observation.
///
/// This is intentionally independent of SwiftUI so the iOS/iPadOS app, Mac companion,
/// widgets, and terminal client can share the same vocabulary without sharing presentation.
public struct MinerStatusSnapshot: Codable, Hashable, Sendable {
    public let device: MinerDevice
    public let observedAt: Date
    public let info: MinerInfo?
    public let error: String?

    public init(device: MinerDevice, observedAt: Date = Date(), info: MinerInfo? = nil, error: String? = nil) {
        self.device = device
        self.observedAt = observedAt
        self.info = info
        self.error = error
    }

    public var isOnline: Bool { info != nil && error == nil }
    public var deviceID: UUID { device.id }
    public var name: String { device.name }
    public var address: String { device.address }
    public var kind: MinerDevice.Kind { device.kind }
    /// Nil means the miner omitted or invalidated the metric. A present zero remains a real zero.
    public var hashrate: Double? {
        guard isOnline else { return nil }
        return Self.usableMetric(info?.raw["hashRate"])
            ?? Self.usableMetric(info?.raw["hashrate"])
    }
    public var power: Double? {
        guard isOnline else { return nil }
        return Self.usableMetric(info?.raw["power"])
    }
    public var temperature: Double? { temperatureCelsius }
    public var online: Bool { isOnline }
    public var hashrateGHs: Double { hashrate ?? 0 }
    public var temperatureCelsius: Double? {
        guard isOnline else { return nil }
        return Self.usableMetric(info?.raw["temp"])
    }
    public var powerWatts: Double? { power }
    public var uptimeSeconds: Int? {
        guard isOnline else { return nil }
        guard let uptime = info?.raw["uptimeSeconds"]?.intValue, uptime >= 0 else { return nil }
        return uptime
    }
    public var asicModel: String? { info?.asicModel.isEmpty == false ? info?.asicModel : nil }
    public var firmware: String? {
        guard let info, !info.version.isEmpty || !info.axeOSVersion.isEmpty else { return nil }
        return info.version.isEmpty ? info.axeOSVersion : info.version
    }

    private static func usableMetric(_ raw: JSONValue?) -> Double? {
        guard let value = raw?.doubleValue, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// A fleet-level read-only status response shared by all HashFleet clients.
public struct FleetStatusSnapshot: Codable, Hashable, Sendable {
    public let observedAt: Date
    public let miners: [MinerStatusSnapshot]

    public init(observedAt: Date = Date(), miners: [MinerStatusSnapshot]) {
        self.observedAt = observedAt
        self.miners = miners
    }

    public var onlineCount: Int { miners.count(where: \.isOnline) }
    public var offlineCount: Int { miners.count - onlineCount }
    public var totalHashrateGHs: Double { miners.reduce(0) { $0 + $1.hashrateGHs } }
}
