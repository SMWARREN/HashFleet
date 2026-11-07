import SwiftUI
import HashFleetCore

extension MinerDiagnosticsView {
    // MARK: - Electrical & Clocks

    var clocksAndElectricalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("ELECTRICAL & CLOCKS", symbol: "bolt.fill")
            VStack(spacing: 7) {
                diagRow("Frequency (configured)",
                        value: MinerDiagnosticsModel.formatFrequency(model.electrical.configuredFrequencyMHz),
                        id: "diagnostics.freq.configured")
                diagRow("Frequency (measured)",
                        value: MinerDiagnosticsModel.formatFrequency(model.electrical.actualFrequencyMHz),
                        id: "diagnostics.freq.measured")
                diagRow("Core voltage (configured)",
                        value: MinerDiagnosticsModel.formatMillivolts(model.electrical.configuredCoreVoltageMV),
                        id: "diagnostics.volt.configured")
                diagRow("Core voltage (measured)",
                        value: MinerDiagnosticsModel.formatMillivolts(model.electrical.actualCoreVoltageMV),
                        id: "diagnostics.volt.measured")
                diagRow("Board input voltage",
                        value: MinerDiagnosticsModel.formatMillivolts(model.electrical.inputVoltageMV),
                        id: "diagnostics.volt.input")
                diagRow("Nominal board voltage",
                        value: MinerDiagnosticsModel.formatVolts(model.electrical.nominalVoltageV),
                        id: "diagnostics.volt.nominal")
                diagRow("Regulator current (DC)",
                        value: MinerDiagnosticsModel.formatMilliamps(model.electrical.currentMilliamps),
                        id: "diagnostics.current.regulator")
                diagRow("Power draw",
                        value: MinerDiagnosticsModel.formatWatts(model.electrical.powerWatts),
                        id: "diagnostics.power")
                diagRow("Est. daily energy",
                        value: MinerDiagnosticsModel.formatEnergyKWhPerDay(model.electrical.dailyEnergyEstimateKWh),
                        id: "diagnostics.energy.estimate")
                if let eff = model.electrical.efficiencyJoulesPerTerahash {
                    diagRow("Reported efficiency",
                        value: "\(eff.formatted(.number.precision(.fractionLength(1)))) J/TH",
                        id: "diagnostics.efficiency")
                }
            }
            Text(MinerDiagnosticsModel.ElectricalAndClocks.energyEstimateDisclaimer)
                .fleetFont(.caption2)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            Text(MinerDiagnosticsModel.ElectricalAndClocks.mainsCurrentDisclaimer)
                .fleetFont(.caption2)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagnostics.section.electrical")
    }

    // MARK: - Thermal & Cooling

    var thermalAndCoolingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("THERMAL & COOLING", symbol: "thermometer.medium")
            VStack(spacing: 7) {
                diagRow("Primary chip temp",
                    value: MinerDiagnosticsModel.formatTemperature(model.thermal.primaryChipTempCelsius),
                    id: "diagnostics.temp.primary")
                diagRow(
                    "Secondary chip temp",
                    value: model.thermal.isSecondaryTempAvailable
                        ? MinerDiagnosticsModel.formatTemperature(model.thermal.secondaryChipTempCelsius)
                        : "Not reported / unavailable",
                    id: "diagnostics.temp.secondary"
                )
                diagRow(
                    "VR / regulator temp",
                    value: model.thermal.isVRTempAvailable
                        ? MinerDiagnosticsModel.formatTemperature(model.thermal.vrTempCelsius)
                        : "Not reported / unavailable",
                    id: "diagnostics.temp.vr"
                )
                diagRow("Fan speed (control)",
                    value: MinerDiagnosticsModel.formatPercentage(model.thermal.fanSpeedPercent, decimals: 0),
                    id: "diagnostics.fan.speed")
                diagRow("Primary fan speed",
                    value: MinerDiagnosticsModel.formatFanRPM(model.thermal.fan1RPM),
                    id: "diagnostics.fan1.rpm")
                diagRow(
                    "Secondary fan speed",
                    value: model.thermal.isFan2Available
                        ? MinerDiagnosticsModel.formatFanRPM(model.thermal.fan2RPM)
                        : "Not reported / unavailable",
                    id: "diagnostics.fan2.rpm"
                )
                if let target = model.thermal.targetTempCelsius {
                    diagRow("Target temperature",
                        value: MinerDiagnosticsModel.formatTemperature(target),
                        id: "diagnostics.temp.target")
                }
                if let minFan = model.thermal.minFanSpeedPercent {
                    diagRow("Minimum fan speed",
                        value: MinerDiagnosticsModel.formatPercentage(minFan, decimals: 0),
                        id: "diagnostics.fan.min")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagnostics.section.thermal")
    }

    // MARK: - Hashrate & Performance

    var hashrateAndPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("HASHRATE & PERFORMANCE", symbol: "waveform.path")
            VStack(spacing: 7) {
                diagRow("Hashrate (current)",
                    value: MinerDiagnosticsModel.formatHashrate(model.hashrate.currentHashrateGHs),
                    id: "diagnostics.hashrate.current")
                diagRow("Hashrate (1m avg)",
                    value: MinerDiagnosticsModel.formatHashrate(model.hashrate.hashrate1mGHs),
                    id: "diagnostics.hashrate.1m")
                diagRow("Hashrate (10m avg)",
                    value: MinerDiagnosticsModel.formatHashrate(model.hashrate.hashrate10mGHs),
                    id: "diagnostics.hashrate.10m")
                diagRow("Hashrate (1h avg)",
                    value: MinerDiagnosticsModel.formatHashrate(model.hashrate.hashrate1hGHs),
                    id: "diagnostics.hashrate.1h")
                if let trend = model.hashrateTrend {
                    // Derived only from the reported 1m and 1h averages; wording names both so it
                    // reads as a comparison of reported values, never a prediction.
                    diagRow("Recent trend",
                        value: trend.title,
                        id: "diagnostics.hashrate.trend")
                }
                diagRow("Expected hashrate",
                    value: MinerDiagnosticsModel.formatHashrate(model.hashrate.expectedHashrateGHs),
                    id: "diagnostics.hashrate.expected")
                diagRow("ASIC error rate",
                    value: MinerDiagnosticsModel.formatPercentage(model.hashrate.asicErrorPercentage),
                    id: "diagnostics.error.asic")
                diagRow("Rejected share rate",
                    value: MinerDiagnosticsModel.formatPercentage(model.hashrate.rejectedSharePercentage),
                    id: "diagnostics.error.rejected")
                diagRow("Shares accepted",
                    value: model.hashrate.sharesAccepted.map { "\($0.formatted())" } ?? "Not reported",
                    id: "diagnostics.shares.accepted")
                diagRow("Shares rejected",
                    value: model.hashrate.sharesRejected.map { "\($0.formatted())" } ?? "Not reported",
                    id: "diagnostics.shares.rejected")
                diagRow("Shares pending (SV2)",
                    value: model.hashrate.sharesPending.map { "\($0.formatted())" } ?? "0 (SV1 or synced)",
                    id: "diagnostics.shares.pending")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagnostics.section.performance")
    }
}
