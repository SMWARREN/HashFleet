import SwiftUI
import HashFleetCore

struct MinerReportedTemperature: Identifiable, Equatable {
    let title: String
    let key: String
    var id: String { key }
}

enum MinerThermalPresentation {
    static func reportedTemperatures(_ info: MinerInfo) -> [MinerReportedTemperature] {
        var readings = [MinerReportedTemperature(title: "Temperature", key: "temp")]
        if FleetFormat.sensor(info, keys: "temp2") != nil {
            readings.append(MinerReportedTemperature(title: "Temperature 2", key: "temp2"))
        }
        return readings
    }
}

/// Metric grid, cooling comparison and hero cards for MinerDetailView. Moved out of
/// MinerDetailView.swift for file/type length; identifiers and behavior are unchanged.
extension MinerDetailView {
    var metricGrid: FleetMinerDetailGrid {
        FleetMinerDetailGrid(maximumColumns: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    func metrics(_ info: MinerInfo, diagnostics: MinerDiagnosticsModel) -> some View {
        VStack(spacing: 14) {
            // These primary readings never collapse, and no extra header pushes them below the
            // initial viewport. Supply voltage uses the same audited mV source as diagnostics.
            primaryMetrics(info, diagnostics: diagnostics)
            coolingCard(info).fleetTourTarget("guide.cooling")
            tuningCard(info)
            secondaryMetrics(info, diagnostics: diagnostics)
        }
    }

    func primaryMetrics(_ info: MinerInfo, diagnostics: MinerDiagnosticsModel) -> some View {
        metricGrid {
            metric("Power", value: FleetFormat.sensor(info, keys: "power"), unit: "W", symbol: "bolt")
            metric(
                "Input voltage",
                value: diagnostics.electrical.inputVoltageMV.map { $0 / 1_000 },
                unit: "V",
                symbol: "powerplug"
            )
        }
    }

    func coolingCard(_ info: MinerInfo) -> some View {
        collapsibleCard(
            spec: MinerDetailCardSpec(
                title: "Cooling",
                subtitle: "Temperatures & fan readings",
                symbol: "fan",
                id: "detail.coolingDisclosure",
                settings: .cooling,
                settingsID: "detail.cooling.settings"
            ),
            expanded: $showsCooling
        ) {
            VStack(alignment: .leading, spacing: 12) {
                coolingComparison(info)
                metricGrid {
                    ForEach(MinerThermalPresentation.reportedTemperatures(info)) { reading in
                        metric(
                            reading.title,
                            value: FleetFormat.sensor(info, keys: reading.key),
                            unit: "°C",
                            symbol: "thermometer.medium"
                        )
                    }
                    metric("VR temp", value: FleetFormat.sensor(info, keys: "vrTemp"), unit: "°C", symbol: "cpu")
                    metric(
                        "Fan speed",
                        value: FleetFormat.sensor(info, keys: "fanspeed", "fanSpeed"),
                        unit: "%",
                        symbol: "fan"
                    )
                    metric(
                        "Fan rotation",
                        value: FleetFormat.sensor(info, keys: "fanrpm", "fanRpm"),
                        unit: "RPM",
                        symbol: "arrow.triangle.2.circlepath"
                    )
                }
                Text("Temperature labels follow the reported sensors, not ASIC count.")
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func tuningCard(_ info: MinerInfo) -> some View {
        collapsibleCard(
            spec: MinerDetailCardSpec(
                title: "Tuning",
                subtitle: "Frequency & core voltage",
                symbol: "gauge.with.dots.needle.67percent",
                id: "detail.tuningDisclosure",
                settings: .tuning,
                settingsID: "detail.tuning.settings"
            ),
            expanded: $showsTuning
        ) {
            metricGrid {
                metric(
                    "Frequency",
                    value: FleetFormat.sensor(info, keys: "frequency"),
                    unit: "MHz",
                    symbol: "waveform"
                )
                metric(
                    "Core voltage",
                    value: FleetFormat.sensor(info, keys: "coreVoltage"),
                    unit: "mV",
                    symbol: "powerplug"
                )
            }
        }
    }

    func secondaryMetrics(_ info: MinerInfo, diagnostics: MinerDiagnosticsModel) -> some View {
        metricGrid {
            metric(
                "Wi-Fi signal",
                value: FleetFormat.sensor(info, keys: "wifiRSSI", "wifiRssi", allowNegative: true),
                unit: "dBm",
                symbol: "wifi"
            )
            // Same audited derivation the diagnostics section uses, so the two can never disagree.
            metric(
                "Efficiency",
                value: diagnostics.electrical.efficiencyJoulesPerTerahash,
                unit: "J/TH",
                symbol: "leaf"
            )
        }
    }

    func metric(_ title: String, value: Double?, unit: String, symbol: String) -> some View {
        MinerDetailMetric(title: title, value: value, unit: unit, symbol: symbol)
    }

    @ViewBuilder
    func coolingComparison(_ info: MinerInfo) -> some View {
        let comparisons = MinerCoolingComparison.readings(current: info, previous: snapshot?.previousInfo)
        if !comparisons.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Since previous sample", systemImage: "clock.arrow.circlepath")
                    .fleetFont(.caption, weight: .semibold)
                    .foregroundStyle(FleetTheme.secondary)
                ForEach(comparisons) { comparison in
                    // One recorded line per reading: header stays on the leading side, the
                    // Now/delta/was values stay on the right and shrink instead of wrapping.
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            comparisonTitle(comparison)
                        }
                        Spacer(minLength: 4)
                        comparisonValues(comparison)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Temperature color shows direction only. It is not a firmware health verdict.")
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(FleetSurfaceSpacing.cardInset)
            .background(FleetTheme.canvas.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail.coolingComparison")
        }
    }

    func comparisonTitle(_ comparison: MinerCoolingComparison) -> some View {
        Text(comparison.title)
            .fleetFont(.caption, design: .monospaced)
            .foregroundStyle(FleetTheme.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(width: coolingComparisonLabelWidth, alignment: .leading)
    }

    func comparisonValues(_ comparison: MinerCoolingComparison) -> some View {
        let color = comparisonColor(comparison)
        let currentText = coolingValue(comparison.current, unit: comparison.unit)
        let deltaText = coolingValue(abs(comparison.delta), unit: comparison.unit)
        let previousText = coolingValue(comparison.previous, unit: comparison.unit)
        return HStack(spacing: 5) {
            Text("Now \(currentText)")
                .monospacedDigit()
                .fleetNumericUpdate(currentText, reduceMotion: reduceMotion)
            Image(systemName: comparison.direction.symbol)
                .accessibilityHidden(true)
            Text(deltaText)
                .monospacedDigit()
                .fleetNumericUpdate(deltaText, reduceMotion: reduceMotion)
            Text("was \(previousText)")
                .monospacedDigit()
                .fleetNumericUpdate(previousText, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: CGFloat.infinity, alignment: .trailing)
        .fleetFont(.caption, design: .monospaced)
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .accessibilityLabel(comparisonLabel(comparison))
    }

    func comparisonLabel(_ comparison: MinerCoolingComparison) -> String {
        let current = coolingValue(comparison.current, unit: comparison.unit)
        let delta = coolingValue(abs(comparison.delta), unit: comparison.unit)
        let previous = coolingValue(comparison.previous, unit: comparison.unit)
        return "Now \(current), \(comparison.direction.voiceLabel) \(delta), was \(previous)"
    }

    func comparisonColor(_ comparison: MinerCoolingComparison) -> Color {
        guard comparison.title.localizedCaseInsensitiveContains("temp") else { return FleetTheme.secondary }
        switch comparison.direction {
        case .decreased: return FleetTheme.positive
        case .unchanged: return FleetTheme.secondary
        case .increased: return FleetTheme.warning
        }
    }

    func coolingValue(_ value: Double, unit: String) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1))))\(unit)"
    }

    @ViewBuilder
    func heroConditions(_ info: MinerInfo) -> some View {
        // The two readings an owner checks first, promoted beside the hashrate.
        let temp = MinerHeroReading(
            title: store.isDemo ? "TEMPERATURE (SAMPLE)" : "TEMPERATURE",
            symbol: "thermometer.medium",
            value: FleetFormat.sensor(info, keys: "temp"),
            unit: "°C",
            caption: "Chip temperature",
            id: "detail.hero.temperature"
        )
        let power = MinerHeroReading(
            title: store.isDemo ? "POWER (SAMPLE)" : "POWER",
            symbol: "bolt.fill",
            value: FleetFormat.sensor(info, keys: "power"),
            unit: "W",
            caption: "Total device power",
            id: "detail.hero.power"
        )
        if dynamicTypeSize.isAccessibilitySize {
            heroCondition(temp)
            heroCondition(power)
        } else {
            HStack(alignment: .top, spacing: 12) {
                heroCondition(temp)
                heroCondition(power)
            }
            // Keep the pair the same height when one title wraps to two lines.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    func heroCondition(_ reading: MinerHeroReading) -> some View {
        let display =
            reading.value.map { $0.formatted(.number.precision(.fractionLength(0...1))) }
            ?? "Not reported"
        return VStack(alignment: .leading, spacing: 8) {
            Label(reading.title, systemImage: reading.symbol)
                .fleetFont(.caption2, weight: .medium, design: .monospaced)
                .foregroundStyle(FleetTheme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(display)
                    .fleetFont(.title, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(FleetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .fleetNumericUpdate(display, reduceMotion: reduceMotion)
                if reading.value != nil {
                    Text(reading.unit).fleetFont(.subheadline).foregroundStyle(FleetTheme.secondary)
                }
            }
            Text(reading.caption).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.accessibilityLabel(display: display))
        .accessibilityIdentifier(reading.id)
    }
}
