import SwiftUI

/// Shared card chrome used by Miner controls and its direct tuning editor.
struct MinerControlsCard<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FleetSurfaceSpacing.cardInset)
        .background(
            LinearGradient(
                colors: [FleetTheme.surface, FleetTheme.raised.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FleetTheme.controlBorder.opacity(0.55))
        )
    }
}

struct MinerControlsHeader: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).fleetFont(.title3).foregroundStyle(FleetTheme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fleetFont(.headline).foregroundStyle(FleetTheme.ink)
                Text(subtitle).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
        }
    }
}
