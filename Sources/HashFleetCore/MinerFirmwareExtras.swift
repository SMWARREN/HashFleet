import Foundation

/// Extra per-firmware settings that are verified in each firmware's upstream source
/// (or, for Harlo OS, the web UI shipped inside the official firmware image).
///
/// Keys without a `writePath` are sent through the normal `.settings` endpoint, so the
/// family's own write path (PATCH `/api/system`, AxeForge POST `/api/settings`) is used.
public struct MinerFirmwareExtra: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// Boolean switch. `sendsBool` sends a JSON bool instead of 0/1 (NerdQAxe uses `is<bool>()`).
        case toggle(sendsBool: Bool)
        /// Integer value inside a verified range.
        case number(range: ClosedRange<Int>, unit: String)
        /// One of fixed integer options.
        case choice([(value: Int, label: String)])
        /// One of fixed string options. The editor works with the option index.
        case textChoice([(value: String, label: String)])

        public static func == (lhs: Kind, rhs: Kind) -> Bool {
            switch (lhs, rhs) {
            case let (.toggle(a), .toggle(b)): a == b
            case let (.number(r1, u1), .number(r2, u2)): r1 == r2 && u1 == u2
            case let (.choice(a), .choice(b)): a.map(\.value) == b.map(\.value) && a.map(\.label) == b.map(\.label)
            case let (.textChoice(a), .textChoice(b)): a.map(\.value) == b.map(\.value) && a.map(\.label) == b.map(\.label)
            default: false
            }
        }
    }

    public let key: String
    public let title: String
    public let detail: String
    public let kind: Kind
    /// Dotted path of the current value inside the read document.
    public let readKey: String
    /// Extra fixed fields that must accompany the write (AxeForge overclock confirmation).
    public let extraFields: [String: JSONValue]
    /// Fields copied from the read document into every write (Harlo protections need all four).
    public let companionKeys: [String]
    /// Hardware-risky changes keep a confirmation even in Essentials.
    public let alwaysConfirm: Bool
    /// GET path for the current value. Nil reads the live info document.
    public let readPath: String?
    /// Dedicated write route. Nil sends through `.settings`.
    public let writeMethod: String?
    public let writePath: String?

    public var id: String { key }

    public init(
        key: String, title: String, detail: String, kind: Kind,
        readKey: String? = nil, extraFields: [String: JSONValue] = [:], companionKeys: [String] = [],
        alwaysConfirm: Bool = false, readPath: String? = nil, writeMethod: String? = nil, writePath: String? = nil
    ) {
        self.key = key
        self.title = title
        self.detail = detail
        self.kind = kind
        self.readKey = readKey ?? key
        self.extraFields = extraFields
        self.companionKeys = companionKeys
        self.alwaysConfirm = alwaysConfirm
        self.readPath = readPath
        self.writeMethod = writeMethod
        self.writePath = writePath
    }

    /// The write body for a new value, or nil when the value is invalid.
    /// `document` supplies companion fields (and must contain them when any are required).
    public func payload(_ value: Int, document: [String: JSONValue] = [:]) -> [String: JSONValue]? {
        var out = extraFields
        for companion in companionKeys {
            guard let current = document[companion] else { return nil }
            out[companion] = current
        }
        let outKey = key
        switch kind {
        case .toggle(let sendsBool):
            guard value == 0 || value == 1 else { return nil }
            out[outKey] = sendsBool ? .bool(value == 1) : .integer(Int64(value))
        case .number(let range, _):
            guard range.contains(value) else { return nil }
            out[outKey] = .integer(Int64(value))
        case .choice(let options):
            guard options.contains(where: { $0.value == value }) else { return nil }
            out[outKey] = .integer(Int64(value))
        case .textChoice(let options):
            guard options.indices.contains(value) else { return nil }
            out[outKey] = .string(options[value].value)
        }
        guard Self.protectionsAreOrdered(out) else { return nil }
        return out
    }

    /// Reads the current value from a raw document.
    public func currentValue(in raw: [String: JSONValue]) -> Int? {
        var node: JSONValue?
        var dict = raw
        let parts = readKey.split(separator: ".").map(String.init)
        for (index, part) in parts.enumerated() {
            guard let value = dict[part] else { return nil }
            if index == parts.count - 1 { node = value } else if case .object(let next) = value { dict = next } else { return nil }
        }
        if case .textChoice(let options) = kind {
            guard case .string(let text)? = node else { return nil }
            return options.firstIndex { $0.value.caseInsensitiveCompare(text) == .orderedSame }
        }
        switch node {
        case .bool(let b): return b ? 1 : 0
        case .integer(let i): return Int(i)
        case .unsignedInteger(let u): return Int(u)
        case .number(let d): return Int(d.rounded())
        default: return nil
        }
    }

    /// Harlo requires each full-fan threshold to stay below its shutdown threshold.
    static func protectionsAreOrdered(_ body: [String: JSONValue]) -> Bool {
        func int(_ key: String) -> Int? {
            switch body[key] {
            case .integer(let i)?: Int(i)
            case .number(let d)?: Int(d)
            default: nil
            }
        }
        if let fan = int("asic_fan_c"), let off = int("asic_shutdown_c"), fan >= off { return false }
        if let fan = int("vr_fan_c"), let off = int("vr_shutdown_c"), fan >= off { return false }
        return true
    }
}

/// One-tap firmware action with a verified route.
public struct MinerFirmwareAction: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let method: String
    public let path: String
    /// Key in the live document whose value is sent as `{"id": value}` (Harlo fault acknowledge).
    public let idFromKey: String?
    /// Only shown while this live key is truthy.
    public let visibleWhenKey: String?
    public let headers: [String: String]

    public init(
        id: String, title: String, detail: String, method: String = "POST", path: String,
        idFromKey: String? = nil, visibleWhenKey: String? = nil, headers: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.method = method
        self.path = path
        self.idFromKey = idFromKey
        self.visibleWhenKey = visibleWhenKey
        self.headers = headers
    }

    public func isVisible(in raw: [String: JSONValue]) -> Bool {
        guard let visibleWhenKey else { return true }
        switch raw[visibleWhenKey] {
        case .bool(let b)?: return b
        case .integer(let i)?: return i != 0
        case .number(let d)?: return d != 0
        default: return false
        }
    }
}

public enum MinerFirmwareExtras {
    /// Verified extras for a firmware family (case-insensitive). Empty when none are verified.
    public static func controls(for family: String) -> [MinerFirmwareExtra] {
        switch family.lowercased() {
        case "bitaxe":
            // ESP-Miner main/nvs_config.c: overclockEnabled (oc_enabled, BOOL 0..1), useNTP (usentp, BOOL 0..1).
            return [
                MinerFirmwareExtra(
                    key: "overclockEnabled", title: "Overclock limits",
                    detail: "Allows frequency and core voltage above the board's stock limits. Higher values add heat and can damage the board.",
                    kind: .toggle(sendsBool: false), alwaysConfirm: true
                ),
                MinerFirmwareExtra(
                    key: "useNTP", title: "Network time (NTP)",
                    detail: "Sync the miner clock from an NTP server.",
                    kind: .toggle(sendsBool: false)
                ),
            ]
        case "nerdqaxe", "nerdoctaxe", "bitfortun":
            // nq_handler_system.cpp:504-531 / bf_handler_system.cpp:366-398. Upstream takes any u16 for
            // overheat_temp; the range below is an app-side safety bound (WarpAxe's validated range),
            // not a firmware limit. The PID fan target is on the shared Cooling page.
            return [
                MinerFirmwareExtra(
                    key: "overheat_temp", title: "Overheat shutdown",
                    detail: "The miner stops hashing above this chip temperature.",
                    kind: .number(range: 50...90, unit: "°C"), alwaysConfirm: true
                ),
                MinerFirmwareExtra(
                    key: "flipscreen", title: "Flip screen",
                    detail: "Rotate the built-in display 180°.",
                    kind: .toggle(sendsBool: true)
                ),
                MinerFirmwareExtra(
                    key: "autoscreenoff", title: "Auto screen off",
                    detail: "Turn the display off automatically.",
                    kind: .toggle(sendsBool: true)
                ),
            ]
        case "warpaxe":
            // dvb-WarpAxe api.rs validation range: overheat_temp 50..90. The fan target is on the
            // shared Cooling page (sent as temptarget, translated to pidTargetTemp).
            return [
                MinerFirmwareExtra(
                    key: "overheat_temp", title: "Overheat shutdown",
                    detail: "The miner stops hashing above this chip temperature.",
                    kind: .number(range: 50...90, unit: "°C"), alwaysConfirm: true
                ),
            ]
        case "axeforge":
            // AxeForge main/net/web.cpp settings_post: atune, tgoal 0..2, pcap 0..2000, overclock + confirm.
            return [
                MinerFirmwareExtra(
                    key: "atune", title: "Auto-tune",
                    detail: "Let the firmware search for the best stable clock and voltage.",
                    kind: .toggle(sendsBool: true), readPath: "settings"
                ),
                MinerFirmwareExtra(
                    key: "tgoal", title: "Tuning goal",
                    detail: "What auto-tune optimises for. Changing it starts a new search.",
                    kind: .choice([(0, "Hashrate"), (1, "Power cap"), (2, "Efficiency")]), readPath: "settings"
                ),
                MinerFirmwareExtra(
                    key: "pcap", title: "Power cap",
                    detail: "Watts limit for the Power cap goal. 0 uses the board limit.",
                    kind: .number(range: 0...2000, unit: "W"), readPath: "settings"
                ),
                MinerFirmwareExtra(
                    key: "overclock", title: "Overclock unlock",
                    detail: "Lets tuning and manual values use the board's envelope instead of stock limits. Adds heat and risk.",
                    kind: .toggle(sendsBool: true), readKey: "overclock.unlocked",
                    extraFields: ["confirm": .string("OVERCLOCK")], alwaysConfirm: true, readPath: "settings"
                ),
            ]
        case "harloos":
            return harloControls
        default:
            return []
        }
    }

    /// Harlo OS 0.2.101: request bodies are taken from the web UI embedded in the official
    /// factory image (dashboard.js). Protections must be sent as all four thresholds together,
    /// each full-fan value below its shutdown value (ASIC max 90 °C, VR max 95 °C).
    private static let harloProtectionKeys = ["asic_fan_c", "asic_shutdown_c", "vr_fan_c", "vr_shutdown_c"]

    private static var harloControls: [MinerFirmwareExtra] {
        func protection(_ key: String, _ title: String, _ detail: String, _ range: ClosedRange<Int>) -> MinerFirmwareExtra {
            MinerFirmwareExtra(
                key: key, title: title, detail: detail, kind: .number(range: range, unit: "°C"),
                companionKeys: harloProtectionKeys.filter { $0 != key }, alwaysConfirm: true,
                readPath: "/api/protections", writeMethod: "PUT", writePath: "/api/protections"
            )
        }
        return [
            protection("asic_fan_c", "ASIC full-fan temperature", "Fans go to 100% when the ASIC reaches this temperature.", 30...89),
            protection("asic_shutdown_c", "ASIC emergency shutdown", "Mining stops when the ASIC reaches this temperature.", 31...90),
            protection("vr_fan_c", "VR full-fan temperature", "Fans go to 100% when the voltage regulator reaches this temperature.", 30...94),
            protection("vr_shutdown_c", "VR emergency shutdown", "Mining stops when the voltage regulator reaches this temperature.", 31...95),
            MinerFirmwareExtra(
                key: "rating_w", title: "Power supply rating",
                detail: "The PSU wattage the miner compares its draw against.",
                kind: .number(range: 1...2000, unit: "W"), readKey: "power_supply_rating_w",
                writeMethod: "PUT", writePath: "/api/power-supply"
            ),
            MinerFirmwareExtra(
                key: "mode", title: "Display mode",
                detail: "Live dashboard, a local-time clock, or screen off.",
                kind: .textChoice([("dashboard", "Dashboard"), ("clock", "Clock"), ("off", "Off")]),
                companionKeys: ["rotation"], readPath: "/api/display", writeMethod: "PUT", writePath: "/api/display"
            ),
            MinerFirmwareExtra(
                key: "unit", title: "Temperature unit",
                detail: "Unit shown on the miner's own screen and web page.",
                kind: .textChoice([("C", "°C"), ("F", "°F")]), readKey: "temperature_unit",
                writeMethod: "PUT", writePath: "/api/temperature-unit"
            ),
            MinerFirmwareExtra(
                key: "enabled", title: "Data collection",
                detail: "Share anonymous mining statistics with Harlo Labs.",
                kind: .toggle(sendsBool: true), readPath: "/api/collection",
                writeMethod: "PUT", writePath: "/api/collection"
            ),
        ]
    }

    /// Verified one-tap actions for a family.
    public static func actions(for family: String) -> [MinerFirmwareAction] {
        switch family.lowercased() {
        case "axeforge":
            return [MinerFirmwareAction(
                id: "retune", title: "Restart auto-tune",
                detail: "Turns auto-tune on and starts a new search. A full search takes 1-2 hours.",
                path: "/api/retune", headers: ["X-AxeForge": "1"]
            )]
        case "harloos":
            return [
                MinerFirmwareAction(
                    id: "faultAck", title: "Dismiss fault notice",
                    detail: "Clears the fault notice on the miner. It does not restart mining or disable protections.",
                    path: "/api/alerts/acknowledge", idFromKey: "fault_notice_id", visibleWhenKey: "fault_notice_pending"
                ),
                MinerFirmwareAction(
                    id: "updateCheck", title: "Check for firmware update",
                    detail: "Asks the miner to check Harlo's update server. Nothing is installed.",
                    path: "/api/updates/check"
                ),
            ]
        default:
            return []
        }
    }

    /// Families with a verified "restart auto-tune" action (AxeForge POST /api/retune).
    public static func supportsRetune(_ family: String) -> Bool {
        family.lowercased() == "axeforge"
    }

    /// AxeForge extras are reported by its settings document (`.asic` endpoint) rather than info.
    public static func readsFromSettingsDocument(_ family: String) -> Bool {
        family.lowercased() == "axeforge"
    }
}

extension MinerFirmwareAdapter {
    /// AxeForge: re-enables auto-tune and restarts the search (`POST /api/retune`, web.cpp:855).
    public func retune() async throws -> Bool {
        guard resolvedFamilyName == "axeforge" else { return false }
        return try await sendCustomHTTP(
            method: "POST", path: "/api/retune", json: nil, headers: ["X-AxeForge": "1"]
        )
    }

    /// Reads the document an extra's current value lives in.
    public func readExtraDocument(_ extra: MinerFirmwareExtra) async throws -> [String: JSONValue] {
        let data: Data
        switch extra.readPath {
        case nil:
            return try await info().raw
        case "settings":
            data = try await execute(.asic)
        case let path?:
            data = try await sendCustomHTTPData(method: "GET", path: path, body: nil, query: [])
        }
        guard case .object(let dict) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            throw MinerAPIError.unrecognizedInfo
        }
        return dict
    }

    /// Writes one extra. Dedicated routes are sent as-is; others go through `.settings`.
    public func writeExtra(_ extra: MinerFirmwareExtra, payload: [String: JSONValue]) async throws {
        let body = try JSONEncoder().encode(JSONValue.object(payload))
        if let path = extra.writePath {
            _ = try await sendCustomHTTPData(
                method: extra.writeMethod ?? "PUT", path: path, body: body, query: [], contentType: "application/json"
            )
        } else {
            _ = try await execute(.settings, body: body)
        }
    }

    /// Runs a verified firmware action. `live` supplies the id for acknowledge-style actions.
    public func runFirmwareAction(_ action: MinerFirmwareAction, live: [String: JSONValue]) async throws {
        var body: Data?
        if let key = action.idFromKey {
            guard let id = live[key] else { throw MinerAPIError.unrecognizedInfo }
            body = try JSONEncoder().encode(JSONValue.object(["id": id]))
        }
        _ = try await sendCustomHTTPData(
            method: action.method, path: action.path, body: body, query: [],
            contentType: body == nil ? nil : "application/json", headers: action.headers
        )
    }
}
