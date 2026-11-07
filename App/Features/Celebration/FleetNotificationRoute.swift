import Foundation

/// Where a notification tap should land. Persisted briefly in defaults so a cold launch from a
/// notification still routes once the scene is active, mirroring `FleetSystemNavigation`.
struct FleetNotificationRoute: Equatable, Sendable {
    let deviceID: UUID
    let celebration: FleetCelebration?

    static let requested = Notification.Name("app.hashfleet.openMinerFromNotification")
    private static let deviceKey = "app.hashfleet.pendingNotificationDevice"
    private static let celebrationKey = "app.hashfleet.pendingNotificationCelebration"

    /// Called from the notification delegate. Only miner-scoped notifications carry a device ID;
    /// anything else falls back to the existing open-the-fleet behaviour.
    static func handle(userInfo: [AnyHashable: Any], defaults: UserDefaults = .standard) -> Bool {
        guard let raw = userInfo[FleetCelebration.userInfoDevice] as? String,
              UUID(uuidString: raw) != nil else { return false }
        defaults.set(raw, forKey: deviceKey)
        if FleetCelebration(userInfo: userInfo) != nil {
            let strings = userInfo.reduce(into: [String: String]()) { result, pair in
                if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
            }
            defaults.set(strings, forKey: celebrationKey)
        } else {
            defaults.removeObject(forKey: celebrationKey)
        }
        NotificationCenter.default.post(name: requested, object: nil)
        return true
    }

    static func consume(defaults: UserDefaults = .standard) -> FleetNotificationRoute? {
        guard let raw = defaults.string(forKey: deviceKey), let deviceID = UUID(uuidString: raw) else { return nil }
        let payload = defaults.dictionary(forKey: celebrationKey)
        defaults.removeObject(forKey: deviceKey)
        defaults.removeObject(forKey: celebrationKey)
        return FleetNotificationRoute(deviceID: deviceID, celebration: payload.flatMap(FleetCelebration.init(userInfo:)))
    }
}

/// Navigation value pushed onto the fleet stack when a notification opens a specific miner.
struct FleetMinerRoute: Hashable {
    let deviceID: UUID
}

/// Mac only: value route for miner settings and tuning pages. Closure-based NavigationLinks
/// inside the path-bound Mac detail stack drop taps and trigger NavigationRequestObserver loops.
struct FleetMinerSettingsRoute: Hashable {
    let deviceID: UUID
    let category: MinerSettingsCategory?
}

/// Lets Settings show the full-screen celebration on demand, using the first miner in the fleet,
/// so people can see what a new high score or found block looks like before one happens.
enum FleetCelebrationPreview {
    static let requested = Notification.Name("app.hashfleet.previewCelebration")

    static func request(kind: FleetCelebration.Kind) {
        NotificationCenter.default.post(name: requested, object: nil, userInfo: ["kind": kind.rawValue])
    }

    static func kind(from notification: Notification) -> FleetCelebration.Kind? {
        (notification.userInfo?["kind"] as? String).flatMap(FleetCelebration.Kind.init(rawValue:))
    }
}
