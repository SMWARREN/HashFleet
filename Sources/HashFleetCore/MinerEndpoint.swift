import Foundation

/// The audited firmware operations, not an arbitrary URL/path escape hatch.
public enum MinerEndpoint: Hashable, Sendable, Identifiable, CaseIterable {
    case info, asic, statistics, dashboardStatistics, scoreboard, wifiScan, logs
    case identify, restart, pause, resume, dismissBlockFound, settings, boot
    case updatePool(Int), deletePool(Int)
    case otaFirmware, otaWWW, theme, updateTheme
    case logWebSocket, liveWebSocket, recovery, options

    /// Pool operations use slot zero as a catalog template. Requests accept slots 0...7.
    public static let catalog: [MinerEndpoint] = [
        .info, .asic, .statistics, .dashboardStatistics, .scoreboard, .wifiScan, .logs,
        .identify, .restart, .pause, .resume, .dismissBlockFound, .settings, .boot,
        .updatePool(0), .deletePool(0), .otaFirmware, .otaWWW, .theme, .updateTheme,
        .logWebSocket, .liveWebSocket, .recovery, .options
    ]
    public static var allCases: [MinerEndpoint] { catalog }
    public var id: String { "\(method) \(path)" }

    public var path: String {
        switch self {
        case .info, .options: "/api/system/info"
        case .asic: "/api/system/asic"
        case .statistics: "/api/system/statistics"
        case .dashboardStatistics: "/api/system/statistics/dashboard"
        case .scoreboard: "/api/system/scoreboard"
        case .wifiScan: "/api/system/wifi/scan"
        case .logs: "/api/system/logs"
        case .identify: "/api/system/identify"
        case .restart: "/api/system/restart"
        case .pause: "/api/system/pause"
        case .resume: "/api/system/resume"
        case .dismissBlockFound: "/api/system/blockFound/dismiss"
        case .settings: "/api/system"
        case .boot: "/api/system/boot"
        case .updatePool(let index), .deletePool(let index): "/api/system/pools/\(index)"
        case .otaFirmware: "/api/system/OTA"
        case .otaWWW: "/api/system/OTAWWW"
        case .theme, .updateTheme: "/api/theme"
        case .logWebSocket: "/api/ws"
        case .liveWebSocket: "/api/ws/live"
        case .recovery: "/recovery"
        }
    }

    public var method: String {
        switch self {
        case .settings: "PATCH"
        case .updatePool: "PUT"
        case .deletePool: "DELETE"
        case .options: "OPTIONS"
        case .identify, .restart, .pause, .resume, .dismissBlockFound, .boot,
            .otaFirmware, .otaWWW, .updateTheme:
            "POST"
        default: "GET"
        }
    }

    public var title: String {
        switch self {
        case .info: "System info"
        case .asic: "ASIC configuration"
        case .statistics: "Statistics history"
        case .dashboardStatistics: "Dashboard statistics (legacy firmware only)"
        case .scoreboard: "Best-share scoreboard"
        case .wifiScan: "Scan Wi-Fi networks"
        case .logs: "Buffered logs"
        case .identify: "Identify device"
        case .restart: "Restart device"
        case .pause: "Pause mining"
        case .resume: "Resume mining"
        case .dismissBlockFound: "Dismiss block-found alert"
        case .settings: "Update settings"
        case .boot: "Select boot partition"
        case .updatePool(let index): "Update pool slot \(index)"
        case .deletePool(let index): "Delete pool slot \(index)"
        case .otaFirmware: "Upload firmware"
        case .otaWWW: "Upload web interface"
        case .theme: "Read theme"
        case .updateTheme: "Update theme"
        case .logWebSocket: "Live logs (WebSocket)"
        case .liveWebSocket: "Live telemetry (WebSocket)"
        case .recovery: "Recovery page"
        case .options: "API preflight capabilities"
        }
    }

    public var isWebSocket: Bool { self == .logWebSocket || self == .liveWebSocket }
    /// Referenced by legacy documentation, but absent from the audited master registrations.
    public var isLegacy: Bool { self == .dashboardStatistics }
    /// Conservative: every mutation requires caller confirmation, even identify/theme changes.
    public var isDestructive: Bool { method != "GET" && method != "OPTIONS" }
    public var isBinaryUpload: Bool { self == .otaFirmware || self == .otaWWW }
    public var contentType: String? {
        if isBinaryUpload { return "application/octet-stream" }
        return isDestructive && method != "DELETE" ? "application/json" : nil
    }
    public var timeout: TimeInterval {
        if isBinaryUpload { return 300 }
        if self == .wifiScan { return 30 }
        return 15
    }

    func validate() throws {
        switch self {
        case .updatePool(let index), .deletePool(let index):
            guard (0...7).contains(index) else { throw MinerAPIError.invalidPoolIndex(index) }
        default: break
        }
    }
}
