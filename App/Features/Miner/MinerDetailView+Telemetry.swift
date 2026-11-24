import HashFleetCore
import SwiftUI

extension MinerDetailView {
    /// Supplies actual sample time and snapshot provenance so retained/error states never append history.
    func firmwareTelemetryView(_ info: MinerInfo) -> some View {
        let observedAt = snapshot?.completeSnapshotAt ?? snapshot?.updatedAt
        return FirmwareTelemetryView(
            info: info,
            observedAt: observedAt,
            minerIdentity: currentDevice.id.uuidString,
            isCached: snapshot?.isCached ?? true,
            error: snapshot?.error,
            isReconnecting: snapshot?.isReconnecting ?? true,
            freshness: MinerSnapshotFreshness(updatedAt: observedAt)
        )
    }

    /// Builds the detail telemetry sections from the same current MinerInfo sample.
    @ViewBuilder
    func telemetrySections(_ info: MinerInfo) -> some View {
        if usesNumberFirstDetail {
            numberFirstTelemetry(info)
        } else if isXMRig {
            hashrateHero(info)
            minerHistoryCard
            bestShares(info)
            xmrigControlLink
            identity(info)
        } else if dashboardMode == .essentials {
            #if os(macOS)
            if FleetLayout.isMac && usesWideDetail {
                desktopEssentialsTelemetrySections(info)
            } else {
                essentialsTelemetrySections(info)
            }
            #else
            essentialsTelemetrySections(info)
            #endif
        } else {
        let diagnostics = MinerDiagnosticsModel(info: info)
        if FleetLayout.isMac && usesWideDetail {
            desktopTelemetrySections(info, diagnostics: diagnostics)
        } else if usesWideDetail {
            // Wide windows: readings on the left, controls and secondary cards on the right, so
            // the whole miner fits without long scrolling. Order within each column is unchanged.
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    hashrateHero(info)
                    minerHistoryCard
                    firmwareTelemetryView(info)
                    heroConditions(info)
                    bestShares(info)
                    MinerDetailSection { metrics(info, diagnostics: diagnostics) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 14) {
                    controlMinerCard
                    identity(info)
                    poolsSection
                    MinerDiagnosticsView(model: diagnostics)
                    // Keep the shorter side useful instead of leaving a tall empty desktop column.
                    // On compact layouts these links retain their original position below telemetry.
                    controls
                        .fleetStaggeredEntrance(index: 6, reduceMotion: reduceMotion)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            hashrateHero(info)
            minerHistoryCard
            firmwareTelemetryView(info)
            heroConditions(info)
            bestShares(info)
            controlMinerCard
            identity(info)
            MinerDetailSection { metrics(info, diagnostics: diagnostics) }
            poolsSection
            MinerDiagnosticsView(model: diagnostics)
        }
        }
    }

    func essentialsTelemetrySections(_ info: MinerInfo) -> some View {
        let availability = NumberFirstPreview.minerAvailability(info, device: device, store: store)
        let usesEssentialsPools = !store.isDemo && dashboardMode == .essentials
        let showsSettings = availability.showsSettingsHub(in: dashboardMode, usesEssentialsPools: usesEssentialsPools)
        let hasBestShares = MiningDifficultyFormat.parse(info.raw["bestDiff"]) != nil
            || MiningDifficultyFormat.parse(info.raw["bestSessionDiff"]) != nil
        // Never put the history behind a disclosure or in a secondary column.
        return VStack(alignment: .leading, spacing: 10) {
            hashrateHero(info, compact: true)
            heroConditions(info, compact: true)
            minerHistoryCard
            if availability.cooling || availability.tuning || !availability.quickActions.isEmpty || showsSettings {
                numberFirstControls(availability, showsSettings: showsSettings)
            }
            if hasBestShares {
                bestShares(info, compact: true)
            }
            AnyView(essentialsAPITools)
            DisclosureGroup(isExpanded: $showsSecondaryReadings) {
                VStack(alignment: .leading, spacing: 14) {
                    firmwareTelemetryView(info)
                    if !isXMRig { uptimeHeatmap }
                    identity(info)
                    metrics(info, diagnostics: MinerDiagnosticsModel(info: info))
                    poolsSection
                }
                .padding(.top, 8)
            } label: {
                Text("More miner readings")
                    .fleetFont(.headline)
                    .foregroundStyle(FleetTheme.ink)
                    .frame(minHeight: 44)
            }
            .fleetCard(padding: 10, cornerRadius: 16)
            fleetManagementControls.buttonStyle(.plain)
        }
    }

    #if os(macOS)
    func desktopEssentialsTelemetrySections(_ info: MinerInfo) -> some View {
        let availability = NumberFirstPreview.minerAvailability(info, device: device, store: store)
        let usesEssentialsPools = !store.isDemo && dashboardMode == .essentials
        let showsSettings = availability.showsSettingsHub(in: dashboardMode, usesEssentialsPools: usesEssentialsPools)
        let hasBestShares = MiningDifficultyFormat.parse(info.raw["bestDiff"]) != nil
            || MiningDifficultyFormat.parse(info.raw["bestSessionDiff"]) != nil
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                hashrateHero(info, compact: true)
                heroConditions(info, compact: true)
                minerHistoryCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 12) {
                if availability.cooling || availability.tuning || !availability.quickActions.isEmpty || showsSettings {
                    numberFirstControls(availability, showsSettings: showsSettings)
                }
                if hasBestShares {
                    bestShares(info, compact: true)
                }
                essentialsAPITools
                DisclosureGroup(isExpanded: $showsSecondaryReadings) {
                    VStack(alignment: .leading, spacing: 12) {
                        firmwareTelemetryView(info)
                        if !isXMRig { uptimeHeatmap }
                        identity(info)
                        metrics(info, diagnostics: MinerDiagnosticsModel(info: info))
                        poolsSection
                    }
                    .padding(.top, 8)
                } label: {
                    Text("More miner readings")
                        .fleetFont(.headline)
                        .foregroundStyle(FleetTheme.ink)
                        .frame(minHeight: 44)
                }
                .fleetCard(padding: 10, cornerRadius: 16)
                fleetManagementControls.buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    #endif
}
