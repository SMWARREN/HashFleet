import Foundation

/// Extra per-firmware settings that are verified in each firmware's upstream source.
///
/// Every entry cites the handler that accepts the key. Keys are sent through the
/// normal `.settings` endpoint, so the family's own write path (PATCH `/api/system`,
/// or AxeForge POST `/api/settings`) is used unchanged.
public struct MinerFirmwareExtra: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// Boolean switch. `sendsBool` sends a JSON bool instead of 0/1 (NerdQAxe uses `is<bool>()`).
        case toggle(sendsBool: Bool)
        /// Integer value inside a verified range.
        case number(range: ClosedRange<Int>, unit: String)
        /// One of fixed integer options.
        case choice([(value: Int, label: String)])

        public static func == (lhs: Kind, rhs: Kind) -> Bool {
            switch (lhs, rhs) {
            case let (.toggle(a), .toggle(b)): a == b
            case let (.number(r1, u1), .number(r2, u2)): r1 == r2 && u1 == u2
            case let (.choice(a), .choice(b)): a.map(\.value) == b.map(\.value) && a.map(\.label) == b.map(\.label)
            default: false
            }
        }
    }

    public let key: String
    public let title: String
    public let detail: String
    public let kind: Kind
    /// Where the current value is reported, if different from `key`.
    public let readKey: String
    /// Extra fields that must accompany the write (AxeForge overclock confirmation).
    public let extraFields: [String: JSONValue]
    /// Hardware-risky changes keep a confirmation even in Essentials.
    public let alwaysConfirm: Bool

    public var id: String { key }

    public init(
        key: String, title: String, detail: String, kind: Kind,
        readKey: String? = nil, extraFields: [String: JSONValue] = [:], alwaysConfirm: Bool = false
    ) {
        self.key = key
        self.title = title
        self.detail = detail
        self.kind = kind
        self.readKey = readKey ?? key
        self.extraFields = extraFields
        self.alwaysConfirm = alwaysConfirm
    }

    /// The settings body for a new value, or nil when the value is invalid.
    public func payload(_ value: Int) -> [String: JSONValue]? {
        var out = extraFields
        switch kind {
        case .toggle(let sendsBool):
            guard value == 0 || value == 1 else { return nil }
            out[key] = sendsBool ? .bool(value == 1) : .integer(Int64(value))
        case .number(let range, _):
            guard range.contains(value) else { return nil }
            out[key] = .integer(Int64(value))
        case .choice(let options):
            guard options.contains(where: { $0.value == value }) else { return nil }
            out[key] = .integer(Int64(value))
        }
        return out
    }

    /// Reads the current value from a raw info/settings document.
    public func currentValue(in raw: [String: JSONValue]) -> Int? {
        var node: JSONValue? = nil
        var dict = raw
        let parts = readKey.split(separator: ".").map(String.init)
        for (index, part) in parts.enumerated() {
            guard let value = dict[part] else { return nil }
            if index == parts.count - 1 { node = value } else if case .object(let next) = value { dict = next } else { return nil }
        }
        switch node {
        case .bool(let b): return b ? 1 : 0
        case .integer(let i): return Int(i)
        case .unsignedInteger(let u): return Int(u)
        case .number(let d): return Int(d.rounded())
        default: return nil
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
            // pidTargetTemp/overheat_temp; the ranges below are app-side safety bounds (WarpAxe's
            // validated ranges), not firmware limits.
            return [
                MinerFirmwareExtra(
                    key: "pidTargetTemp", title: "Fan target temperature",
                    detail: "The automatic fan PID holds the chips at this temperature.",
                    kind: .number(range: 35...85, unit: "°C")
                ),
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
            // dvb-WarpAxe api.rs validation ranges: pidTargetTemp 35..85, overheat_temp 50..90.
            return [
                MinerFirmwareExtra(
                    key: "pidTargetTemp", title: "Fan target temperature",
                    detail: "The automatic fan PID holds the chips at this temperature.",
                    kind: .number(range: 35...85, unit: "°C")
                ),
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
                    kind: .toggle(sendsBool: true)
                ),
                MinerFirmwareExtra(
                    key: "tgoal", title: "Tuning goal",
                    detail: "What auto-tune optimises for. Changing it starts a new search.",
                    kind: .choice([(0, "Hashrate"), (1, "Power cap"), (2, "Efficiency")])
                ),
                MinerFirmwareExtra(
                    key: "pcap", title: "Power cap",
                    detail: "Watts limit for the Power cap goal. 0 uses the board limit.",
                    kind: .number(range: 0...2000, unit: "W")
                ),
                MinerFirmwareExtra(
                    key: "overclock", title: "Overclock unlock",
                    detail: "Lets tuning and manual values use the board's envelope instead of stock limits. Adds heat and risk.",
                    kind: .toggle(sendsBool: true), readKey: "overclock.unlocked",
                    extraFields: ["confirm": .string("OVERCLOCK")], alwaysConfirm: true
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

    /// Families whose extras are reported by the settings document (`.asic` endpoint) rather than info.
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
}
