import Foundation

/// WatchConnectivity message and application-context keys shared by iOS and watchOS.
public enum WatchRelayKeys {
    public static let cgminerRequest = "app.hashfleet.watch-cgminer-request.v1"
    public static let cgminerResponse = "app.hashfleet.watch-cgminer-response.v1"
    public static let cachedReadings = "app.hashfleet.watch-cached-readings.v1"
}

/// Request sent from the Watch to the paired iPhone to query a cgminer TCP endpoint
/// (blocked on real watchOS hardware per Apple TN3135).
public struct WatchMinerRelayRequest: Codable, Equatable, Sendable {
    public let minerID: UUID
    public let host: String
    public let port: Int

    public init(minerID: UUID, host: String, port: Int = 4028) {
        self.minerID = minerID
        self.host = host
        self.port = port
    }

    /// Validates that `host` and `port` form a safe local endpoint.
    public func validatedEndpoint() -> (host: String, port: Int)? {
        guard let endpoint = try? WatchEndpoint.normalize("\(host):\(port)") else { return nil }
        return (endpoint.host, endpoint.port ?? 4028)
    }
}

/// Response returned by the paired iPhone for a cgminer relay request.
public struct WatchMinerRelayResponse: Codable, Equatable, Sendable {
    public let reading: WatchMinerReading?
    public let error: String?

    public init(reading: WatchMinerReading? = nil, error: String? = nil) {
        self.reading = reading
        self.error = error
    }
}

/// Snapshot of recent miner readings pushed from iPhone to Watch via `applicationContext`
/// so TCP-only miners remain visible even when the iPhone app is not actively reachable.
public struct WatchCachedReadingsTransfer: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let sentAt: Date
    public let readings: [WatchMinerReading]

    public init(readings: [WatchMinerReading], sentAt: Date = Date()) {
        self.version = Self.currentVersion
        self.sentAt = sentAt
        self.readings = readings
    }
}
