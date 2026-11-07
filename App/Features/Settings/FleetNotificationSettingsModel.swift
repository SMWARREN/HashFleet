import Observation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import UserNotifications

/// Settings-only permission state. Reading system settings never changes the user's saved choices.
@MainActor @Observable
final class FleetNotificationSettingsModel {
    enum Alert: CaseIterable {
        case blockFound
        case bestShare
        case sessionBestShare
        case disconnect
        case metricChange
        case power

        var title: String {
            switch self {
            case .blockFound: "Block-found alerts"
            case .bestShare: "Best-share alerts"
            case .sessionBestShare: "Session-best alerts"
            case .disconnect: "Disconnect alerts"
            case .metricChange: "Metric-change alerts"
            case .power: "High-power alerts"
            }
        }

        var identifier: String {
            switch self {
            case .blockFound: "preferences.blockNotifications"
            case .bestShare: "preferences.bestShareNotifications"
            case .sessionBestShare: "preferences.sessionBestNotifications"
            case .disconnect: "preferences.disconnectNotifications"
            case .metricChange: "preferences.metricAlertNotifications"
            case .power: "preferences.powerAlertNotifications"
            }
        }

        var explanation: String {
            switch self {
            case .blockFound:
                "When a miner reports a block counter increase or a new block-found flag. "
                    + "A high-difficulty share alone does not qualify."
            case .bestShare:
                "Master control for all-time or session best-share alerts. The all-time record takes priority when both improve. "
                    + "Use Session-best alerts below to suppress only session records. This is not proof of a block."
            case .sessionBestShare:
                "In the app, a miner's new session difficulty record shows the same illustrated popup as an "
                    + "all-time best. It stays until dismissed, not a brief toast. Turn this off to keep only all-time "
                    + "record alerts. You can also turn it off on that popup, and turn it back on here."
            case .disconnect:
                "When a reachable miner stops responding, and again when it comes back online. "
                    + "Each outage alerts once, with the time the connection was lost."
            case .metricChange:
                "When hashrate, power, or efficiency moves well outside the miner's own recent "
                    + "range, or hashrate falls to zero while the miner still answers. "
                    + "Small fluctuations stay silent. Temperature has its own per-miner setting."
            case .power:
                "Delivers a miner's per-miner high-power alarm, and again when its power returns "
                    + "below the threshold. Each miner's wattage threshold is set under Monitoring."
            }
        }
    }

    enum TestNotificationState: Equatable {
        case idle
        case sending
        case queued
        case blocked
        case failed

        @MainActor var message: String? {
            switch self {
            case .idle, .sending: nil
            case .queued:
                FleetDeviceCopy.current.queuedTestNotificationMessage
            case .blocked:
                "Notification permission is needed to send a test. Use \(FleetDeviceCopy.hostNotificationSettingsButtonTitle) above to allow notifications, then try again."
            case .failed:
                "Couldn’t send the test notification. Try again or check Hash Fleet notification permission in \(FleetDeviceCopy.hostSettingsAppName)."
            }
        }
    }

    struct Access: Equatable {
        let authorization: UNAuthorizationStatus
        var alertsEnabled = true
        var soundsEnabled = true

        var permitsNotifications: Bool {
            switch authorization {
            case .authorized, .provisional: true
#if os(iOS)
            case .ephemeral: true
#endif
            default: false
            }
        }

        var title: String {
            switch authorization {
            case .denied:
                "Blocked in \(FleetDeviceCopy.hostSettingsAppName)"
            case .notDetermined: "Permission not requested"
            case .provisional: "Quiet delivery only"
#if os(iOS)
            case .ephemeral: "Temporary permission"
#endif
            case .authorized:
                !alertsEnabled ? "Banners and alerts are off" : (!soundsEnabled ? "Allowed without sound" : "Allowed by system")
            @unknown default: "Permission unavailable"
            }
        }

        var explanation: String {
            switch authorization {
            case .denied:
#if os(macOS)
                "System Settings is blocking notifications from Hash Fleet. Open Notifications and allow alerts. Then return here to choose your alerts. Saved alert choices are kept."
#else
                "The system is blocking notifications from Hash Fleet. Open Settings, choose Notifications, "
                    + "and turn on Allow Notifications. Then return here to choose your alerts. Saved alert choices are kept."
#endif
            case .notDetermined:
                "Alert choices and system permission are separate. Best-share alerts are selected by default unless you have opted out. "
                    + "Turn on an alert or send a test to request permission. Testing never changes your saved alert choices."
            case .provisional:
                "Notifications may appear quietly in Notification Center, without a banner or sound. Change delivery options in \(FleetDeviceCopy.hostSettingsAppName)."
#if os(iOS)
            case .ephemeral:
                "Temporary notification access is active. Permission may expire."
#endif
            case .authorized:
#if os(macOS)
                "Permission is granted, not a delivery guarantee. "
                    + (!alertsEnabled ? "Enable alerts in System Settings to make notifications visible. " : "")
                    + (!soundsEnabled ? "Notification sounds are off in System Settings. " : "")
                    + "Focus and notification settings can silence or delay alerts."
#else
                "Permission is granted, not a delivery guarantee. "
                    + (!alertsEnabled ? "Enable banners or alerts in Settings to make notifications visible. " : "")
                    + (!soundsEnabled ? "Notification sounds are off in Settings. " : "")
                    + "Focus and Scheduled Summary can silence or delay alerts."
#endif
            @unknown default:
                "Check notification permission in \(FleetDeviceCopy.hostSettingsAppName) before relying on alerts."
            }
        }
    }

    static let frequencyExplanation =
        "Event-based, not scheduled. The first reading establishes a baseline and does not alert. "
        + "Unchanged readings do not alert again. Checks can miss events between readings, "
        + "and alerts from several miners may arrive together after a gap."
    static let backgroundExplanation = FleetDeviceCopy.current.backgroundExplanation
    static let connectionExplanation = FleetDeviceCopy.current.notificationConnectionExplanation
#if os(macOS)
    static let foregroundExplanation = "While Hash Fleet is running, new events appear in the app instead of as a system notification. "
        + "Closing the workspace window does not stop the app; quitting it stops local monitoring. Session "
        + "bests, all-time records and found blocks use the illustrated popup and stay until dismissed."
#else
    static let foregroundExplanation = "While Fleet is on screen, new events appear in the app instead of as a system notification. "
        + "Session bests, all-time records and found blocks use the illustrated miner popup and stay "
        + "until dismissed. Opening the app refreshes readings without repeating events already delivered "
        + "as system notifications. Demo mining events do not test notification delivery."
#endif
    static let settingsURL: URL = {
#if canImport(UIKit)
        URL(string: UIApplication.openSettingsURLString)!
#else
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
#endif
    }()

    private(set) var access: Access?
    #if canImport(UIKit)
    typealias BackgroundRefreshStatus = UIBackgroundRefreshStatus
    #else
    enum BackgroundRefreshStatus {
        case available, denied, restricted, unavailable
    }
    #endif

    private(set) var backgroundRefreshStatus: BackgroundRefreshStatus = .available
    private(set) var backgroundDiagnostics = FleetBackgroundRefreshDiagnostics.Snapshot()
    private(set) var isRequesting = false
    private(set) var testNotificationState: TestNotificationState = .idle
    var error: String?

    @ObservationIgnored private let preferences: FleetPreferences
    @ObservationIgnored private let readAccess: @MainActor () async -> Access
    @ObservationIgnored private let requestAccess: @MainActor () async throws -> Bool
    @ObservationIgnored private let readBackgroundStatus: @MainActor () -> BackgroundRefreshStatus
    @ObservationIgnored private let readBackgroundDiagnostics: @MainActor () -> FleetBackgroundRefreshDiagnostics.Snapshot
    @ObservationIgnored private let postTestNotification: @MainActor () async throws -> Void
    @ObservationIgnored private var revisions: [Alert: Int] = [:]
    @ObservationIgnored private var accessRevision = 0

    init(
        preferences: FleetPreferences,
        readAccess: @escaping @MainActor () async -> Access = {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return Access(
                authorization: settings.authorizationStatus,
                alertsEnabled: settings.alertSetting == .enabled,
                soundsEnabled: settings.soundSetting == .enabled
            )
        },
        requestAccess: @escaping @MainActor () async throws -> Bool = {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        },
        readBackgroundStatus: @escaping @MainActor () -> BackgroundRefreshStatus = {
#if canImport(UIKit)
            UIApplication.shared.backgroundRefreshStatus
#else
            .unavailable
#endif
        },
        readBackgroundDiagnostics: @escaping @MainActor () -> FleetBackgroundRefreshDiagnostics.Snapshot = {
            FleetBackgroundRefreshDiagnostics.shared.snapshot
        },
        postTestNotification: @escaping @MainActor () async throws -> Void = {
            try await FleetLocalNotifications.postTestNotification()
        }
    ) {
        self.preferences = preferences
        self.readAccess = readAccess
        self.requestAccess = requestAccess
        self.readBackgroundStatus = readBackgroundStatus
        self.readBackgroundDiagnostics = readBackgroundDiagnostics
        self.postTestNotification = postTestNotification
    }

    var backgroundTitle: String {
        switch backgroundRefreshStatus {
        case .available: "Background checks are best effort"
        case .denied: "Background App Refresh is unavailable"
        case .restricted: "Background App Refresh is restricted"
        #if os(macOS)
        case .unavailable: "Background refresh is not used on Mac"
        #endif
        @unknown default: "Background availability is unknown"
        }
    }

    var backgroundDetail: String {
        switch backgroundRefreshStatus {
        case .available: Self.backgroundExplanation
        case .denied:
            "Background checks cannot run right now. Check Background App Refresh in \(FleetDeviceCopy.hostSettingsAppName) "
                + "and turn off Low Power Mode if needed. Opening Hash Fleet still refreshes readings. "
                + Self.backgroundExplanation
        case .restricted:
            "A system restriction prevents background checks. Opening Hash Fleet still refreshes readings. " + Self.backgroundExplanation
        #if os(macOS)
        case .unavailable: "Background refresh is not used on Mac. Local notifications are supported while the app is running."
        #endif
        @unknown default: Self.backgroundExplanation
        }
    }

    func isSelected(_ alert: Alert) -> Bool {
        switch alert {
        case .blockFound: preferences.blockNotificationsEnabled
        case .bestShare: preferences.bestShareNotificationsEnabled
        case .sessionBestShare: preferences.sessionBestNotificationsEnabled
        case .disconnect: preferences.stateChangeNotificationsEnabled
        case .metricChange: preferences.metricAlertNotificationsEnabled
        case .power: preferences.powerAlertNotificationsEnabled
        }
    }

    /// Reflect effective permission without destroying opt-in choices when access is revoked outside the app.
    func isEnabled(_ alert: Alert) -> Bool {
        isSelected(alert) && access?.permitsNotifications == true
            && (alert != .sessionBestShare || preferences.bestShareNotificationsEnabled)
    }

    func deliveryNote(for alert: Alert) -> String? {
        if alert == .sessionBestShare, !preferences.bestShareNotificationsEnabled {
            return "Best-share alerts are off. Enable the master control to allow session-best alerts. Your session choice is saved."
        }
        guard let access, !access.permitsNotifications, access.authorization != .notDetermined else { return nil }
        return isSelected(alert)
            ? "Selected, but blocked by system notification settings. Use \(FleetDeviceCopy.hostNotificationSettingsButtonTitle) to restore delivery."
            : "Blocked by system notification settings. Use \(FleetDeviceCopy.hostNotificationSettingsButtonTitle) to allow notifications."
    }

    func refresh() async {
        // Returning from the authorization sheet can activate the scene. Let that request own its result.
        guard !isRequesting else { return }
        accessRevision += 1
        let revision = accessRevision
        let updated = await readAccess()
        guard !Task.isCancelled, !isRequesting, accessRevision == revision else { return }
        access = updated
        backgroundRefreshStatus = readBackgroundStatus()
        backgroundDiagnostics = readBackgroundDiagnostics()
    }

    func setEnabled(_ enabled: Bool, for alert: Alert) async {
        if !enabled {
            revisions[alert, default: 0] += 1
            save(false, for: alert)
            return
        }
        guard !isRequesting else { return }
        isRequesting = true
        accessRevision += 1
        error = nil
        let revision = revisions[alert, default: 0]
        defer { isRequesting = false }
        do {
            let permitted = try await authorizeIfNeeded()
            guard !Task.isCancelled, revisions[alert, default: 0] == revision else { return }
            save(permitted, for: alert)
        } catch {
            guard !Task.isCancelled, revisions[alert, default: 0] == revision else { return }
            save(false, for: alert)
            self.error = "Couldn’t request notification permission. Try again or open \(FleetDeviceCopy.hostSettingsAppName)."
        }
    }

    /// Exercises the real notification posting route without touching either alert preference.
    func sendTestNotification() async {
        guard !isRequesting else { return }
        isRequesting = true
        accessRevision += 1
        error = nil
        testNotificationState = .sending
        defer { isRequesting = false }
        do {
            guard try await authorizeIfNeeded() else {
                testNotificationState = .blocked
                return
            }
            try await postTestNotification()
            // Successful submission means the system accepted the request, not that a banner was shown.
            testNotificationState = .queued
        } catch is CancellationError {
            testNotificationState = .idle
        } catch {
            testNotificationState = .failed
        }
    }

    private func authorizeIfNeeded() async throws -> Bool {
        access = await readAccess()
        backgroundRefreshStatus = readBackgroundStatus()
        try Task.checkCancellation()
        if access?.authorization == .notDetermined {
            _ = try await requestAccess()
            access = await readAccess()
        }
        try Task.checkCancellation()
        return access?.permitsNotifications == true
    }

    func settingsDidOpen(_ success: Bool) {
#if os(macOS)
        error = success ? nil : "Couldn’t open Notification Settings. Open System Settings, choose Notifications, then select Hash Fleet."
#else
        error = success ? nil : "Couldn’t open Settings. Open Settings manually, then choose Apps → Hash Fleet → Notifications."
#endif
    }

    private func save(_ enabled: Bool, for alert: Alert) {
        switch alert {
        case .blockFound: preferences.blockNotificationsEnabled = enabled
        case .bestShare: preferences.bestShareNotificationsEnabled = enabled
        case .sessionBestShare: preferences.sessionBestNotificationsEnabled = enabled
        case .disconnect: preferences.stateChangeNotificationsEnabled = enabled
        case .metricChange: preferences.metricAlertNotificationsEnabled = enabled
        case .power: preferences.powerAlertNotificationsEnabled = enabled
        }
    }
}
