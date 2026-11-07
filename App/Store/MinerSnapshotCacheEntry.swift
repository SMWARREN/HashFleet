import Foundation
import HashFleetCore

/// Private, bounded last-known settings. Explicit allowlists prevent future firmware secrets
/// from being persisted by accident. Cached data never establishes connectivity or write authority.
struct MinerSnapshotCacheEntry: Codable {
    let observedAt: Date
    let fields: [String: JSONValue]

    static let scalarKeys: Set<String> = [
        "hostname", "ASICModel", "asicModel", "boardVersion", "version", "axeOSVersion",
        "hashRate", "hashrate", "power", "temp", "vrTemp", "fanspeed", "fanSpeed",
        "frequency", "coreVoltage", "coreVoltageActual", "autofanspeed", "manualFanSpeed",
        "minFanSpeed", "temptarget", "statsFrequency", "rotation", "invertscreen", "displayTimeout",
        "display", "overheat_mode", "overclockEnabled", "miningPaused", "uptimeSeconds",
        "sharesAccepted", "sharesRejected", "errorPercentage", "bestDiff", "bestSessionDiff", "blockHeight",
        "primaryPoolIndex", "secondaryPoolIndex", "activePoolIndex", "isUsingFallbackStratum",
        "poolRotationEnabled", "stratumPort", "fallbackStratumPort", "stratumProtocol", "fallbackStratumProtocol"
    ]
    static let poolKeys: Set<String> = [
        "id", "port", "stratumPort", "stratumProtocol", "enabled", "priority", "stratumTLS"
    ]

    init(info: MinerInfo, observedAt: Date) {
        self.observedAt = observedAt
        var safe = Self.scalars(info.raw, keys: Self.scalarKeys)
        for key in ["stratumURL", "fallbackStratumURL", "poolURL"] {
            if let value = Self.safeServer(info.raw[key]?.stringValue) { safe[key] = .string(value) }
        }
        if let pools = info.raw["pools"]?.arrayValue {
            safe["pools"] = .array(
                pools.prefix(8).compactMap { pool in
                    guard let raw = pool.objectValue else { return nil }
                    var result = Self.scalars(raw, keys: Self.poolKeys)
                    for key in ["stratumURL", "url"] {
                        if let server = Self.safeServer(raw[key]?.stringValue) { result[key] = .string(server) }
                    }
                    return .object(result)
                }
            )
        }
        fields = safe
    }

    var restored: MinerSnapshot {
        let clean = Self(info: MinerInfo(raw: fields), observedAt: observedAt)
        return MinerSnapshot(
            info: MinerInfo(raw: clean.fields),
            error: "Offline · showing cached settings. Reconnect to verify.",
            updatedAt: observedAt,
            isCached: true
        )
    }

    private static func scalars(_ raw: [String: JSONValue], keys: Set<String>) -> [String: JSONValue] {
        raw.filter { key, value in
            guard keys.contains(key) else { return false }
            switch value {
            case .string(let text): return text.utf8.count <= 256
            case .number(let number): return number.isFinite
            case .integer, .bool: return true
            default: return false
            }
        }
    }

    private static func safeServer(_ text: String?) -> String? {
        guard let text, text.utf8.count <= 2048 else { return nil }
        let value = text.contains("://") ? text : "stratum+tcp://" + text
        guard let url = URLComponents(string: value), let host = url.host, !host.isEmpty else { return nil }
        let bracketed = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return bracketed + (url.port.map { ":\($0)" } ?? "")
    }
}
