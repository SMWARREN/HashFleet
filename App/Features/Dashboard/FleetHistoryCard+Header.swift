import SwiftUI
import Charts
import HashFleetCore

/// Selected-vs-summary header strip shown above the history chart, plus its clear-selection control.
extension FleetHistoryCard {
    @ViewBuilder
    func periodHeader(
        for window: HistoryWindow,
        histories: [MinerHistorySeries],
        selection: FleetChartSelection?
    ) -> some View {
        let sampleCount = histories.reduce(0) { $0 + $1.points.count }

        Group {
            if let selection {
                selectedHeader(selection: selection, window: window)
            } else if !isFleetView, let summary = periodSummary(for: histories) {
                summaryHeader(window: window, summary: summary, sampleCount: sampleCount)
            }
        }
        .frame(minHeight: 38, alignment: .leading)
    }

    private func selectedHeader(selection: FleetChartSelection, window: HistoryWindow) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Selected · \(selection.formattedTimestamp(for: window.selectedTimestampFormat))")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityIdentifier("dashboard.historySelection.timestamp")
                Text(selection.formattedTotalRate + (selection.seriesValues.contains(where: \.isMissing) ? " subtotal" : ""))
                    .fleetFont(.title3, weight: .semibold, design: .monospaced)
                    .foregroundStyle(FleetTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dashboard.historySelection.rate")
                Spacer(minLength: 0)
                clearSelectionButton
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Selected · \(selection.formattedTimestamp(for: window.selectedTimestampFormat))")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                        .accessibilityIdentifier("dashboard.historySelection.timestamp")
                    Spacer(minLength: 0)
                    clearSelectionButton
                }
                Text(selection.formattedTotalRate + (selection.seriesValues.contains(where: \.isMissing) ? " subtotal" : ""))
                    .fleetFont(.title3, weight: .semibold, design: .monospaced)
                    .foregroundStyle(FleetTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dashboard.historySelection.rate")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.historySelection")
    }

    private func summaryHeader(window: HistoryWindow, summary: String, sampleCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(window == .daily ? recentRange.summaryLabel : window.summaryLabel) per-miner reading")
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    headerRateText(summary)
                    Text("\(sampleCount) samples")
                        .fleetFont(.caption2)
                        .foregroundStyle(FleetTheme.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    headerRateText(summary)
                    Text("\(sampleCount) samples")
                        .fleetFont(.caption2)
                        .foregroundStyle(FleetTheme.secondary)
                }
            }
        }
    }

    private func headerRateText(_ summary: String) -> some View {
        Text(summary)
            .fleetFont(.title3, weight: .semibold, design: .monospaced)
            .foregroundStyle(FleetTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    var clearSelectionButton: some View {
        Button {
            if reduceMotion {
                rawSelectedDate = nil
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    rawSelectedDate = nil
                }
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .fleetFont(.subheadline)
                .foregroundStyle(FleetTheme.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear selection")
        .accessibilityIdentifier("dashboard.historySelection.clear")
    }
}
