import SwiftUI
import HashFleetCore

/// A compact disclosure view presenting deep diagnostics from available telemetry.
/// Follows `FleetTheme` styling and respects Dynamic Type.
struct MinerDiagnosticsView: View {
    let model: MinerDiagnosticsModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var iconColumnWidth: CGFloat = 28
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                header
                    .frame(maxWidth: .infinity, minHeight: 44,
                           maxHeight: isExpanded ? nil : .infinity, alignment: .leading)
                    .padding(16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail.diagnosticsDisclosure")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides read-only diagnostics. Does not change miner settings.")
            if isExpanded {
                VStack(alignment: .leading, spacing: 18) {
                    clocksAndElectricalSection
                    thermalAndCoolingSection
                    hashrateAndPerformanceSection
                    poolAndConnectionSection
                    systemAndFirmwareSection
                }
                .padding([.horizontal, .bottom], 16)
                .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isExpanded ? .topLeading : .leading)
        .fleetCard(padding: 0)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .fleetFont(.title3)
                .foregroundStyle(FleetTheme.accent)
                .frame(width: iconColumnWidth)
            VStack(alignment: .leading, spacing: 3) {
                Text("Miner Diagnostics")
                    .fleetFont(.headline)
                    .foregroundStyle(FleetTheme.ink)
                Text("Telemetry, clocks, cooling, energy & pool state")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                // Calm, factual notes listed first so gaps and explicit zero readings are
                // visible even while the section is collapsed. No verdicts, no alarms.
                ForEach(Array(model.attentionNotes.prefix(2)), id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .fleetFont(.caption, weight: .semibold)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .accessibilityHidden(true)
        }
    }
    // MARK: - Pool & Connection

    private var poolAndConnectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("POOL & STRATUM CONNECTION", symbol: "network")
            VStack(spacing: 7) {
                diagURLRow(
                    model.pool.activeConnectionTitle,
                    value: model.pool.activeConnectionURL,
                    id: "diagnostics.pool.active"
                )
                if let primary = model.pool.primaryURL {
                    diagURLRow("Primary URL", value: primary, id: "diagnostics.pool.primary.url")
                }
                if let port = model.pool.primaryPort {
                    diagRow("Primary port", value: "\(port)", id: "diagnostics.pool.primary.port")
                }
                if let proto = model.pool.primaryProtocol {
                    diagRow("Primary protocol", value: proto, id: "diagnostics.pool.primary.protocol")
                }
                if let tls = model.pool.primaryTLS {
                    diagRow("Primary TLS", value: tls ? "Enabled" : "Disabled", id: "diagnostics.pool.primary.tls")
                }
                if let fallback = model.pool.fallbackURL {
                    diagURLRow("Fallback URL", value: fallback, id: "diagnostics.pool.fallback.url")
                }
                if let port = model.pool.fallbackPort {
                    diagRow("Fallback port", value: "\(port)", id: "diagnostics.pool.fallback.port")
                }
                if let proto = model.pool.fallbackProtocol {
                    diagRow("Fallback protocol", value: proto, id: "diagnostics.pool.fallback.protocol")
                }
                if let tls = model.pool.fallbackTLS {
                    diagRow("Fallback TLS", value: tls ? "Enabled" : "Disabled", id: "diagnostics.pool.fallback.tls")
                }
                diagRow(
                    "Pool response time",
                    value: model.pool.responseTimeMs
                        .map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) ms" } ?? "Not reported",
                    id: "diagnostics.pool.responseTime"
                )
                if let batch = model.pool.responseShareBatch {
                    diagRow("Response share batch", value: "\(batch)", id: "diagnostics.pool.batch")
                }
                diagRow(
                    "Pool difficulty",
                    value: FleetFormat.difficulty(model.pool.poolDifficulty),
                    id: "diagnostics.pool.difficulty"
                )
                if let info = model.pool.poolConnectionInfo {
                    diagRow("Address family", value: info, id: "diagnostics.pool.connInfo")
                }
            }

            if !model.pool.rejectionReasons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rejection reasons:")
                        .fleetFont(.caption, weight: .medium)
                        .foregroundStyle(FleetTheme.ink)
                    ForEach(model.pool.rejectionReasons, id: \.self) { reason in
                        HStack {
                            Text("• \(reason.message)")
                                .fleetFont(.caption)
                                .foregroundStyle(FleetTheme.warning)
                            Spacer()
                            Text("(\(reason.count.formatted()))")
                                .fleetFont(.caption, design: .monospaced).monospacedDigit()
                                .foregroundStyle(FleetTheme.secondary)
                                .fleetNumericUpdate("(\(reason.count.formatted()))", reduceMotion: reduceMotion)
                        }
                    }
                }
                .padding(.top, 4)
                .accessibilityIdentifier("diagnostics.pool.rejectionReasons")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagnostics.section.pool")
    }

    // MARK: - System & Firmware

    private var systemAndFirmwareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("SYSTEM & FIRMWARE", symbol: "cpu")
            VStack(spacing: 7) {
                diagRow("Session uptime",
                    value: MinerDiagnosticsModel.formatDuration(model.system.sessionUptimeSeconds),
                    id: "diagnostics.system.sessionUptime")
                diagRow("Total uptime",
                    value: MinerDiagnosticsModel.formatDuration(model.system.totalUptimeSeconds),
                    id: "diagnostics.system.totalUptime")
                diagRow("Free heap",
                    value: MinerDiagnosticsModel.formatHeapBytes(model.system.freeHeapBytes),
                    id: "diagnostics.system.freeHeap")
                if let cpu = model.system.cpuUsagePercent {
                    diagRow("CPU usage",
                        value: MinerDiagnosticsModel.formatPercentage(cpu, decimals: 1),
                        id: "diagnostics.system.cpu")
                }
                if let reset = model.system.resetReason {
                    diagRow("Last reset reason", value: reset, id: "diagnostics.system.resetReason")
                }
                if let part = model.system.runningPartition {
                    diagRow("Running partition", value: part, id: "diagnostics.system.partition")
                }
                if let fw = model.system.firmwareVersion {
                    diagRow("Firmware version", value: fw, id: "diagnostics.system.firmware")
                }
                if let osVersion = model.system.axeOSVersion {
                    diagRow("AxeOS version", value: osVersion, id: "diagnostics.system.axeOS")
                }
                if let board = model.system.boardVersion {
                    diagRow("Board version", value: board, id: "diagnostics.system.board")
                }
                if let rssi = model.system.wifiRSSI {
                    diagRow("Wi-Fi signal",
                        value: "\(rssi.formatted(.number.precision(.fractionLength(0)))) dBm",
                        id: "diagnostics.system.wifiRSSI")
                }
                if let ssid = model.system.wifiSSID {
                    FleetSensitiveValue(
                        title: "Wi-Fi SSID",
                        value: ssid,
                        identifier: "diagnostics.system.wifiSSID"
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagnostics.section.system")
    }

    // MARK: - Common Row Builders

    func sectionHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .fleetFont(.caption2, weight: .bold)
            Text(title)
                .font(FleetTheme.mono(10))
                .tracking(1.5)
        }
        .foregroundStyle(FleetTheme.secondary)
        .padding(.bottom, 2)
    }

    func diagRow(_ title: String, value: String, id: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
            Spacer(minLength: 16)
            Text(value)
                .fleetFont(.caption)
                .monospacedDigit()
                .foregroundStyle(FleetTheme.ink)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .fleetNumericUpdate(value, reduceMotion: reduceMotion)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    func diagURLRow(_ title: String, value: String, id: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
            Spacer(minLength: 16)
            BrowserLink(label: value, rawValue: value, identifier: id, font: .caption, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("Diagnostics") {
    MinerDiagnosticsView(model: MinerDiagnosticsModel(info: MinerInfo(raw: [
        "hostname": .string("Workshop Gamma"),
        "hashrate": .number(1_220_000_000_000),
        "power": .number(19.2),
        "temp": .number(53),
        "fanrpm": .number(2_860),
        "freeHeap": .number(184_320),
        "version": .string("2.12.0")
    ])))
    .padding()
}
