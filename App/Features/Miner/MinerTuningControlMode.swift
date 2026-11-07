import Foundation

/// Control mode for the tuning session. Easy shows dropdown + custom input; Advanced shows car-style dials.
enum MinerTuningControlMode: String, CaseIterable, Sendable {
    case easy = "Easy"
    case advanced = "Advanced"

    var displayName: String { rawValue }

    var systemImage: String {
        switch self {
        case .easy: "list.bullet.rectangle"
        case .advanced: "gauge.with.dots.needle.67percent"
        }
    }
}
