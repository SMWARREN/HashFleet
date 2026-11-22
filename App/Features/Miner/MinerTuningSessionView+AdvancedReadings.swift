import SwiftUI
import HashFleetCore

extension MinerTuningSessionView {
    var info: MinerInfo? { store.snapshot(for: device.id)?.info }

    /// Self-contained title identity so every entry point (quick link, card gear, dashboard,
    /// settings hub) shows the miner name and coin instead of relying on an inherited environment.
    var navigationIdentity: MinerNavigationIdentity {
        let context = MinerMiningContext.resolve(info: info)
        let coin = context.pool?.coin
        return MinerNavigationIdentity(
            deviceName: device.name,
            poolName: context.pool == nil ? nil : context.providerLabel,
            coin: coin,
            market: coin.flatMap { insights?.coinMarkets[$0] }
        )
    }

    var capabilityReport: MinerCapabilityReport? {
        store.capabilities.reports[device.id]
    }

    var reference: MinerTuningReference? {
        guard let asic = capabilityReport?.asic else { return nil }
        return try? MinerTuningReference(json: asic)
    }

    var configuredFrequency: Double? { MinerTuningSessionMath.validFrequency(info?.raw["frequency"]?.doubleValue) }
    private var actualFrequency: Double? { MinerTuningSessionMath.validFrequency(info?.raw["actualFrequency"]?.doubleValue) }
    var configuredVoltage: Double? { MinerTuningSessionMath.validVoltage(info?.raw["coreVoltage"]?.doubleValue) }
    private var measuredVoltage: Double? { MinerTuningSessionMath.validMeasuredVoltage(diagnostics.electrical.actualCoreVoltageMV) }

    var chipCount: Int {
        max(1, MinerTuningSessionMath.chipCount(reference: reference, info: info) ?? 1)
    }

    var chipCountWasReported: Bool {
        MinerTuningSessionMath.chipCount(reference: reference, info: info) != nil
    }

    private var diagnostics: MinerDiagnosticsModel {
        MinerDiagnosticsModel(info: info ?? MinerInfo(raw: [:]))
    }

    private var coreReadings: [MinerTuningCoreReading] {
        MinerTuningSessionMath.coreReadings(
            count: chipCount,
            primaryTemperature: diagnostics.thermal.primaryChipTempCelsius,
            secondaryTemperature: diagnostics.thermal.secondaryChipTempCelsius,
            voltageMillivolts: diagnostics.electrical.actualCoreVoltageMV
                ?? diagnostics.electrical.configuredCoreVoltageMV
        )
    }

    var referenceMaximum: Double? { MinerTuningSessionMath.referenceMaximum(reference) }

    var isBeyondReference: Bool {
        MinerTuningSessionMath.isBeyondReference(frequency, reference: reference)
    }

    private var controlRange: ClosedRange<Double> {
        MinerTuningSessionMath.controlRange(
            current: setpoints.frequencyBaseline ?? 1, reference: reference
        )
    }

    var voltageReferenceMaximum: Double? { MinerTuningSessionMath.voltageReferenceMaximum(reference) }

    var isVoltageBeyondReference: Bool {
        MinerTuningSessionMath.isVoltageBeyondReference(coreVoltage, reference: reference)
    }

    private var voltageRange: ClosedRange<Double> {
        MinerTuningSessionMath.voltageControlRange(
            current: setpoints.voltageBaseline ?? 1,
            reference: reference
        )
    }

    /// Car-style instrument cluster: frequency "tach" beside a core-voltage gauge, with a strip
    /// that compares what is staged against what the miner runs now.
    var advancedControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MinerTuningDialPair(
                frequency: MinerTuningDial(
                    title: "Frequency",
                    unit: "MHz",
                    setpoint: frequencyBinding,
                    range: controlRange,
                    liveValue: actualFrequency,
                    configuredValue: configuredFrequency,
                    referenceMaximum: referenceMaximum,
                    isBeyondReference: isBeyondReference,
                    isEnabled: setpoints.frequency != nil,
                    referenceOptions: reference?.frequencyOptions ?? [],
                    step: 1,
                    coarseStep: 10,
                    accessibilityPrefix: "tuningSession.master",
                    valueIdentifier: "tuningSession.frequencyValue",
                    compact: compactAdvanced
                ),
                voltage: MinerTuningDial(
                    title: "Core voltage",
                    unit: "mV",
                    setpoint: voltageBinding,
                    range: voltageRange,
                    liveValue: measuredVoltage,
                    configuredValue: configuredVoltage,
                    referenceMaximum: voltageReferenceMaximum,
                    isBeyondReference: isVoltageBeyondReference,
                    isRestricted: voltageRestriction != nil,
                    isEnabled: setpoints.coreVoltage != nil,
                    referenceOptions: reference?.voltageOptions ?? [],
                    step: 5,
                    coarseStep: 25,
                    accessibilityPrefix: "tuningSession.voltage",
                    valueIdentifier: "tuningSession.voltageValue",
                    compact: compactAdvanced
                )
            )
            .disabled(editsLocked)
            if !compactAdvanced, setpoints.frequency != nil, setpoints.coreVoltage != nil {
                MinerTuningDeltaStrip(
                    stagedFrequency: frequency,
                    configuredFrequency: configuredFrequency,
                    stagedVoltage: coreVoltage,
                    configuredVoltage: configuredVoltage
                )
            }
            if !compactAdvanced {
                Text("Frequency and core voltage are board-wide. Only the dials you move are sent, and nothing is sent while you drag.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tuningSession.advancedControlsSection")
    }

    func asicSection(proxy: ScrollViewProxy) -> some View {
        MinerTuningASICRail(
            proxy: proxy,
            chipCount: chipCount, coreReadings: coreReadings,
            frequency: setpoints.frequency,
            stagedVoltage: setpoints.coreVoltage,
            referenceMaximum: referenceMaximum,
            isAnyBeyondReference: isAnyBeyondReference
        )
    }

    var liveContextCard: some View {
        MinerTuningLiveContextCard(
            configuredFrequency: formattedFrequency(configuredFrequency), measuredFrequency: formattedFrequency(actualFrequency),
            configuredVoltage: formattedVoltage(configuredVoltage), measuredVoltage: formattedVoltage(measuredVoltage),
            asicErrors: hardwareErrorText, isChecking: store.capabilities.checking.contains(device.id)
        )
    }

    private var hardwareErrorText: String {
        guard let info else { return "Not reported" }
        return MinerShareSummary(info: info).firmwareErrorPercentageDisplay ?? "Not reported"
    }
}
