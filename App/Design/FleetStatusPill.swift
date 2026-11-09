import SwiftUI

/// Capsule status pill adapted from ShipSwift's `SWStatusBadge`: tinted text on a faint
/// matching fill with a hairline stroke. Static, so it costs nothing while idle.
struct FleetStatusPill: View {
    let text: String
    var systemImage: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(FleetTheme.mono(10).weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(tint)
        .background(Capsule().fill(tint.opacity(0.18)))
        .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 0.5))
        .fixedSize()
    }
}

/// What a miner row in the sidebar should call out. Healthy miners get no pill so the list
/// stays quiet and only problems stand out.
enum MinerSidebarAttention: Equatable, Sendable {
    case offline
    case hot(celsius: Double)

    /// Red-orange so a hot chip reads differently from the amber offline pill.
    static let hotTint = Color(red: 0xF0 / 255, green: 0x5A / 255, blue: 0x3C / 255)

    /// The hot case only, for surfaces that already show offline state another way.
    static func hotOnly(state: FleetMinerPresentationState, temperature: Double?) -> Self? {
        let attention = resolve(state: state, temperature: temperature)
        if case .hot = attention { return attention }
        return nil
    }

    /// Matches the existing sidebar warning color threshold for chip temperature.
    static let hotThresholdCelsius: Double = 70

    static func resolve(state: FleetMinerPresentationState, temperature: Double?) -> Self? {
        switch state {
        case .stale, .unreachable:
            return .offline
        case .live, .online:
            if let temperature, temperature.isFinite, temperature >= hotThresholdCelsius {
                return .hot(celsius: temperature)
            }
            return nil
        case .sample, .loading, .connecting, .reconnecting:
            return nil
        }
    }

    var text: String {
        switch self {
        case .offline: "Offline"
        case .hot(let celsius): "Hot \(FleetFormat.number(celsius))°C"
        }
    }

    var systemImage: String {
        switch self {
        case .offline: "wifi.slash"
        case .hot: "flame.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .offline: "Offline"
        case .hot(let celsius): "Running hot, \(FleetFormat.number(celsius)) degrees Celsius"
        }
    }
}
