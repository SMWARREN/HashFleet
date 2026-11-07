import Foundation

/// An app-only alert preference, never a firmware target or hardware protection limit.
/// Mirrors `MinerTemperatureAlertPolicy` for per-miner power monitoring.
public struct MinerPowerAlertPolicy: Codable, Equatable, Sendable {
    public static let thresholdRange: ClosedRange<Double> = 1...5_000
    public static let defaultThresholdWatts: Double = 100
    /// Readings must fall this far below the threshold before a high episode resolves again.
    public static let hysteresisWatts: Double = 5
    public static let cooldown: TimeInterval = 30 * 60
    public static let maximumReadingAge: TimeInterval = 120

    public let isEnabled: Bool
    public let thresholdWatts: Double

    public init() {
        isEnabled = false
        thresholdWatts = Self.defaultThresholdWatts
    }

    public init(isEnabled: Bool, thresholdWatts: Double) throws {
        guard thresholdWatts.isFinite, Self.thresholdRange.contains(thresholdWatts) else {
            throw ValidationError.invalidThreshold
        }
        self.isEnabled = isEnabled
        self.thresholdWatts = thresholdWatts
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, thresholdWatts }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            isEnabled: values.decode(Bool.self, forKey: .isEnabled),
            thresholdWatts: values.decode(Double.self, forKey: .thresholdWatts)
        )
    }

    public enum ValidationError: Error, LocalizedError, Equatable {
        case invalidThreshold

        public var errorDescription: String? {
            "Enter a finite power from 1 to 5000 watts. This is an alert threshold, not a safe operating limit."
        }
    }
}
