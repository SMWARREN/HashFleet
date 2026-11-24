import Foundation

/// Harlo OS local API (published endpoint list: http://MINER_IP/api/...). Request bodies follow the
/// web UI embedded in the official Harlo OS 0.2.101 firmware image.
public enum HarloOSError: LocalizedError, Equatable {
    case rejected(String)
    public var errorDescription: String? {
        switch self { case .rejected(let text): text }
    }
}

public struct HarloOSClient: Sendable {
    public let adapter: MinerFirmwareAdapter

    public init(adapter: MinerFirmwareAdapter) {
        self.adapter = adapter
    }

    // MARK: Generic

    public func get(_ path: String) async throws -> [String: JSONValue] {
        let data = try await adapter.sendCustomHTTPData(method: "GET", path: path, body: nil, query: [])
        guard case .object(let dict) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            throw MinerAPIError.unrecognizedInfo
        }
        return dict
    }

    @discardableResult
    public func send(_ method: String, _ path: String, _ body: [String: JSONValue]? = nil) async throws -> [String: JSONValue] {
        let encoded = try body.map { try JSONEncoder().encode(JSONValue.object($0)) }
        let data = try await adapter.sendCustomHTTPData(
            method: method, path: path, body: encoded, query: [],
            contentType: encoded == nil ? nil : "application/json"
        )
        let reply = (try? JSONDecoder().decode(JSONValue.self, from: data))?.objectValue ?? [:]
        if case .bool(false)? = reply["ok"] {
            throw HarloOSError.rejected(reply["output"]?.stringValue ?? "The miner rejected the request.")
        }
        return reply
    }

    // MARK: Updates

    public func updates() async throws -> [String: JSONValue] { try await get("/api/updates") }
    public func checkForUpdate() async throws { try await send("POST", "/api/updates/check") }
    public func installUpdate() async throws { try await send("POST", "/api/updates/install") }
    public func setUpdateIgnored(version: String, ignored: Bool) async throws {
        try await send("PUT", "/api/updates/ignore", ["version": .string(version), "ignored": .bool(ignored)])
    }

    // MARK: Time

    public func time() async throws -> [String: JSONValue] { try await get("/api/time") }
    public func setTime(server: String, timezone: String) async throws {
        let server = server.trimmingCharacters(in: .whitespaces)
        guard !server.isEmpty, !timezone.isEmpty else { throw HarloOSError.rejected("Enter an NTP server and timezone.") }
        try await send("PUT", "/api/time", ["server": .string(server), "timezone": .string(timezone)])
    }
    public func syncTime() async throws { try await send("POST", "/api/time/sync") }

    // MARK: Miner name

    public func minerName() async throws -> String { try await get("/api/miner-name")["name"]?.stringValue ?? "" }
    public func setMinerName(_ name: String) async throws {
        guard name.count <= 63 else { throw HarloOSError.rejected("Names are limited to 63 characters.") }
        try await send("PUT", "/api/miner-name", ["name": .string(name)])
    }

    // MARK: Schedules (slots 1-8)

    public enum ScheduleAction: Sendable, Equatable {
        case start, stop, reboot
        case tuning(frequencyMHz: Int, coreMV: Int)
        case fanPercent(channel: Int, percent: Int)
        case fanAuto(channel: Int, sensor: String, targetC: Int)
        case display(on: Bool)

        var request: (method: String, path: String, body: [String: JSONValue]) {
            switch self {
            case .start: ("POST", "/api/asic/start", [:])
            case .stop: ("POST", "/api/asic/stop", [:])
            case .reboot: ("POST", "/api/reboot", [:])
            case let .tuning(f, mv):
                ("PUT", "/api/tuning", ["frequency_mhz": .integer(Int64(f)), "core_mv": .integer(Int64(mv))])
            case let .fanPercent(ch, pct): ("PUT", "/api/fans/\(ch)", ["percent": .integer(Int64(pct))])
            case let .fanAuto(ch, sensor, target):
                ("PUT", "/api/fans/\(ch)", ["mode": .string("auto"), "sensor": .string(sensor), "target_c": .integer(Int64(target))])
            case .display(let on): ("PUT", "/api/display/mode", ["mode": .string(on ? "dashboard" : "off")])
            }
        }
    }

    /// Validated schedule body. `days` are 0 (Sun) to 6 (Sat); `time` is "HH:MM".
    public static func scheduleBody(enabled: Bool, days: [Int], time: String, action: ScheduleAction) throws -> [String: JSONValue] {
        let days = Array(Set(days)).sorted()
        guard !days.isEmpty, days.allSatisfy({ (0...6).contains($0) }) else {
            throw HarloOSError.rejected("Choose at least one day.")
        }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
            throw HarloOSError.rejected("Use a 24-hour time such as 21:00.")
        }
        switch action {
        case .fanPercent(_, let pct) where !(20...100).contains(pct):
            throw HarloOSError.rejected("Fan speed must be 20-100%.")
        case .fanAuto(_, _, let t) where !(30...70).contains(t):
            throw HarloOSError.rejected("Target temperature must be 30-70 °C.")
        default: break
        }
        let req = action.request
        return [
            "enabled": .bool(enabled),
            "days": .array(days.map { .integer(Int64($0)) }),
            "time": .string(String(format: "%02d:%02d", parts[0], parts[1])),
            "method": .string(req.method),
            "path": .string(req.path),
            "body": .object(req.body),
        ]
    }

    public func schedules() async throws -> [[String: JSONValue]] {
        (try await get("/api/schedules")["schedules"]?.arrayValue ?? []).compactMap(\.objectValue)
    }
    public func saveSchedule(slot: Int, body: [String: JSONValue]) async throws {
        guard (1...8).contains(slot) else { throw HarloOSError.rejected("Schedule slot must be 1-8.") }
        try await send("PUT", "/api/schedules/\(slot)", body)
    }
    public func deleteSchedule(slot: Int) async throws {
        guard (1...8).contains(slot) else { throw HarloOSError.rejected("Schedule slot must be 1-8.") }
        try await send("DELETE", "/api/schedules/\(slot)")
    }

    // MARK: Lighting

    public static let lightEffects = ["Off", "Static custom", "Red", "Green", "Blue", "Yellow", "Cyan", "Magenta",
                                      "White", "Rainbow flow", "Breathing", "Flashing", "Marquee"]

    public func lighting() async throws -> [String: JSONValue] { try await get("/api/lighting") }
    public func setZone(_ zone: Int, on: Bool, colorHex: String, brightness: Int, effect: Int) async throws {
        let hex = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { throw HarloOSError.rejected("Use a 6-digit hex color.") }
        guard (0...100).contains(brightness) else { throw HarloOSError.rejected("Brightness must be 0-100%.") }
        guard Self.lightEffects.indices.contains(effect) else { throw HarloOSError.rejected("Unknown effect.") }
        try await send("PUT", "/api/argb/\(zone)", [
            "on": .bool(on), "color": .string(hex), "brightness": .integer(Int64(brightness)), "effect": .integer(Int64(effect)),
        ])
    }
    public func setAutomaticLighting(_ enabled: Bool) async throws {
        try await send("PUT", "/api/lighting/rules", ["enabled": .bool(enabled)])
    }
    public func testLighting(event: String) async throws {
        try await send("POST", "/api/lighting/test", ["event": .string(event)])
    }

    // MARK: Discord alerts

    public func discord() async throws -> [String: JSONValue] { try await get("/api/discord") }
    /// Saves alert options, keeping the current rules. A nil webhook keeps the saved one.
    public func saveDiscord(current: [String: JSONValue], enabled: Bool, webhookURL: String?, cooldownSeconds: Int) async throws {
        var body: [String: JSONValue] = [
            "enabled": .bool(enabled),
            "include_best_share_all_time": current["include_best_share_all_time"] ?? .bool(false),
            "include_best_share_session": current["include_best_share_session"] ?? .bool(false),
            "include_block_mined": current["include_block_mined"] ?? .bool(true),
            "cooldown_seconds": .integer(Int64(max(0, cooldownSeconds))),
            "rules": current["rules"] ?? .array([]),
        ]
        if let url = webhookURL?.trimmingCharacters(in: .whitespaces), !url.isEmpty {
            guard url.count <= 255, url.hasPrefix("https://") else { throw HarloOSError.rejected("Enter an https webhook URL.") }
            body["webhook_url"] = .string(url)
        }
        try await send("PUT", "/api/discord", body)
    }
    public func testDiscord() async throws { try await send("POST", "/api/discord/test", [:]) }

    // MARK: Matter power plug

    public func matter() async throws -> [String: JSONValue] { try await get("/api/matter") }
    public func pairPlug(setupCode: String, address: String) async throws {
        let code = setupCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { throw HarloOSError.rejected("Enter the Matter setup code.") }
        try await send("POST", "/api/matter/pair", ["address": .string(address), "setup_code": .string(code)])
    }
    public func unpairPlug() async throws { try await send("DELETE", "/api/matter") }
    public func forgetPlug() async throws { try await send("POST", "/api/matter/forget", ["confirm": .bool(true)]) }

    // MARK: Network, fleet, logs, reset

    public func network() async throws -> [String: JSONValue] { try await get("/api/network") }

    /// Nearby SSIDs from `GET /api/wifi/scan` (`{"networks":[{"ssid","rssi"}]}`), de-duplicated.
    public func wifiNetworks() async throws -> [String] {
        let data = try await adapter.sendCustomHTTPData(method: "GET", path: "/api/wifi/scan", body: nil, query: [], timeout: 30)
        let list = (try JSONDecoder().decode(JSONValue.self, from: data)).objectValue?["networks"]?.arrayValue ?? []
        var seen = Set<String>()
        return list.compactMap { $0.objectValue?["ssid"]?.stringValue }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public func connectWiFi(ssid: String, password: String) async throws {
        guard !ssid.isEmpty, ssid.count <= 32 else { throw HarloOSError.rejected("Enter a network name (1-32 characters).") }
        guard password.count <= 64 else { throw HarloOSError.rejected("Wi-Fi passwords are at most 64 characters.") }
        try await send("POST", "/api/wifi/connect", ["ssid": .string(ssid), "password": .string(password)])
    }
    public func fleet() async throws -> [String: JSONValue] { try await get("/api/fleet") }
    public func scanFleet() async throws { try await send("POST", "/api/fleet/scan", [:]) }
    public func setWebLogging(_ running: Bool) async throws {
        try await send("POST", running ? "/api/logs/resume" : "/api/logs/pause")
    }
    public func factoryReset() async throws { try await send("POST", "/api/factory-reset", ["confirm": .bool(true)]) }
}
