import Foundation
import HashFleetCore

/// A single cooling reading compared with the prior successful response.
struct MinerCoolingComparison: Identifiable, Equatable, Sendable {
    enum Direction: Equatable, Sendable {
        case decreased
        case unchanged
        case increased

        var symbol: String {
            switch self {
            case .decreased: "arrow.down"
            case .unchanged: "arrow.right"
            case .increased: "arrow.up"
            }
        }

        var voiceLabel: String {
            switch self {
            case .decreased: "down"
            case .unchanged: "unchanged by"
            case .increased: "up"
            }
        }
    }

    let id: String
    let title: String
    let unit: String
    let current: Double
    let previous: Double

    var delta: Double { current - previous }
    var direction: Direction {
        if abs(delta) < 0.5 { return .unchanged }
        return delta < 0 ? .decreased : .increased
    }

    private struct Definition {
        let title: String
        let id: String
        let unit: String
        let keys: [String]
        let allowNegative: Bool
    }

    /// Only values present in both responses are compared. A firmware omission is not a zero.
    static func readings(current: MinerInfo, previous: MinerInfo?) -> [MinerCoolingComparison] {
        guard let previous else { return [] }
        let definitions: [Definition] = [
            Definition(title: "Chip temp", id: "chipTemp", unit: "°C", keys: ["temp"], allowNegative: false),
            Definition(title: "VR temp", id: "vrTemp", unit: "°C", keys: ["vrTemp"], allowNegative: false),
            Definition(title: "Fan", id: "fanSpeed", unit: "%", keys: ["fanspeed", "fanSpeed"], allowNegative: false)
        ]
        return definitions.compactMap { def in
            guard let currentValue = reading(current, keys: def.keys, allowNegative: def.allowNegative),
                let previousValue = reading(previous, keys: def.keys, allowNegative: def.allowNegative)
            else {
                return nil
            }
            return MinerCoolingComparison(
                id: def.id,
                title: def.title,
                unit: def.unit,
                current: currentValue,
                previous: previousValue
            )
        }
    }

    private static func reading(_ info: MinerInfo, keys: [String], allowNegative: Bool) -> Double? {
        keys.lazy.compactMap { info.raw[$0]?.doubleValue }
            .first { $0.isFinite && (allowNegative || $0 >= 0) }
    }
}
