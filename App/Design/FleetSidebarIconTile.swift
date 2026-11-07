import SwiftUI

/// Colored rounded-square icon tile for sidebar destinations, adapted from ShipSwift's
/// `SWLabelWithIcon` (colored shape behind a white SF Symbol, like System Settings).
/// Static drawing only: no animation, so it adds no idle CPU cost.
enum FleetSidebarTileTint: String, CaseIterable, Sendable {
    case amber, blue, yellow, orange, green, teal, gray, indigo, pink

    var color: Color {
        switch self {
        case .amber: Color(red: 0xF5 / 255, green: 0xAC / 255, blue: 0x26 / 255)
        case .blue: Color(red: 0x2F / 255, green: 0x7F / 255, blue: 0xE0 / 255)
        case .yellow: Color(red: 0xE8 / 255, green: 0xB4 / 255, blue: 0x00 / 255)
        case .orange: Color(red: 0xF0 / 255, green: 0x6E / 255, blue: 0x1E / 255)
        case .green: Color(red: 0x2A / 255, green: 0xAE / 255, blue: 0x68 / 255)
        case .teal: Color(red: 0x1F / 255, green: 0xA2 / 255, blue: 0xB0 / 255)
        case .gray: Color(red: 0x7C / 255, green: 0x86 / 255, blue: 0x8E / 255)
        case .indigo: Color(red: 0x5E / 255, green: 0x5C / 255, blue: 0xE6 / 255)
        case .pink: Color(red: 0xE0 / 255, green: 0x4F / 255, blue: 0x86 / 255)
        }
    }
}

struct FleetSidebarIconStyle: Equatable, Sendable {
    let symbol: String
    let tint: FleetSidebarTileTint
}

extension FleetSidebarDestination {
    /// Icon tile for fixed destinations. Miner rows keep their live status dot instead.
    var iconStyle: FleetSidebarIconStyle? {
        switch self {
        case .overview: FleetSidebarIconStyle(symbol: "gauge.with.needle", tint: .amber)
        case .miner: nil
        case .network: FleetSidebarIconStyle(symbol: "point.3.connected.trianglepath.dotted", tint: .blue)
        case .energy: FleetSidebarIconStyle(symbol: "bolt.fill", tint: .yellow)
        case .achievements: FleetSidebarIconStyle(symbol: "trophy.fill", tint: .orange)
        case .reports: FleetSidebarIconStyle(symbol: "doc.text.fill", tint: .green)
        case .backup: FleetSidebarIconStyle(symbol: "arrow.triangle.2.circlepath", tint: .teal)
        case .monitoring, .preferences: FleetSidebarIconStyle(symbol: "gearshape.fill", tint: .gray)
        case .about: FleetSidebarIconStyle(symbol: "info.circle.fill", tint: .indigo)
        case .support: FleetSidebarIconStyle(symbol: "heart.fill", tint: .pink)
        }
    }
}

struct FleetSidebarIconTile: View {
    /// Same as the shared sidebar icon column, so titles stay aligned on Mac and iPad.
    static var tileSize: CGFloat { FleetLayout.sidebarIconWidth }
    static let symbolSize: CGFloat = 11

    let style: FleetSidebarIconStyle

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(style.tint.color.gradient)
            .frame(width: Self.tileSize, height: Self.tileSize)
            .overlay {
                Image(systemName: style.symbol)
                    .font(.system(size: Self.symbolSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// Sidebar label with a colored tile. Text is unchanged, so accessibility and UI tests keep
/// finding the same row titles.
struct FleetSidebarTileLabel: View {
    let title: String
    let destination: FleetSidebarDestination

    var body: some View {
        if let style = destination.iconStyle {
            Label {
                Text(title)
            } icon: {
                FleetSidebarIconTile(style: style)
            }
        } else {
            Text(title)
        }
    }
}
