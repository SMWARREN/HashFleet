import SwiftUI

struct MinerTuningASICCard: View {
    let number: Int
    let coreReading: MinerTuningCoreReading
    let frequency: Double?
    let stagedVoltage: Double?
    let referenceMaximum: Double?
    let isBeyondReference: Bool
    let accessibilityPrefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 9) {
                    Text("\(number)")
                        .fleetFont(.title3, weight: .bold, design: .monospaced).monospacedDigit()
                        .foregroundStyle(isBeyondReference ? .red : FleetTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(
                            (isBeyondReference ? Color.red : FleetTheme.accent).opacity(0.13),
                            in: Circle()
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ASIC \(number)")
                            .fleetFont(.headline)
                            .accessibilityIdentifier("\(accessibilityPrefix).title")
                        Text("Core \(number) · shared board clock")
                            .fleetFont(.caption)
                            .foregroundStyle(FleetTheme.secondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(frequency.map { "\(MinerTuningDraft.numericText($0)) MHz" } ?? "Not reported")
                        .fleetFont(.subheadline, weight: .bold, design: .monospaced)
                        .foregroundStyle(isBeyondReference ? .red : FleetTheme.ink)
                        .accessibilityIdentifier("\(accessibilityPrefix).value")
                    Text(stagedVoltage.map { "\(MinerTuningDraft.numericText($0)) mV" } ?? "Not reported")
                        .fleetFont(.caption, weight: .semibold, design: .monospaced)
                        .foregroundStyle(FleetTheme.secondary)
                        .accessibilityIdentifier("\(accessibilityPrefix).stagedVoltage")
                }
            }
            HStack(spacing: 10) {
                coreMetric(
                    title: "Chip temp",
                    value: coreReading.temperatureCelsius.map { "\(numericText($0)) °C" } ?? "Not reported",
                    identifier: "\(accessibilityPrefix).temperature"
                )
                coreMetric(
                    title: "Core voltage",
                    value: coreReading.voltageMillivolts.map { "\(numericText($0)) mV" } ?? "Not reported",
                    identifier: "\(accessibilityPrefix).voltage"
                )
            }
            HStack {
                Label(
                    isBeyondReference ? "Over-reference" : "Tracking shared setpoint",
                    systemImage: isBeyondReference ? "exclamationmark.triangle.fill" : "link"
                )
                .fleetFont(.caption)
                .foregroundStyle(isBeyondReference ? .red : FleetTheme.secondary)
                Spacer()
                if let referenceMaximum {
                    Text("ref \(MinerTuningDraft.numericText(referenceMaximum))")
                        .fleetFont(.caption2, design: .monospaced)
                        .foregroundStyle(FleetTheme.secondary)
                }
            }
        }
        .fleetCard(padding: FleetSurfaceSpacing.cardInset, fill: isBeyondReference ? Color.red.opacity(0.07) : FleetTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isBeyondReference ? Color.red.opacity(0.5) : FleetTheme.ink.opacity(0.045), lineWidth: 1)
        }
    }

    private func coreMetric(title: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .fleetFont(.caption2, weight: .semibold)
                .foregroundStyle(FleetTheme.secondary)
            Text(value)
                .fleetFont(.caption, weight: .semibold, design: .monospaced)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numericText(_ value: Double) -> String {
        MinerTuningDraft.numericText(value)
    }
}
