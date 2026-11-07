import SwiftUI
import HashFleetCore

/// Read-only ASIC domain readings and pool selection diagnostics for the current real snapshot.
struct FirmwareTelemetryView: View {
    let info: MinerInfo
    let observedAt: Date?
    let minerIdentity: String
    let isCached: Bool
    let error: String?
    let isReconnecting: Bool
    let freshness: MinerSnapshotFreshness?

    @State private var history = FirmwareTelemetryHistory()
    @State private var isDomainsExpanded: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        info: MinerInfo,
        observedAt: Date?,
        minerIdentity: String,
        isCached: Bool,
        error: String?,
        isReconnecting: Bool,
        freshness: MinerSnapshotFreshness?,
        initiallyExpanded: Bool = false
    ) {
        self.info = info
        self.observedAt = observedAt
        self.minerIdentity = minerIdentity
        self.isCached = isCached
        self.error = error
        self.isReconnecting = isReconnecting
        self.freshness = freshness
        _isDomainsExpanded = State(initialValue: initiallyExpanded)
    }

    private var domains: [FirmwareTelemetryDomainSample] {
        info.hashrateDomains.compactMap { item -> FirmwareTelemetryDomainSample? in
            guard item.chipIndex >= 0, item.domainIndex >= 0,
                  item.hashrateGHs.isFinite, item.hashrateGHs >= 0 else { return nil }
            return FirmwareTelemetryDomainSample(
                chipIndex: item.chipIndex,
                domainIndex: item.domainIndex,
                hashrateGHs: item.hashrateGHs,
                nominalHashrateGHs: item.nominalHashrateGHs.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            )
        }.sorted {
            $0.chipIndex == $1.chipIndex
                ? $0.domainIndex < $1.domainIndex
                : $0.chipIndex < $1.chipIndex
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isRetained {
                Text(isReconnecting ? "Refreshing. The readings below are retained." : "The readings below are retained from the last available snapshot.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup(isExpanded: $isDomainsExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if domains.isEmpty {
                        Label("Per-ASIC domain telemetry is not reported by this firmware.", systemImage: "info.circle")
                            .fleetFont(.footnote)
                            .foregroundStyle(FleetTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("detail.asicTelemetry.unsupported")
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            FirmwareTelemetryGridLayout(
                                accessibilitySize: dynamicTypeSize.isAccessibilitySize
                            ) {
                                ForEach(domains) { domain in
                                    domainRow(domain)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("ASIC chip and domain readings")
                        .accessibilityIdentifier("detail.asicTelemetry.grid")
                        Text(
                            "Ordered observed samples: left is older, right is newer. " +
                            "History stays on this screen and resets when miner identity, " +
                            "firmware, uptime session, or domain layout changes."
                        )
                            .fleetFont(.caption2)
                            .foregroundStyle(FleetTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label(isRetained ? "Last known ASIC hashrate" : "ASIC hashrate", systemImage: "cpu")
                        .fleetFont(.headline)
                        .foregroundStyle(FleetTheme.ink)
                    Text(domains.isEmpty
                         ? "Per-domain readings are not reported"
                         : "\(domains.count) chip-domain readings · observed GH/s")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(isDomainsExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Shows read-only ASIC chip and domain hashrate readings")
                .accessibilityIdentifier("detail.asicTelemetry.disclosure")
            }
            Divider()
            poolStatus.accessibilityElement(children: .contain)
                .accessibilityIdentifier("detail.poolDiagnostics")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.firmwareTelemetry")
        .onAppear { recordCurrentSnapshot() }
        .onChange(of: observedAt) { _, _ in recordCurrentSnapshot() }
        .onChange(of: isCached) { _, _ in recordCurrentSnapshot() }
        .onChange(of: error) { _, _ in recordCurrentSnapshot() }
        .onChange(of: isReconnecting) { _, _ in recordCurrentSnapshot() }
    }

    private func domainRow(_ domain: FirmwareTelemetryDomainSample) -> some View {
        let label = "Chip \(domain.chipIndex + 1), domain \(domain.domainIndex + 1)"
        let nominal = domain.nominalHashrateGHs
        let values = history.samples.compactMap { $0.values[domain.id] }
        return VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    domainLabel(label)
                    domainReading(domain.hashrateGHs)
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 6) {
                    domainLabel(label)
                    domainReading(domain.hashrateGHs)
                }
            }
            if let nominal, nominal.isFinite, nominal > 0 {
                let percentage = (domain.hashrateGHs / nominal * 100)
                    .formatted(.number.precision(.fractionLength(0)))
                let reference = "Nominal \(FleetFormat.measurement(nominal, unit: "GH/s", decimals: 1))"
                ViewThatFits(in: .horizontal) {
                    Text("\(reference) · \(percentage)% of nominal")
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reference)
                        Text("\(percentage)% of nominal")
                    }
                }
                .fleetFont(.caption2)
                .foregroundStyle(FleetTheme.secondary)
            } else {
                Text("Nominal reference not reported")
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
            }
            FirmwareTelemetrySparkline(
                values: values,
                nominal: domain.nominalHashrateGHs
            )
                .frame(height: 64)
                .accessibilityLabel("Observed hashrate history for \(label)" + (nominal == nil ? "" : ". Dashed line shows nominal hashrate"))
                .accessibilityValue("\(values.count) observed samples. " + (values.last.map { FleetFormat.measurement($0, unit: "GH/s", decimals: 1) } ?? "No history"))
                .accessibilityIdentifier("detail.asicGraph.\(domain.chipIndex).\(domain.domainIndex)")
            Text(values.isEmpty ? "Waiting for fresh readings" : (values.count == 1 ? "1 sample · building trend" : "\(values.count) observed samples"))
                .fleetFont(.caption2)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.asicDomain.\(domain.chipIndex).\(domain.domainIndex)")
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FleetTheme.raised, in: Rectangle())
        .overlay(Rectangle().strokeBorder(FleetTheme.separator.opacity(0.4), lineWidth: 0.75))
    }

    private func domainLabel(_ label: String) -> some View {
        Text(label)
            .fleetFont(.subheadline, weight: .semibold)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func domainReading(_ value: Double) -> some View {
        Text(FleetFormat.measurement(value, unit: "GH/s", decimals: 1))
            .fleetFont(.caption, weight: .semibold, design: .monospaced)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    private var poolStatus: some View {
        let diagnostics = MinerPoolDiagnostics(info: info)
        return VStack(alignment: .leading, spacing: 7) {
            Label("Pool connection", systemImage: "server.rack")
                .fleetFont(.subheadline, weight: .semibold)
            if let banner = diagnostics.banner, !banner.isEmpty {
                Text(banner).fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("detail.poolDiagnostics.banner")
            }
            if let error = diagnostics.primaryError, !error.isEmpty {
                LabeledContent("Primary pool issue", value: error)
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("detail.poolDiagnostics.primaryError")
            }
            HStack(spacing: 8) {
                Text(fallbackLabel(diagnostics.usingFallback))
                    .fleetFont(.caption, weight: .medium)
                    .foregroundStyle(diagnostics.usingFallback == true ? FleetTheme.warning : FleetTheme.secondary)
                Spacer(minLength: 4)
                Text(diagnostics.transportLabel)
                    .fleetFont(.caption2, design: .monospaced)
                    .foregroundStyle(FleetTheme.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail.poolDiagnostics.transport")
        }
    }

    private func fallbackLabel(_ usingFallback: Bool?) -> String {
        switch usingFallback {
        case true: "Using fallback pool"
        case false: "Primary pool selected"
        case nil: "Active pool not reported"
        }
    }

    private var isRetained: Bool {
        isCached || error != nil || isReconnecting || freshness?.isStale == true
    }

    private func recordCurrentSnapshot() {
        guard FirmwareTelemetryHistory.mayRecordSample(
            observedAt: observedAt,
            isCached: isCached,
            hasError: error != nil,
            isReconnecting: isReconnecting,
            isStale: freshness?.isStale == true
        ), let observedAt else { return }
        history.record(
            domains: domains,
            observedAt: observedAt,
            identity: "\(minerIdentity)|\(info.macAddress)",
            firmware: info.version.isEmpty ? nil : info.version,
            uptimeSeconds: info.raw["uptimeSeconds"]?.intValue
        )
    }
}

enum FirmwareTelemetryGridMetrics {
    static let minimumTileWidth: CGFloat = 156
    static let spacing: CGFloat = 12
    static let maximumColumns = 4

    static func columnCount(availableWidth: CGFloat, accessibilitySize: Bool) -> Int {
        guard !accessibilitySize, availableWidth.isFinite else { return 1 }
        let usableWidth = max(availableWidth, 0)
        let count = Int((usableWidth + spacing) / (minimumTileWidth + spacing))
        return min(maximumColumns, max(1, count))
    }
}

private struct FirmwareTelemetryGridLayout: Layout {
    let accessibilitySize: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let naturalWidth = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? naturalWidth
        let width = max(proposedWidth.isFinite ? proposedWidth : 1, 1)
        let columns = FirmwareTelemetryGridMetrics.columnCount(
            availableWidth: width, accessibilitySize: accessibilitySize
        )
        let tileWidth = (width - CGFloat(columns - 1) * FirmwareTelemetryGridMetrics.spacing) / CGFloat(columns)
        let rowHeights = stride(from: 0, to: subviews.count, by: columns).map { start in
            (start..<min(start + columns, subviews.count)).map { index in
                subviews[index].sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height
            }.max() ?? 0
        }
        let height = rowHeights.reduce(0, +)
            + CGFloat(max(0, rowHeights.count - 1)) * FirmwareTelemetryGridMetrics.spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let columns = FirmwareTelemetryGridMetrics.columnCount(
            availableWidth: bounds.width, accessibilitySize: accessibilitySize
        )
        let tileWidth = (bounds.width - CGFloat(columns - 1) * FirmwareTelemetryGridMetrics.spacing) / CGFloat(columns)
        var y = bounds.minY
        for start in stride(from: 0, to: subviews.count, by: columns) {
            let row = start..<min(start + columns, subviews.count)
            let rowHeights = row.map { index in
                subviews[index].sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height
            }
            let rowHeight = rowHeights.max() ?? 0
            for (offset, index) in row.enumerated() {
                let x = bounds.minX + CGFloat(offset) * (tileWidth + FirmwareTelemetryGridMetrics.spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: tileWidth, height: rowHeight)
                )
            }
            y += rowHeight + FirmwareTelemetryGridMetrics.spacing
        }
    }
}
