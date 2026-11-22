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
                seriesValue: historyValue,
                dash: FleetChartPalette.comparisonDash(for: index)
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
            Rectangle()
                .frame(width: 25, height: 2)
                .hidden()
                .overlay {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 1))
                        path.addLine(to: CGPoint(x: 25, y: 1))
                    }
                    .stroke(item.color, style: StrokeStyle(lineWidth: 2, dash: item.dash))
                }
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
