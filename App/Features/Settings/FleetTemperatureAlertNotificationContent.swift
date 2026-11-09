import Foundation
import HashFleetCore

/// Payload only. The existing FleetLocalNotifications owner controls OS authorization/delivery.
struct FleetTemperatureAlertNotificationContent: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String

    init(event: MinerTemperatureAlertEvent) {
        // One slot per miner: a newer reading replaces the previous temperature alert.
        identifier = "app.hashfleet.temperature-alert.\(event.deviceID.uuidString)"
        title = "Temperature alert from \(event.minerName)"
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
        body = "Primary chip reported \(event.temperatureCelsius.formatted(format)) °C, "
            + "at or above your \(event.thresholdCelsius.formatted(format)) °C alert threshold. "
            + "Check your miner and cooling. No hardware settings were changed."
    }
}
