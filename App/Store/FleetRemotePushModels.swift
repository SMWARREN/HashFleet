import Foundation
import HashFleetCore

/// Names are local presentation only. Wire DTOs below deliberately do not encode them.
struct FleetRemoteMinerSchedule: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var enabled = true
    var intervalMinutes = 60

    static let intervals = [60, 180, 360, 720, 1_440]
    var intervalTitle: String { Self.title(for: intervalMinutes) }

    static func safeName(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(64)
        let result = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Miner" : result
    }

    static func title(for minutes: Int) -> String {
        switch minutes {
        case 60: "Every hour"
        case 180: "Every 3 hours"
        case 360: "Every 6 hours"
        case 720: "Every 12 hours"
        default: "Every day"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, enabled
        case intervalMinutes = "interval_minutes"
    }

    init(id: String, name: String, enabled: Bool = true, intervalMinutes: Int = 60) {
        self.id = id
        self.name = Self.safeName(name)
        self.enabled = enabled
        self.intervalMinutes = intervalMinutes
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = Self.safeName(try values.decodeIfPresent(String.self, forKey: .name) ?? "Miner")
        enabled = try values.decode(Bool.self, forKey: .enabled)
        intervalMinutes = try values.decode(Int.self, forKey: .intervalMinutes)
        guard UUID(uuidString: id) != nil, id == id.lowercased(), Self.intervals.contains(intervalMinutes) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: values, debugDescription: "Invalid schedule.")
        }
    }
}

struct FleetRemotePushSettings: Codable, Equatable, Sendable {
    var enabled = false
    var miners: [FleetRemoteMinerSchedule] = []

    func merging(_ devices: [MinerDevice]) -> Self {
        let previous = Dictionary(miners.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = self
        var seen = Set<UUID>()
        result.miners = devices.filter { $0.kind == .espMiner && seen.insert($0.id).inserted }.prefix(64).map { device in
            let id = device.id.uuidString.lowercased()
            var schedule = previous[id] ?? FleetRemoteMinerSchedule(id: id, name: "")
            schedule.name = FleetRemoteMinerSchedule.safeName(device.name)
            return schedule
        }
        return result
    }

    var wirePreferences: FleetRemotePushPreferences {
        FleetRemotePushPreferences(enabled: enabled, miners: miners.map {
            .init(id: $0.id, enabled: $0.enabled, intervalMinutes: $0.intervalMinutes)
        })
    }
}

/// Scheduling-only cloud schema. Local names, addresses and metrics have no fields here.
struct FleetRemotePushPreferences: Encodable, Equatable, Sendable {
    struct Miner: Encodable, Equatable, Sendable {
        var id: String
        var enabled: Bool
        var intervalMinutes: Int

        enum CodingKeys: String, CodingKey {
            case id, enabled
            case intervalMinutes = "interval_minutes"
        }
    }
    var enabled: Bool
    var miners: [Miner]
}

struct FleetRemotePushRegistration: Encodable, Sendable {
    struct Miner: Encodable, Sendable { let id: String }
    let mode = "device_check_v1"
    let deviceToken: String
    let environment: String
    let miners: [Miner]

    enum CodingKeys: String, CodingKey {
        case mode, environment, miners
        case deviceToken = "device_token"
    }
}

struct FleetRemotePushReply: Decodable, Sendable {
    var ok: Bool
    var mode: String?
    var settings: FleetRemotePushSettings?
    var providerReady: Bool?
    enum CodingKeys: String, CodingKey {
        case ok, mode, settings
        case providerReady = "provider_ready"
    }
}
