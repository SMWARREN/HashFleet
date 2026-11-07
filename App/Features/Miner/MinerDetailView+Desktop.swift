import SwiftUI
import HashFleetCore

extension MinerDetailView {
    var minerHistoryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            FleetHistoryCard(
                devices: [currentDevice],
                snapshots: store.snapshots(for: [currentDevice.id]),
                isDemo: store.isDemo,
                initialDisplay: .miners,
                isMinerDetail: true,
                uptime: isXMRig ? nil : MinerUptimeHeatmap(
                    deviceID: currentDevice.id,
                    isDemo: store.isDemo,
                    recentHistory: store.snapshot(for: currentDevice.id)?.history ?? []
                )
            )
            if FleetMetricTotal.reading(info, keys: FleetTotals.hashrateKeys) == nil {
                let readings = (store.snapshot(for: currentDevice.id)?.history ?? [])
                    .filter { $0.value.isFinite && $0.value >= 0 }
                if !readings.isEmpty {
                    let average = readings.reduce(0.0) { $0 + $1.value / Double(readings.count) }
                    Text("Retained history average: \(FleetFormat.hashrateWithUnit(average)) · \(readings.count) readings")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                        .accessibilityIdentifier("detail.retainedHistoryAverage")
                }
            }
        }
        .accessibilityIdentifier("detail.history")
    }

    /// Primary readings keep the full page width. Only related secondary cards
    /// share a row, so controls never stretch to the height of a stack of charts.
    @ViewBuilder
    func desktopTelemetrySections(_ info: MinerInfo, diagnostics: MinerDiagnosticsModel) -> some View {
        desktopPrimarySections(info)
        FleetMinerDetailGrid(maximumColumns: min(2, detailColumnCount), minimumColumnWidth: 320, spacing: 14) {
            bestShares(info)
            identity(info)
        }
        MinerDetailSection { metrics(info, diagnostics: diagnostics) }
        FleetMinerDetailGrid(maximumColumns: min(2, detailColumnCount), minimumColumnWidth: 320, spacing: 14) {
            MinerDiagnosticsView(model: diagnostics)
            poolsSection
        }
        AnyView(controls)
            .fleetStaggeredEntrance(index: 6, reduceMotion: reduceMotion)
    }

    func desktopPrimarySections(_ info: MinerInfo) -> some View {
        VStack(spacing: 14) {
            hashrateHero(info)
            minerHistoryCard
            firmwareTelemetryView(info)
            heroConditions(info)
            // Keep the navigation-heavy control subtree behind a type-erased boundary.
            // Copying its full opaque type inside the surrounding custom Layout can
            // crash in NavigationLink's StateOrBinding copy on the iPad runtime.
            AnyView(controlMinerCard)
        }
    }
}
