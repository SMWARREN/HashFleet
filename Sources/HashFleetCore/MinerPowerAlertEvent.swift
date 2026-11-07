import Foundation

/// Evidence of a fresh power reading crossing the selected threshold. An `.exceeded` event
/// reports a reading at or above the threshold; a `.resolved` event reports the alarm cleared
/// after watts returned below the threshold minus hysteresis. Neither claims a hardware fault,
/// shutdown, or notification delivery.
public struct MinerPowerAlertEvent: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case exceeded
        case resolved
    }

    public let id: UUID
    public let deviceID: UUID
    public let minerName: String
    public let kind: Kind
    public let watts: Double
    public let thresholdWatts: Double
    public let occurredAt: Date

    public init(
        id: UUID = UUID(), deviceID: UUID, minerName: String, kind: Kind,
        watts: Double, thresholdWatts: Double, occurredAt: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.minerName = minerName
        self.kind = kind
        self.watts = watts
        self.thresholdWatts = thresholdWatts
        self.occurredAt = occurredAt
    }
}
