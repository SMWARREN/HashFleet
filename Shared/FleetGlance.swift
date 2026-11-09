import Foundation
import HashFleetCore

/// Only aggregate readings cross into the widget extension. No device identifiers or secrets.
struct FleetGlance: Codable, Hashable, Sendable {
    var updatedAt: Date
    var onlineCount: Int
    var minerCount: Int
    var hashrateGHs: Double
    var powerWatts: Double
    var isDemo: Bool

    static let empty = FleetGlance(
        updatedAt: .distantPast,
        onlineCount: 0,
        minerCount: 0,
        hashrateGHs: 0,
        powerWatts: 0,
        isDemo: false
    )
    static let freshnessInterval: TimeInterval = 60

    func isStale(at date: Date) -> Bool {
        let age = date.timeIntervalSince(updatedAt)
        let drift = updatedAt.timeIntervalSince(date)
        return !isValid
            || minerCount == 0
            || age >= Self.freshnessInterval
            || drift > 5
    }

    var isValid: Bool {
        onlineCount >= 0 && minerCount >= 0 && onlineCount <= minerCount &&
        hashrateGHs.isFinite && hashrateGHs >= 0 && powerWatts.isFinite && powerWatts >= 0 &&
        updatedAt.timeIntervalSince1970.isFinite
    }
}

/// UserDefaults is thread-safe. The payload is stored atomically as one encoded value.
struct FleetGlanceStorage: @unchecked Sendable {
    static let appGroup = "group.app.hashfleet.shared"
    static let key = "app.hashfleet.glance.v1"
    static let shared: FleetGlanceStorage = {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil else {
            return FleetGlanceStorage(defaults: nil)
        }
        return FleetGlanceStorage(defaults: UserDefaults(suiteName: appGroup))
    }()

    private let defaults: UserDefaults?
    init(defaults: UserDefaults?) { self.defaults = defaults }
    var isAvailable: Bool { defaults != nil }

    func load() -> FleetGlance {
        guard let data = defaults?.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(FleetGlance.self, from: data), value.isValid else { return .empty }
        return value
    }

    @discardableResult func save(_ value: FleetGlance) -> Bool {
        guard value.isValid, let defaults, let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    func clear() { defaults?.removeObject(forKey: Self.key) }
}

/// Aggregate-only snapshot for the native Mac menu-bar companion. This is separate from the
/// widget opt-in cache so disabling widgets does not remove the Mac status display.
struct FleetMenuBarGlanceStorage: @unchecked Sendable {
    static let key = "app.hashfleet.menu-bar-glance.v1"
    static let shared = FleetMenuBarGlanceStorage(
        defaults: UserDefaults(suiteName: FleetGlanceStorage.appGroup)
    )

    private let defaults: UserDefaults?
    init(defaults: UserDefaults?) { self.defaults = defaults }

    func load() -> FleetGlance {
        guard let data = defaults?.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(FleetGlance.self, from: data),
              value.isValid
        else { return .empty }
        return value
    }

    @discardableResult
    func save(_ value: FleetGlance) -> Bool {
        guard value.isValid, let defaults, let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }
}

enum FleetMenuBarMinerStatus: String, Codable, Sendable {
    case connecting
    case reconnecting
    case offline
    case online
}

/// Privacy-bounded row for the native Mac system-menu popover. It intentionally contains only the
/// user's local display label plus fixed, already-formatted readings. Addresses, pool data, raw
/// firmware messages, authentication, wallets, and seeds never cross into this cache.
struct FleetMenuBarMinerSummary: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let status: FleetMenuBarMinerStatus
    let segments: [String]
    let notices: [String]
    let isSimulated: Bool
    /// Current firmware session only. Never substituted with an all-time or cached record.
    var sessionBest: String?
}

/// Only bounded presentation text crosses into the companion, never a raw firmware payload.
struct FleetMenuBarNotificationSummary: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let minerName: String
    let title: String
    let occurredAt: Date
}

struct FleetMenuBarSnapshot: Codable, Equatable, Sendable {
    let glance: FleetGlance
    let miners: [FleetMenuBarMinerSummary]
    /// Nil is a legacy complete aggregate. New publishers explicitly flag unavailable metrics.
    /// FleetGlance's widget wire format remains unchanged.
    var hashrateIsComplete: Bool?
    var powerIsComplete: Bool?
    /// Optional for decoding snapshots published by earlier app versions.
    var notifications: [FleetMenuBarNotificationSummary]?

    var reportedHashrate: Double? { hashrateIsComplete == false ? nil : glance.hashrateGHs }
    var reportedPower: Double? { powerIsComplete == false ? nil : glance.powerWatts }
}

/// Legacy persisted presentation choice, retained for compatibility with older app versions.
/// Current dropdowns always show miners and recent activity, and never consult this filter.
/// This value has never granted permission to post notifications or alter a miner.
enum FleetActivityContentMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case notifications
    case sessionBest
    case both

    var id: String { rawValue }
    var showsNotifications: Bool { self != .sessionBest }
    var showsSessionBest: Bool { self != .notifications }
    var title: String {
        switch self {
        case .notifications: "Notifications"
        case .sessionBest: "Session best"
        case .both: "Both"
        }
    }
}

/// Shared by the actual native menu bar and host-side regressions. Freshness and demo provenance
/// apply to the closed status item, tooltip, header and every row, not just the aggregate title.
enum FleetMenuBarFormat {
    static func compactTitle(_ snapshot: FleetMenuBarSnapshot, now: Date) -> String {
        let glance = snapshot.glance
        let fleet = "\(glance.onlineCount)/\(glance.minerCount)"
        let rate = hashrate(snapshot.reportedHashrate)
        let demo = glance.isDemo ? "DEMO " : ""
        return "\(demo)\(fleet) \(rate)" + (glance.isStale(at: now) ? " !" : "")
    }

    static func compactTitle(_ glance: FleetGlance, now: Date) -> String {
        compactTitle(FleetMenuBarSnapshot(glance: glance, miners: []), now: now)
    }

    static func accessibilityTitle(_ snapshot: FleetMenuBarSnapshot, now: Date) -> String {
        let glance = snapshot.glance
        let demo = glance.isDemo ? ", DEMO sample data" : ""
        guard glance.minerCount > 0 else { return "Hash Fleet\(demo)" }
        let state = glance.isStale(at: now) ? ", data stale" : ""
        return "Hash Fleet\(demo), \(glance.onlineCount) of \(glance.minerCount) online, \(hashrate(snapshot.reportedHashrate))\(state)"
    }

    static func accessibilityTitle(_ glance: FleetGlance, now: Date) -> String {
        accessibilityTitle(FleetMenuBarSnapshot(glance: glance, miners: []), now: now)
    }

    static func hashrate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "Not reported" }
        return FleetFormat.hashrateWithUnit(value)
    }

    static func power(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "Not reported" }
        return FleetFormat.measurement(value, unit: "W", decimals: 1)
    }

    static func rowStatus(_ miner: FleetMenuBarMinerSummary, isStale: Bool) -> String {
        if isStale { return "Stale" }
        if miner.isSimulated { return "Sample" }
        switch miner.status {
        case .connecting: return "Connecting"
        case .reconnecting: return "Refreshing"
        case .offline: return "Offline"
        case .online: return "Live"
        }
    }

    static func rowIsLive(_ miner: FleetMenuBarMinerSummary, isStale: Bool) -> Bool {
        !isStale && !miner.isSimulated && miner.status == .online
    }

    static func sessionBest(_ miner: FleetMenuBarMinerSummary, isStale: Bool) -> String? {
        guard !isStale, miner.status == .online || miner.isSimulated else { return nil }
        return miner.sessionBest
    }
}

struct FleetMenuBarSnapshotStorage: @unchecked Sendable {
    static let key = "app.hashfleet.menu-bar-snapshot.v1"
    static let shared = FleetMenuBarSnapshotStorage(
        defaults: UserDefaults(suiteName: FleetGlanceStorage.appGroup)
    )

    private let defaults: UserDefaults?
    init(defaults: UserDefaults?) { self.defaults = defaults }

    func load() -> FleetMenuBarSnapshot {
        guard let data = defaults?.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(FleetMenuBarSnapshot.self, from: data),
              value.glance.isValid
        else {
            guard let legacyData = defaults?.data(forKey: FleetMenuBarGlanceStorage.key),
                  let legacy = try? JSONDecoder().decode(FleetGlance.self, from: legacyData),
                  legacy.isValid
            else { return FleetMenuBarSnapshot(glance: .empty, miners: []) }
            return FleetMenuBarSnapshot(glance: legacy, miners: [])
        }
        return value
    }

    @discardableResult
    func save(_ value: FleetMenuBarSnapshot) -> Bool {
        guard value.glance.isValid, let defaults, let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }
}

/// User-selected visibility for the Mac status item. The native Mac app stores this preference
/// locally and owns the item itself. The legacy iOS compatibility path keeps its shared domain.
enum FleetMenuBarVisibilityMode: String, Sendable {
    case always
    case hidden

    var shouldShow: Bool { self == .always }
}

/// Launch URL owned by the native Mac companion. The iPad app running on macOS opens this URL
/// when the user enables the menu-bar item, which also recovers from a deliberate companion Quit.
enum FleetMenuBarLaunch {
    static let showURL = URL(string: "hashfleet-menubar://show")!
}

struct FleetMenuBarPreferenceStorage: @unchecked Sendable {
    static let key = "app.hashfleet.menu-bar-visibility.v1"
    static let contentKey = "app.hashfleet.menu-bar-content.v1"
    #if os(macOS)
    static let shared = FleetMenuBarPreferenceStorage(defaults:
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
            ? UserDefaults(suiteName: "app.hashfleet.mac.ui-tests") : .standard)
    #else
    static let shared = FleetMenuBarPreferenceStorage(
        defaults: UserDefaults(suiteName: FleetGlanceStorage.appGroup)
    )
    #endif

    private let defaults: UserDefaults?
    init(defaults: UserDefaults?) { self.defaults = defaults }

    func load() -> FleetMenuBarVisibilityMode {
        guard let rawValue = defaults?.string(forKey: Self.key) else { return .always }
        if rawValue == "whenAppIsOpen" { return .always }
        return FleetMenuBarVisibilityMode(rawValue: rawValue) ?? .always
    }

    @discardableResult
    func save(_ mode: FleetMenuBarVisibilityMode) -> Bool {
        guard let defaults else { return false }
        defaults.set(mode.rawValue, forKey: Self.key)
        return true
    }

    func loadContentMode() -> FleetActivityContentMode {
        defaults?.string(forKey: Self.contentKey)
            .flatMap(FleetActivityContentMode.init(rawValue:)) ?? .notifications
    }

    @discardableResult
    func saveContentMode(_ mode: FleetActivityContentMode) -> Bool {
        guard let defaults else { return false }
        defaults.set(mode.rawValue, forKey: Self.contentKey)
        return true
    }
}
