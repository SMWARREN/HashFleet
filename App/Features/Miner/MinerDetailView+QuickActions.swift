import SwiftUI
import HashFleetCore

extension MinerDetailView {
    func toolRow(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .fleetFont(.title3)
                .foregroundStyle(FleetTheme.accent)
                .frame(width: detailIconColumnWidth)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fleetFont(.headline).foregroundStyle(FleetTheme.ink)
                Text(subtitle).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").fleetFont(.caption, weight: .bold).foregroundStyle(FleetTheme.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .leading)
        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
        .contentShape(Rectangle())
    }

    func quickAction(_ endpoint: MinerEndpoint, symbol: String, id: String) -> some View {
        NavigationLink(value: endpoint) {
            VStack(spacing: 8) {
                Image(systemName: symbol).fleetFont(.title3)
                Text(endpoint.title)
                    .fleetFont(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(FleetTheme.accent)
            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: .infinity)
            .fleetCard(padding: FleetSurfaceSpacing.cardInset)
            .contentShape(Rectangle())
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .accessibilityIdentifier(id)
        .accessibilityHint("Opens a review form. No command is sent until you confirm it.")
    }
}
