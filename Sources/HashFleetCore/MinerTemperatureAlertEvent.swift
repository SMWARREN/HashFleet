import Foundation

/// Evidence of one fresh primary-chip temperature reading at or above the selected threshold.
/// This does not claim a hardware fault, shutdown, or notification delivery.
public struct MinerTemperatureAlertEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let deviceID: UUID
    public let minerName: String
    public let temperatureCelsius: Double
    public let thresholdCelsius: Double
    public let occurredAt: Date

    public init(
        id: UUID = UUID(), deviceID: UUID, minerName: String,
        temperatureCelsius: Double, thresholdCelsius: Double, occurredAt: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.minerName = minerName
        self.temperatureCelsius = temperatureCelsius
        self.thresholdCelsius = thresholdCelsius
        self.occurredAt = occurredAt
    }
}
