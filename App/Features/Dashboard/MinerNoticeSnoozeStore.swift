import Foundation

/// UserDefaults-backed snooze window for a miner status notice.
enum MinerNoticeSnoozeStore {
    static let duration: TimeInterval = 4 * 60 * 60
    private static let keyPrefix = "app.hashfleet.miner-status-notice-snooze.v1."

    static func snooze(for deviceID: UUID, at date: Date = .now, defaults: UserDefaults? = nil) {
        resolvedDefaults(defaults).set(date.addingTimeInterval(duration), forKey: key(for: deviceID))
    }

    static func isSnoozed(for deviceID: UUID, at date: Date = .now, defaults: UserDefaults? = nil) -> Bool {
        snoozedUntil(for: deviceID, at: date, defaults: defaults) != nil
    }

    static func snoozedUntil(for deviceID: UUID, at date: Date = .now, defaults: UserDefaults? = nil) -> Date? {
        let defaults = resolvedDefaults(defaults)
        guard let until = defaults.object(forKey: key(for: deviceID)) as? Date else { return nil }
        guard until > date else {
            defaults.removeObject(forKey: key(for: deviceID))
            return nil
        }
        return until
    }

    private static func key(for deviceID: UUID) -> String {
        "\(keyPrefix)\(deviceID.uuidString)"
    }

    private static func resolvedDefaults(_ defaults: UserDefaults?) -> UserDefaults {
        if let defaults { return defaults }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return UserDefaults(suiteName: "app.hashfleet.ui-tests") ?? .standard
        }
        return .standard
    }
}
