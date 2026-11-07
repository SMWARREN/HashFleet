import SwiftUI
import HashFleetCore

/// Probe status presentation (icons, colors, labels) split from MinerCompatibilityView.swift
/// for file length.
extension MinerProbeStatus {
    var friendlyTitle: String {
        switch self {
        case .notChecked: "Not checked"
        case .supported: "Supported"
        case .unsupported: "Not supported"
        case .failed: "Could not check"
        }
    }

    var friendlyDetail: String? {
        switch self {
        case .notChecked:
            "This read has not been performed by a compatibility check."
        case .supported:
            "The miner returned a readable response."
        case .unsupported(let statusCode):
            "This firmware answered HTTP \(statusCode) for this path, "
                + "so the operation is not implemented on this device."
        case .failed(let message):
            "Support is still unknown, so nothing here says the feature is missing: \(message)"
        }
    }

    var symbol: String {
        switch self {
        case .notChecked: "questionmark.circle"
        case .supported: "checkmark.circle.fill"
        case .unsupported: "slash.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notChecked: FleetTheme.secondary
        case .supported: FleetTheme.positive
        case .unsupported: FleetTheme.secondary
        case .failed: FleetTheme.warning
        }
    }
}
