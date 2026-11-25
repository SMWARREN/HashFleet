import Foundation

/// Per-firmware write and control capability flags ported from MinerWatch's `MinerDriver`
/// base class plus AxeForge (`/api/settings`, `/api/restart`, `/api/identify`, `/api/pools`).
public struct MinerDriverCapabilities: Equatable, Hashable, Sendable {
    public let family: String
    public let canSetFan: Bool
    public let canSetFrequency: Bool
    public let canSetVoltage: Bool
    public let canSetWorkmode: Bool
    public let canRestart: Bool
    public let canPause: Bool
    public let canShutdown: Bool
    public let canSetPool: Bool
    public let canIdentify: Bool
    public let fanMinPct: Int

    public init(
        family: String,
        canSetFan: Bool = false,
        canSetFrequency: Bool = false,
        canSetVoltage: Bool = false,
        canSetWorkmode: Bool = false,
        canRestart: Bool = false,
        canPause: Bool = false,
        canShutdown: Bool = false,
        canSetPool: Bool = false,
        canIdentify: Bool = false,
        fanMinPct: Int = 0
    ) {
        self.family = family
        self.canSetFan = canSetFan
        self.canSetFrequency = canSetFrequency
        self.canSetVoltage = canSetVoltage
        self.canSetWorkmode = canSetWorkmode
        self.canRestart = canRestart
        self.canPause = canPause
        self.canShutdown = canShutdown
        self.canSetPool = canSetPool
        self.canIdentify = canIdentify
        self.fanMinPct = fanMinPct
    }

    public var isReadOnly: Bool {
        !canSetFan && !canSetFrequency && !canSetVoltage && !canSetWorkmode
            && !canRestart && !canPause && !canShutdown && !canSetPool && !canIdentify
    }

    public static func forFamily(_ rawFamily: String?, info: MinerInfo? = nil) -> MinerDriverCapabilities {
        let normalized = (rawFamily ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let special = specializedCapabilities(for: normalized, info: info) {
            return special
        }
        return standardCapabilities(for: normalized)
    }

    private static func specializedCapabilities(for normalized: String, info: MinerInfo?) -> MinerDriverCapabilities? {
        switch normalized {
        case "canaan":
            // A10 Universal API documents `led` and `hashpower`; the stock Nano 3s ascset table
            // (Canaan-Creative/Avalon_Nano3s driver-avalon.c device_cmds[]) has neither.
            let model = [info?.raw["deviceModel"], info?.raw["ASICModel"]]
                .compactMap { $0?.stringValue?.lowercased() }.joined(separator: " ")
            let isNano = model.contains("nano")
            return MinerDriverCapabilities(
                family: "canaan",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canSetWorkmode: true,
                canRestart: true,
                canShutdown: !isNano,
                canIdentify: !isNano,
                fanMinPct: 15
            )
        case "canaannano3":
            return MinerDriverCapabilities(
                family: "canaannano3",
                canSetWorkmode: true,
                canRestart: true
            )
        case "bitforge":
            let supportsPause = info == nil || info?.raw["miningPaused"] != nil
            return MinerDriverCapabilities(
                family: "bitforge",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canPause: supportsPause,
                canShutdown: false,
                canSetPool: true,
                canIdentify: true
            )
        default:
            return nil
        }
    }

    private static func standardCapabilities(for normalized: String) -> MinerDriverCapabilities {
        switch normalized {
        case "nerdqaxe", "nerdoctaxe":
            return MinerDriverCapabilities(
                family: "nerdqaxe",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canPause: false,
                canShutdown: true,
                canSetPool: true,
                canIdentify: true
            )
        case "nmaxe":
            return MinerDriverCapabilities(
                family: "nmaxe",
                canSetFan: true,
                canRestart: true
            )
        case "axeforge":
            return MinerDriverCapabilities(
                family: "axeForge",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canSetPool: true,
                canIdentify: true,
                fanMinPct: 20
            )
        case "harloos":
            return MinerDriverCapabilities(
                family: "harloOS",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canPause: true,
                canShutdown: true,
                canSetPool: true,
                fanMinPct: 20
            )
        case "thoros":
            // Core voltage uses unverified board-specific units on ThorOS, so it stays read-only.
            return MinerDriverCapabilities(
                family: "thorOS",
                canSetFan: true,
                canSetFrequency: true,
                canRestart: true,
                canSetPool: true,
                fanMinPct: 20
            )
        case "warpaxe":
            return MinerDriverCapabilities(
                family: "warpAxe",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canPause: true,
                canShutdown: true,
                canSetPool: true
            )
        case "braiins", "luxos":
            return MinerDriverCapabilities(family: normalized)
        case "bitfortun":
            return MinerDriverCapabilities(
                family: "bitfortun",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canShutdown: true,
                canSetPool: true
            )
        default:
            return MinerDriverCapabilities(
                family: "bitaxe",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canPause: true,
                canSetPool: true,
                canIdentify: true
            )
        }
    }
}
