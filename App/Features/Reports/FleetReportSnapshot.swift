import Foundation

/// An immutable, privacy-minimized capture. No device identifiers, names, addresses, raw payloads,
/// pool details, wallets, errors or credentials can enter either export through this DTO.
struct FleetReportSnapshot: Equatable, Sendable {
    let capturedAt: Date
    let isDemo: Bool
    let miners: [Miner]

    struct Miner: Identifiable, Equatable, Sendable {
        let id: Int
        let connection: Connection
        let freshness: Freshness
        let observedAt: Date?
        let hashrateGHs: Double?
        let powerWatts: Double?
        let temperatureCelsius: Double?
        let fanRPM: Double?
        let uptimeSeconds: Double?

        var label: String { "Miner \(id)" }
        var isCurrent: Bool { connection == .online && freshness == .fresh }
    }

    enum Connection: String, Sendable {
        case online = "Online at last response"
        case offline = "Offline at last check"
        case unknown = "Connection unconfirmed"
    }

    enum Freshness: String, Sendable {
        case fresh = "Fresh at capture"
        case stale = "Stale at capture"
        case cached = "Cached, not live"
        case unknown = "Observation time unknown"
        case clockSkew = "Future timestamp, not trusted"

        static func classify(observedAt: Date?, capturedAt: Date, isCached: Bool, staleAfter: TimeInterval = 120) -> Self {
            if isCached { return .cached }
            guard let observedAt else { return .unknown }
            let age = capturedAt.timeIntervalSince(observedAt)
            guard age.isFinite else { return .unknown }
            if age < -60 { return .clockSkew }
            return age > staleAfter ? .stale : .fresh
        }
    }

    struct Total: Equatable, Sendable {
        let value: Double?
        let reporting: Int
        let eligible: Int

        var coverage: String { "\(reporting) of \(eligible) fresh online miners" }
    }

    var onlineCount: Int { miners.filter { $0.connection == .online }.count }
    var offlineCount: Int { miners.filter { $0.connection == .offline }.count }
    var unconfirmedCount: Int { miners.count - onlineCount - offlineCount }
    var currentCount: Int { miners.filter(\.isCurrent).count }
    var nonFreshCount: Int { miners.filter { $0.freshness != .fresh }.count }
    var hashrate: Total { total(\.hashrateGHs) }
    var power: Total { total(\.powerWatts) }

    private func total(_ keyPath: KeyPath<Miner, Double?>) -> Total {
        let eligible = miners.filter(\.isCurrent)
        let values = eligible.compactMap { Self.usable($0[keyPath: keyPath]) }
        let sum = values.reduce(0, +)
        return Total(value: values.isEmpty || !sum.isFinite ? nil : sum, reporting: values.count, eligible: eligible.count)
    }

    static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Power has a separate observation clock because partial updates retain previously read watts.
    /// Unlike the general row freshness's clock-skew tolerance, future power is never current.
    static func isFreshPowerObservation(observedAt: Date?, capturedAt: Date) -> Bool {
        guard let observedAt else { return false }
        let age = capturedAt.timeIntervalSince(observedAt)
        return age.isFinite && age >= 0 && age <= 120
    }

    static func number(_ value: Double?) -> String {
        guard let value = usable(value) else { return "Not reported" }
        // Locale-independent and round-trip-safe for CSV. Human-readable previews add units.
        return String(value)
    }

    static func formattedHashrate(_ value: Double?) -> String {
        guard let value = usable(value) else { return "Not reported" }
        return FleetFormat.hashrateWithUnit(value)
    }

    static func timestamp(_ date: Date?) -> String {
        guard let date, date.timeIntervalSince1970.isFinite else { return "Unknown" }
        return date.ISO8601Format()
    }

    static let scopeNote = "On-demand snapshot, not a daily report. No history, energy consumption or electricity costs are inferred."
    static let privacyNote = "Anonymous miner labels. Names, IP addresses, hostnames, wallets, pool details and credentials are excluded."
    static let freshnessNote = "Fresh means observed within 120 seconds of capture. "
        + "Connection status is from the last check, not a new connection test. "
        + "Cached, stale, offline and unconfirmed readings are excluded from subtotals. "
        + "Power uses its own observation time: missing, future or over-120-second observations "
        + "are omitted as Not reported."
}
