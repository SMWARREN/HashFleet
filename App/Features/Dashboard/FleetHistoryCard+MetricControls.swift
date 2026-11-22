import SwiftUI
import HashFleetCore

extension FleetHistoryCard {
    var chartTitle: some View {
        Text("\(showsSavedSensor ? selectedMetric.title : "Hashrate") trend")
            .fleetFont(numberFirst ? .subheadline : (isMinerDetail && !isEssentials ? .caption : .headline), weight: .semibold)
            .foregroundStyle(chartInk)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    var numberFirstMinerChartHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                chartTitle.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                metricMenu.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 0) {
                chartTitle
                metricMenu
            }
        }
    }

    var metricMenu: some View {
        Menu {
            ForEach(MinerHistoryMetric.allCases) { metric in
                Button {
                    selectedMetric = metric
                    rawSelectedDate = nil
                } label: {
                    if selectedMetric == metric {
                        Label(metric.title, systemImage: "checkmark")
                    } else {
                        Text(metric.title)
                    }
                }
                .accessibilityAddTraits(selectedMetric == metric ? .isSelected : [])
                .accessibilityIdentifier("detail.historyMetric.\(metric.rawValue)")
            }
        } label: {
            if numberFirst {
                HStack(spacing: 4) {
                    Text("Metric")
                    Image(systemName: "chevron.down").imageScale(.small).accessibilityHidden(true)
                }
                .fleetFont(.caption, weight: .medium)
                .foregroundStyle(chartInk)
                .padding(.horizontal, 10)
                .frame(minHeight: 24)
                .background(FleetTheme.raised, in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            } else {
                Label("Metric: \(selectedMetric.title)", systemImage: "chevron.up.chevron.down")
                    .fleetFont(.subheadline, weight: .medium)
                    .foregroundStyle(chartInk)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 10)
                    .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .fleetDesignedMenu()
        .accessibilityLabel("History metric")
        .accessibilityValue(selectedMetric.title)
        .accessibilityIdentifier("detail.historyMetric")
    }

}
