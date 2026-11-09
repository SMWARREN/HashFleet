import SwiftUI
import HashFleetCore

/// Display inputs consumed by series labels and chart-kind membership.
struct FleetHistoryDeviceMetadata: Equatable, Sendable {
    let id: UUID
    let name: String
    let address: String
    let kind: MinerDevice.Kind
}

struct FleetHistoryPageIdentity: Equatable {
    let window: HistoryWindow
    let recentRange: FleetRecentRange
    let displayMode: FleetHistoryDisplay
    let kind: FleetHistoryKind
    let currentSignatures: [MinerHistorySignature]
    let storedSignatures: [MinerHistorySignature]
    let storedRevision: Int
    let deviceMetadata: [FleetHistoryDeviceMetadata]
}

final class FleetHistoryPageCache {
    private var identity: FleetHistoryPageIdentity?
    private var value: FleetHistoryCard.PageData?

    func resolve(
        _ identity: FleetHistoryPageIdentity,
        make: () -> FleetHistoryCard.PageData
    ) -> FleetHistoryCard.PageData {
        if self.identity == identity, let value { return value }
        let value = make()
        self.identity = identity
        self.value = value
        return value
    }
}

struct FleetHistoryRangeIdentity: Equatable {
    let kind: FleetHistoryKind
    let currentSignatures: [MinerHistorySignature]
    let storedSignatures: [MinerHistorySignature]
    let storedRevision: Int
}

/// Range controls can be evaluated many times during one native layout/navigation update.
/// Reuse their derived data without observing or mutating SwiftUI state during body evaluation.
final class FleetHistoryRangeCache {
    private var identity: FleetHistoryRangeIdentity?
    private var resolvedAt = Date.distantFuture
    private var expiration = Date.distantPast
    private var ranges: [FleetRecentRange] = []

    func resolve(
        _ identity: FleetHistoryRangeIdentity, now: Date,
        make: () -> (ranges: [FleetRecentRange], expiration: Date)
    ) -> [FleetRecentRange] {
        if self.identity == identity, now >= resolvedAt, now < expiration { return ranges }
        let result = make()
        self.identity = identity
        resolvedAt = now
        expiration = result.expiration
        ranges = result.ranges
        return ranges
    }
}

extension FleetHistoryCard {
    /// Resolves the complete data needed by one history page in one page-body pass.
    /// The chart previously called `minerSeries` and fleet alignment again while building its
    /// segments, then repeated both operations for the same page's `series` and chart content.
    /// Keeping the paired result together avoids rebuilding the O(points × miners) aggregation
    /// while preserving the existing recorded-data and missing-sample rules.
    typealias PageData = (histories: [MinerHistorySeries], segments: [FleetHistorySegment]?)

    func pageData(for window: HistoryWindow) -> PageData {
        pageData(for: window, cache: pageDataCache)
    }

    /// Keeps cache resolution testable across view value copies without changing installed state.
    func pageData(for window: HistoryWindow, cache: FleetHistoryPageCache) -> PageData {
        cache.resolve(pageDataIdentity(for: window)) {
            buildPageData(for: window)
        }
    }

    private func pageDataIdentity(for window: HistoryWindow) -> FleetHistoryPageIdentity {
        FleetHistoryPageIdentity(
            window: window,
            recentRange: recentRange,
            displayMode: displayMode,
            kind: activeKind,
            currentSignatures: historySignatures,
            storedSignatures: devices.map {
                MinerHistorySignature(id: $0.id, history: databaseSeries[$0.id] ?? [])
            },
            storedRevision: databaseSeriesRevision,
            deviceMetadata: devices.map {
                FleetHistoryDeviceMetadata(id: $0.id, name: $0.name, address: $0.address, kind: $0.kind)
            }
        )
    }

    private func buildPageData(for window: HistoryWindow) -> PageData {
        let minerHistories = minerSeries(for: window)
        guard isFleetView else { return (minerHistories, nil) }

        let segments = FleetHistoryAggregation.segments(
            histories: minerHistories, expectedIDs: chartDevices.map(\.id)
        )
        let points = segments.flatMap(\.points)
        guard !points.isEmpty, let first = chartDevices.first else {
            return ([], segments)
        }
        let name = chartDevices.count == 1 ? first.name :
            (first.kind == .xmrig ? "CPU fleet" : "SHA-256 fleet")
        return ([MinerHistorySeries(id: first.id, name: name, points: points)], segments)
    }

    @ViewBuilder
    var windowControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                recentRangeButtons
                historyDisplayControl
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(FleetTheme.raised))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("History time range")
            .accessibilityIdentifier("dashboard.historyRanges")
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    recentRangeButtons
                    historyDisplayControl
                }
                .fixedSize(horizontal: true, vertical: false)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    recentRangeButtons
                    historyDisplayControl
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(FleetTheme.raised))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("History time range")
            .accessibilityIdentifier("dashboard.historyRanges")
        }
    }

    private var recentRangeButtons: some View {
        ForEach(visibleRecentRanges, id: \.self) { range in
            let selected = selectedWindow == .daily && recentRange == range
            Button {
                recentRange = range
                selectedWindow = .daily
            } label: {
                ZStack {
                    Text(range.rawValue)
                        .font(.system(
                            size: dynamicTypeSize.isAccessibilitySize ? 14 : 10,
                            weight: .semibold,
                            design: .monospaced
                        ))
                        .foregroundStyle(selected ? chartAccent : chartSecondary)
                        .fleetPillPadding()
                        .frame(minWidth: 44, minHeight: 44)
                        .background(selected ? chartAccent.opacity(0.14) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                    .frame(minWidth: 44, minHeight: 44)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(range.rawValue) history")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("dashboard.historyRange.\(range.identifier)")
        }
    }

    /// Start with the one-minute view, then reveal longer windows as local readings or saved logs
    /// cover them. This keeps a new session from opening on an empty 15-minute or day chart.
    private var visibleRecentRanges: [FleetRecentRange] {
        let now = Date()
        let identity = FleetHistoryRangeIdentity(
            kind: activeKind,
            currentSignatures: historySignatures,
            storedSignatures: devices.map {
                MinerHistorySignature(id: $0.id, history: databaseSeries[$0.id] ?? [])
            },
            storedRevision: databaseSeriesRevision
        )
        return recentRangeCache.resolve(identity, now: now) {
            let points = chartDevices.flatMap { device in
                FleetHistorySource.mergedPoints(
                    stored: databaseSeries[device.id] ?? [],
                    current: snapshots[device.id]?.history ?? [],
                    since: now.addingTimeInterval(-FleetRecentRange.day.interval),
                    until: now
                )
            }
            let sources = chartDevices.flatMap { device in
                [databaseSeries[device.id] ?? [], snapshots[device.id]?.history ?? []]
            }
            return (
                FleetHistoryPresentation.availableRecentRanges(for: points, now: now),
                FleetHistorySource.recentRangeExpiration(sources: sources, now: now)
            )
        }
    }

    func normalizeRecentRange() {
        let available = visibleRecentRanges
        guard let fallback = available.last, !available.contains(recentRange) else { return }
        recentRange = fallback
    }

    @ViewBuilder
    var historyDisplayControl: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Button { isHistoryOptionsPresented = true } label: {
                historyDisplayLabel
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: $isHistoryOptionsPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                historyOptionsPanel
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel("Chart view and longer history")
            .accessibilityValue(displayMode.title)
            .accessibilityIdentifier("dashboard.historyDisplay")
        } else {
            Menu {
                historyOptionsMenu
            } label: {
                historyDisplayLabel
            }
            .fleetDesignedMenu()
            .accessibilityLabel("Chart view and longer history")
            .accessibilityValue(displayMode.title)
            .accessibilityIdentifier("dashboard.historyDisplay")
        }
    }

    private var historyDisplayLabel: some View {
        ZStack {
            Image(systemName: "ellipsis")
                .font(.system(
                    size: dynamicTypeSize.isAccessibilitySize ? 14 : 11,
                    weight: .semibold
                ))
                .fleetPillPadding()
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(selectedWindow == .daily ? chartSecondary : chartAccent)
                .background(
                    selectedWindow == .daily ? Color.clear : chartAccent.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
            .frame(minWidth: 44, minHeight: 44)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var historyOptionsMenu: some View {
        if chartDevices.count > 1 {
            Picker("Chart view", selection: $displayMode) {
                ForEach(FleetHistoryDisplay.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        }
        Section("Saved history") {
            ForEach(HistoryWindow.allCases.filter { $0 != .daily }, id: \.id) { window in
                let selected = selectedWindow == window
                Button { selectedWindow = window } label: {
                    Label("\(window.heading) history", systemImage: selected ? "checkmark" : "clock")
                }
                .accessibilityIdentifier("dashboard.historyRange.\(window.identifier)")
            }
        }
    }

    private var historyOptionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if chartDevices.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chart view")
                        .fleetFont(.headline)
                    Picker("Chart view", selection: $displayMode) {
                        ForEach(FleetHistoryDisplay.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Divider()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Saved history")
                    .fleetFont(.headline)
                ForEach(HistoryWindow.allCases.filter { $0 != .daily }, id: \.id) { window in
                    let selected = selectedWindow == window
                    Button {
                        selectedWindow = window
                        isHistoryOptionsPresented = false
                    } label: {
                        Label("\(window.heading) history", systemImage: selected ? "checkmark" : "clock")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dashboard.historyRange.\(window.identifier)")
                }
            }
        }
        .padding()
        .frame(minWidth: 230)
    }

    func chartSegments(for window: HistoryWindow) -> [FleetHistorySegment]? {
        pageData(for: window).segments
    }

    func series(for window: HistoryWindow) -> [MinerHistorySeries] {
        pageData(for: window).histories
    }
}
