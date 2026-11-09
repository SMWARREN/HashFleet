import Foundation

/// An app-only alert preference, never a firmware target or hardware protection limit.
public struct MinerTemperatureAlertPolicy: Codable, Equatable, Sendable {
    public static let thresholdRange: ClosedRange<Double> = 30...110
    public static let defaultThresholdCelsius: Double = 75
    public static let hysteresisCelsius: Double = 5
    public static let cooldown: TimeInterval = 30 * 60
    public static let maximumReadingAge: TimeInterval = 120

    public let isEnabled: Bool
    public let thresholdCelsius: Double

    public init() {
        isEnabled = false
        thresholdCelsius = Self.defaultThresholdCelsius
    }

    public init(isEnabled: Bool, thresholdCelsius: Double) throws {
        guard thresholdCelsius.isFinite, Self.thresholdRange.contains(thresholdCelsius) else {
            throw ValidationError.invalidThreshold
        }
        self.isEnabled = isEnabled
        self.thresholdCelsius = thresholdCelsius
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, thresholdCelsius }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            isEnabled: values.decode(Bool.self, forKey: .isEnabled),
            thresholdCelsius: values.decode(Double.self, forKey: .thresholdCelsius)
        )
    }

    public enum ValidationError: Error, LocalizedError, Equatable {
        case invalidThreshold

        public var errorDescription: String? {
            "Enter a finite temperature from 30 to 110 °C. This is an alert threshold, not a safe operating limit."
        }
    }
}
