import Foundation

/// Easy and Advanced share the same board-wide draft and final hardware-policy gate.
enum MinerTuningEasyField: Sendable, Hashable {
    case frequency
    case voltage

    var unit: String { self == .frequency ? "MHz" : "mV" }

    func value(from text: String) throws -> Double {
        switch self {
        case .frequency:
            try MinerTuningDraft.frequencyValue(text)
        case .voltage:
            Double(try MinerTuningDraft.integer(text, name: "Core voltage", bounds: 1...65_535))
        }
    }

    /// These are reported choices, not recommended or hardware-safe profiles. Include the exact
    /// configured and staged values so the picker never displays a nearby value in their place.
    func options(reported: [Double], configured: Double?, staged: Double) -> [Double] {
        let candidates = reported + [configured, staged].compactMap { $0 }
        return Array(Set(candidates.filter { value in
            value.isFinite && (try? self.value(from: MinerTuningDraft.numericText(value))) == value
        })).sorted()
    }
}
