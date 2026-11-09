import Foundation
import Observation
import SwiftUI
import HashFleetCore

@MainActor
@Observable
final class FleetPreferences {
    enum Appearance: String, CaseIterable, Identifiable, Sendable {
        case system
        case light
        case dark

        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    enum SortOption: String, CaseIterable, Identifiable, Codable, Sendable {
        case name
        case address
        case hashrate
        case power
        case temperature
        case acceptedShares
        case uptime
        case firmware

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name: return "Name"
            case .address: return "Address"
            case .hashrate: return "Hashrate"
            case .power: return "Power"
            case .temperature: return "Temperature"
            case .acceptedShares: return "Accepted Shares"
            case .uptime: return "Uptime"
            case .firmware: return "Firmware"
            }
        }
    }

    typealias Sort = SortOption

    static let defaultSort: SortOption = .name
    static let defaultAscending: Bool = true
    static let defaultCompactCards: Bool = false
    static let defaultRealtimeMonitoring: Bool = true
    static let defaultBlockNotificationsEnabled: Bool = false
    static let defaultBestShareNotificationsEnabled: Bool = true
    static let defaultSessionBestNotificationsEnabled: Bool = true
    static let defaultActivityContentMode: FleetActivityContentMode = .notifications
    static let defaultStateChangeNotificationsEnabled: Bool = false
    static let defaultMetricAlertNotificationsEnabled: Bool = false
    static let defaultPowerAlertNotificationsEnabled: Bool = false
    static let defaultTelemetryStorageEnabled: Bool = true
    static let defaultTelemetryRetention: TelemetryRetention = .month

    enum TelemetryRetention: Int, CaseIterable, Identifiable, Sendable {
        case week = 7
        case month = 30
        case quarter = 90
        case year = 365
        case forever = 36500  // 100 years

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .week: "7 days"
            case .month: "30 days"
            case .quarter: "90 days"
            case .year: "365 days"
            case .forever: "Forever"
            }
        }

        var days: Int { rawValue }
    }

    enum Keys {
        static let appearance = "app.hashfleet.preferences.appearance"
        static let systemAppearanceMigration = "app.hashfleet.preferences.systemAppearanceMigration"
        static let sort = "app.hashfleet.preferences.sort"
        static let ascending = "app.hashfleet.preferences.ascending"
        static let compactCards = "app.hashfleet.preferences.compactCards"
        static let externalData = "app.hashfleet.preferences.externalData"
        static let realtimeMonitoring = "app.hashfleet.preferences.realtimeMonitoring"
        static let blockNotificationsEnabled = "app.hashfleet.preferences.blockNotificationsEnabled"
        static let bestShareNotificationsEnabled = "app.hashfleet.preferences.bestShareNotificationsEnabled"
        static let sessionBestNotificationsEnabled = "app.hashfleet.preferences.sessionBestNotificationsEnabled"
        static let activityContentMode = "app.hashfleet.preferences.activityContentMode"
        static let stateChangeNotificationsEnabled = "app.hashfleet.preferences.stateChangeNotificationsEnabled"
        static let metricAlertNotificationsEnabled = "app.hashfleet.preferences.metricAlertNotificationsEnabled"
        static let powerAlertNotificationsEnabled = "app.hashfleet.preferences.powerAlertNotificationsEnabled"
        static let tourSeen = "app.hashfleet.preferences.tourSeen"
        static let tourSuppressed = "app.hashfleet.preferences.tourSuppressed"
        static let dashboardCoins = "app.hashfleet.preferences.dashboardCoins"
        static let telemetryRetention = "app.hashfleet.preferences.telemetryRetention"
        static let telemetryStorageEnabled = "app.hashfleet.preferences.telemetryStorageEnabled"
    }

    @MainActor
    private struct StoredValues {
        var hasSeenFeatureTour: Bool
        var suppressFeatureTour: Bool
        var dashboardCoins: Set<MiningPoolCoin>?
        var appearance: Appearance
        var sort: SortOption
        var ascending: Bool
        var compactCards: Bool
        var externalDataEnabled: Bool
        var realtimeMonitoring: Bool
        var blockNotificationsEnabled: Bool
        var bestShareNotificationsEnabled: Bool
        var sessionBestNotificationsEnabled: Bool
        var activityContentMode: FleetActivityContentMode
        var stateChangeNotificationsEnabled: Bool
        var metricAlertNotificationsEnabled: Bool
        var powerAlertNotificationsEnabled: Bool
        var telemetryStorageEnabled: Bool
        var telemetryRetention: TelemetryRetention

        init(defaults: UserDefaults) {
            hasSeenFeatureTour = defaults.bool(forKey: Keys.tourSeen)
            suppressFeatureTour = defaults.bool(forKey: Keys.tourSuppressed)
            dashboardCoins = defaults.stringArray(forKey: Keys.dashboardCoins)
                .map { Set($0.compactMap(MiningPoolCoin.init(rawValue:))) }
            appearance = defaults.string(forKey: Keys.appearance)
                .flatMap(Appearance.init(rawValue:)) ?? .system
            sort = defaults.string(forKey: Keys.sort)
                .flatMap(SortOption.init(rawValue:)) ?? FleetPreferences.defaultSort
            ascending = defaults.object(forKey: Keys.ascending) as? Bool ?? FleetPreferences.defaultAscending
            compactCards = defaults.object(forKey: Keys.compactCards) as? Bool
                ?? FleetPreferences.defaultCompactCards
            externalDataEnabled = defaults.object(forKey: Keys.externalData) as? Bool ?? true
            realtimeMonitoring = defaults.object(forKey: Keys.realtimeMonitoring) as? Bool
                ?? FleetPreferences.defaultRealtimeMonitoring
            blockNotificationsEnabled = defaults.object(forKey: Keys.blockNotificationsEnabled) as? Bool
                ?? FleetPreferences.defaultBlockNotificationsEnabled
            bestShareNotificationsEnabled = defaults.object(forKey: Keys.bestShareNotificationsEnabled) as? Bool
                ?? FleetPreferences.defaultBestShareNotificationsEnabled
            sessionBestNotificationsEnabled = defaults.object(forKey: Keys.sessionBestNotificationsEnabled) as? Bool
                ?? FleetPreferences.defaultSessionBestNotificationsEnabled
            activityContentMode = defaults.string(forKey: Keys.activityContentMode)
                .flatMap(FleetActivityContentMode.init(rawValue:)) ?? FleetPreferences.defaultActivityContentMode
            stateChangeNotificationsEnabled = defaults.object(forKey: Keys.stateChangeNotificationsEnabled) as? Bool
                ?? FleetPreferences.defaultStateChangeNotificationsEnabled
            metricAlertNotificationsEnabled = defaults.object(forKey: Keys.metricAlertNotificationsEnabled) as? Bool
                ?? FleetPreferences.defaultMetricAlertNotificationsEnabled
            powerAlertNotificationsEnabled = defaults.object(forKey: Keys.powerAlertNotificationsEnabled) as? Bool
                ?? FleetPreferences.defaultPowerAlertNotificationsEnabled
            telemetryStorageEnabled = defaults.object(forKey: Keys.telemetryStorageEnabled) as? Bool
                ?? FleetPreferences.defaultTelemetryStorageEnabled
            telemetryRetention = (defaults.object(forKey: Keys.telemetryRetention) as? Int)
                .flatMap(TelemetryRetention.init(rawValue:)) ?? FleetPreferences.defaultTelemetryRetention
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    private var storedValues: StoredValues

    var hasSeenFeatureTour: Bool {
        get { storedValues.hasSeenFeatureTour }
        set {
            storedValues.hasSeenFeatureTour = newValue
            defaults.set(newValue, forKey: Keys.tourSeen)
        }
    }

    var suppressFeatureTour: Bool {
        get { storedValues.suppressFeatureTour }
        set {
            storedValues.suppressFeatureTour = newValue
            defaults.set(newValue, forKey: Keys.tourSuppressed)
        }
    }

    var shouldShowFeatureTour: Bool { !hasSeenFeatureTour && !suppressFeatureTour }

    /// nil follows detected coins. An explicit empty set intentionally hides all coin rows.
    var dashboardCoins: Set<MiningPoolCoin>? {
        get { storedValues.dashboardCoins }
        set {
            storedValues.dashboardCoins = newValue
            if let newValue {
                defaults.set(newValue.map(\.rawValue).sorted(), forKey: Keys.dashboardCoins)
            } else {
                defaults.removeObject(forKey: Keys.dashboardCoins)
            }
        }
    }

    /// App-only display preference. Never changes miner settings or monitoring.
    var appearance: Appearance {
        get { storedValues.appearance }
        set {
            storedValues.appearance = newValue
            defaults.set(newValue.rawValue, forKey: Keys.appearance)
        }
    }

    var sort: SortOption {
        get { storedValues.sort }
        set {
            storedValues.sort = newValue
            defaults.set(newValue.rawValue, forKey: Keys.sort)
        }
    }

    var ascending: Bool {
        get { storedValues.ascending }
        set {
            storedValues.ascending = newValue
            defaults.set(newValue, forKey: Keys.ascending)
        }
    }

    var compactCards: Bool {
        get { storedValues.compactCards }
        set {
            storedValues.compactCards = newValue
            defaults.set(newValue, forKey: Keys.compactCards)
        }
    }

    var externalDataEnabled: Bool {
        get { storedValues.externalDataEnabled }
        set {
            storedValues.externalDataEnabled = newValue
            defaults.set(newValue, forKey: Keys.externalData)
        }
    }

    /// Keeps read-only WebSocket monitoring active while Fleet is visible. When disabled, the app
    /// still performs a complete HTTP snapshot on open or pull-to-refresh, but does not keep a live
    /// connection or retry it in the background.
    var realtimeMonitoring: Bool {
        get { storedValues.realtimeMonitoring }
        set {
            storedValues.realtimeMonitoring = newValue
            defaults.set(newValue, forKey: Keys.realtimeMonitoring)
        }
    }

    /// Local alerts are opt-in and only fire for explicit block evidence reported by a miner.
    var blockNotificationsEnabled: Bool {
        get { storedValues.blockNotificationsEnabled }
        set {
            storedValues.blockNotificationsEnabled = newValue
            defaults.set(newValue, forKey: Keys.blockNotificationsEnabled)
        }
    }

    /// Opt-in alerts for a new personal-best share. Separate from block alerts because this is
    /// mining progress, not proof that a block was solved.
    var bestShareNotificationsEnabled: Bool {
        get { storedValues.bestShareNotificationsEnabled }
        set {
            storedValues.bestShareNotificationsEnabled = newValue
            defaults.set(newValue, forKey: Keys.bestShareNotificationsEnabled)
        }
    }

    /// Independently controls session-record alerts; all-time record alerts use bestShareNotificationsEnabled.
    var sessionBestNotificationsEnabled: Bool {
        get { storedValues.sessionBestNotificationsEnabled }
        set {
            storedValues.sessionBestNotificationsEnabled = newValue
            defaults.set(newValue, forKey: Keys.sessionBestNotificationsEnabled)
        }
    }

    var activityContentMode: FleetActivityContentMode {
        get { storedValues.activityContentMode }
        set {
            storedValues.activityContentMode = newValue
            defaults.set(newValue.rawValue, forKey: Keys.activityContentMode)
        }
    }

    /// Opt-in alerts for a miner going offline or coming back online. Fires once per transition.
    var stateChangeNotificationsEnabled: Bool {
        get { storedValues.stateChangeNotificationsEnabled }
        set {
            storedValues.stateChangeNotificationsEnabled = newValue
            defaults.set(newValue, forKey: Keys.stateChangeNotificationsEnabled)
        }
    }

    /// Opt-in alerts for significant dashboard metric changes (hashrate, power, efficiency) that
    /// move outside the miner's own expected range. Temperature uses its own per-miner policy.
    var metricAlertNotificationsEnabled: Bool {
        get { storedValues.metricAlertNotificationsEnabled }
        set {
            storedValues.metricAlertNotificationsEnabled = newValue
            defaults.set(newValue, forKey: Keys.metricAlertNotificationsEnabled)
        }
    }

    /// Opt-in delivery for per-miner high-power alarms and their resolutions. Each miner still
    /// needs its own enabled power alert policy in FleetPowerAlertPreferences.
    var powerAlertNotificationsEnabled: Bool {
        get { storedValues.powerAlertNotificationsEnabled }
        set {
            storedValues.powerAlertNotificationsEnabled = newValue
            defaults.set(newValue, forKey: Keys.powerAlertNotificationsEnabled)
        }
    }

    /// Store all miner telemetry (hashrate, temp, power, achievements) to database for historical viewing
    var telemetryStorageEnabled: Bool {
        get { storedValues.telemetryStorageEnabled }
        set {
            storedValues.telemetryStorageEnabled = newValue
            defaults.set(newValue, forKey: Keys.telemetryStorageEnabled)
        }
    }

    /// How long to keep historical telemetry data before auto-pruning
    var telemetryRetention: TelemetryRetention {
        get { storedValues.telemetryRetention }
        set {
            storedValues.telemetryRetention = newValue
            defaults.set(newValue.rawValue, forKey: Keys.telemetryRetention)
        }
    }

    init(defaults: UserDefaults = .standard) {
        // Start this release in System once, including upgrades from the old
        // forced two-mode preference. Explicit choices made afterward persist.
        if !defaults.bool(forKey: Keys.systemAppearanceMigration) {
            defaults.set(Appearance.system.rawValue, forKey: Keys.appearance)
            defaults.set(true, forKey: Keys.systemAppearanceMigration)
        }
        self.defaults = defaults
        self.storedValues = StoredValues(defaults: defaults)
    }

    /// Reloads all in-memory properties from the underlying UserDefaults suite.
    func reloadFromDefaults() {
        storedValues = StoredValues(defaults: defaults)
    }
}
