import SwiftUI
import Charts
import HashFleetCore

/// Miner legend row grid shown below the history chart.
extension FleetHistoryCard {
    func historyLegend(
        for histories: [MinerHistorySeries],
        selection: FleetChartSelection?
    ) -> some View {
        let items: [FleetChartLegendItem] = histories.enumerated().map { index, history in
            let historyValue = selection?.seriesValues.first(where: { $0.id == history.id })
            return FleetChartLegendItem(
                id: history.id,
                name: history.name,
                color: FleetChartPalette.color(for: index),
                seriesValue: historyValue
            )
        }

        return Group {
            if selection != nil {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in legendItemView(item) }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], spacing: 8) {
                    ForEach(items) { item in legendItemView(item) }
                }
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.historyLegend")
    }

    private func legendItemView(_ item: FleetChartLegendItem) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(item.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(item.name)
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let seriesValue = item.seriesValue {
                Text(seriesValue.isMissing ? "—" : seriesValue.formattedRate)
                    .fleetFont(.caption, design: .monospaced)
                    .foregroundStyle(seriesValue.isMissing ? FleetTheme.secondary : FleetTheme.ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("dashboard.historySelection.series.\(item.id.uuidString)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibleDescription)
        .accessibilityIdentifier("dashboard.historyLegend.item.\(item.id.uuidString)")
    }
}
