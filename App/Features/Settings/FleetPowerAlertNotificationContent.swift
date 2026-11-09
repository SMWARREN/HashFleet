import Foundation
import HashFleetCore

/// Notification copy for a high-power alarm or its resolution. Mirrors
/// `FleetTemperatureAlertNotificationContent` and keeps miner telemetry out of the payload
/// beyond the reading that triggered the alarm.
struct FleetPowerAlertNotificationContent: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String

    init(event: MinerPowerAlertEvent) {
        // One slot per miner: "back to normal" replaces the high-power alarm it resolves.
        identifier = "app.hashfleet.power-alert.\(event.deviceID.uuidString)"
        switch event.kind {
        case .exceeded:
            title = "High power draw on \(event.minerName)"
            body = "\(event.minerName) reported \(FleetFormat.number(event.watts)) W, above its "
                + "\(FleetFormat.number(event.thresholdWatts)) W alert threshold."
        case .resolved:
            title = "Power back to normal on \(event.minerName)"
            body = "\(event.minerName) is back at \(FleetFormat.number(event.watts)) W, below its "
                + "\(FleetFormat.number(event.thresholdWatts)) W alert threshold."
        }
    }
}
