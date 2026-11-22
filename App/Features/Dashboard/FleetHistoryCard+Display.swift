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
    @ViewBuilder var numberFirstChartControls: some View {
        if numberFirstUsesRangeMenu {
            VStack(alignment: .leading, spacing: 4) {
                numberFirstRangeBar(columns: 2) {
                    essentialsRangeMenu
                    historyControlsButton
                }
                if showsHistoryControls { savedHistoryOptions }
            }
        } else {
            numberFirstRangeBar(columns: min(3, visibleRecentRanges.count + 1)) {
                recentRangeButtons
                historyDisplayControl
            }
        }
    }

    /// Keep the native button and menu semantics. The segmented style is only the bar that holds them.
    private func numberFirstRangeBar<Controls: View>(
        columns: Int, @ViewBuilder controls: () -> Controls
    ) -> some View {
        let tracks = Array(repeating: GridItem(.flexible(minimum: 44), spacing: 0), count: columns)
        return LazyVGrid(columns: tracks, spacing: 0, content: controls)
            .frame(maxWidth: .infinity)
            .background {
                if numberFirstHasSingleRangeRow {
                    Capsule().fill(FleetTheme.raised).frame(height: numberFirstRangeRailHeight)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Hashrate chart controls")
            .accessibilityIdentifier("dashboard.historyRanges")
    }

    // When additional recent ranges need two rows, draw each capsule on its own button
    // rather than painting one tall block behind the whole grid.
    private var numberFirstUsesRangeMenu: Bool { isEssentials || (isMinerDetail && selectedMetric != .hashrate) }
    private var numberFirstHasSingleRangeRow: Bool { numberFirstUsesRangeMenu || visibleRecentRanges.count < 3 }
    private var numberFirstRangeRailHeight: CGFloat { 24 }

    private func numberFirstSegment(_ title: String, selected: Bool, symbol: String? = nil,
                                    compactTitle: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let compactTitle {
                ViewThatFits(in: .horizontal) {
                    Text(title).fixedSize(horizontal: true, vertical: false)
                    Text(compactTitle)
                }
            } else {
                Text(title)
            }
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
        }
        .fleetFont(.caption, weight: selected ? .semibold : .medium)
        .dynamicTypeSize(numberFirstChartLabelSize)
        .foregroundStyle(selected ? chartInk : chartSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, minHeight: numberFirstRangeRailHeight)
        .background {
            if selected { Capsule().fill(chartInk.opacity(0.13)).padding(2) }
        }
        .background {
            if !numberFirstHasSingleRangeRow {
                Capsule().fill(FleetTheme.raised).padding(.horizontal, 2)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }

    var essentialsHistoryControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    essentialsRangeMenu.fixedSize(horizontal: true, vertical: false)
                    historyControlsButton.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 0) {
                    essentialsRangeMenu
                    historyControlsButton
                }
            }
            if showsHistoryControls { savedHistoryOptions }
        }
    }

    private var savedHistoryOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if chartDevices.count > 1 {
                FleetSettingsPicker(
                    "Chart view", valueTitle: displayMode.title, selection: $displayMode
                ) {
                    ForEach(FleetHistoryDisplay.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .accessibilityIdentifier("dashboard.historyCompare")
            }
            Text("Saved history")
                .fleetFont(.caption, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            ForEach(HistoryWindow.allCases.filter { $0 != .daily }) { window in
                let selected = window == selectedWindow
                Button { selectedWindow = window } label: {
                    Label(window.rangeTitle, systemImage: selected ? "checkmark" : "clock")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("dashboard.historyRange.\(window.identifier)")
            }
        }
        .fleetFont(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private var essentialsRangeMenu: some View {
        Menu {
            ForEach(selectedMetric == .hashrate ? visibleRecentRanges : FleetRecentRange.allCases) { range in
                let selected = selectedWindow == .daily && range == recentRange
                Button {
                    recentRange = range
                    selectedWindow = .daily
                    if numberFirst { showsHistoryControls = false }
                } label: {
                    Label(range.rangeTitle, systemImage: selected ? "checkmark" : "clock")
                }
                .accessibilityIdentifier("dashboard.historyRange.\(range.identifier)")
            }
        } label: {
            if numberFirst {
                numberFirstSegment(recentRange.rangeTitle, selected: !numberFirstHistorySelected,
                                   symbol: "chevron.down", compactTitle: recentRange.rawValue)
            } else {
                Label(isMinerDetail ? rangeTitle : "Range: \(rangeTitle)", systemImage: "clock")
                    .fleetFont(.subheadline, weight: .semibold)
                    .foregroundStyle(chartInk)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 10)
                    .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .fleetDesignedMenu()
        .accessibilityLabel("History time range")
        .accessibilityValue(numberFirst ? recentRange.rangeTitle : rangeTitle)
        .accessibilityAddTraits(numberFirst && !numberFirstHistorySelected ? .isSelected : [])
        .accessibilityIdentifier("dashboard.historyRangeMenu")
    }

    private var historyControlsButton: some View {
        let title = showsHistoryControls ? "Hide history options" : (isMinerDetail ? "View history" : "History options")
        return Button { showsHistoryControls.toggle() } label: {
            if numberFirst {
                numberFirstSegment("History", selected: numberFirstHistorySelected,
                                   symbol: showsHistoryControls ? "chevron.up" : (selectedWindow != .daily ? "checkmark" : "chevron.down"))
            } else {
                Label(title, systemImage: showsHistoryControls ? "chevron.up" : "chevron.down")
                    .fleetFont(.subheadline, weight: .semibold)
                    .foregroundStyle(chartAccent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(showsHistoryControls ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(numberFirst && numberFirstHistorySelected ? .isSelected : [])
        .accessibilityHint("Longer ranges and, when available, miner comparisons.")
        .accessibilityIdentifier("dashboard.viewHistory")
    }

    private var numberFirstHistorySelected: Bool { selectedWindow != .daily || showsHistoryControls }

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
                if numberFirst {
                    numberFirstSegment(range.rawValue, selected: selected, symbol: selected ? "checkmark" : nil)
                } else {
                    ZStack {
                        recentRangeText(range)
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel(numberFirst ? range.rangeTitle : "\(range.rawValue) history")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("dashboard.historyRange.\(range.identifier)")
        }
    }

    @ViewBuilder
    private func recentRangeText(_ range: FleetRecentRange) -> some View {
        if isMinerDetail {
            Text(range.rawValue)
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 14 : 10,
                              weight: .semibold, design: .monospaced))
        } else {
            Text(range.rawValue).fleetFont(.footnote, weight: .semibold)
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
        if prefersHistoryPopover || dynamicTypeSize.isAccessibilitySize {
            Button { isHistoryOptionsPresented = true } label: {
                historyDisplayLabel
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: $isHistoryOptionsPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: numberFirst ? nil : .bottom
            ) {
                historyOptionsPopoverContent
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel(historyDisplayAccessibilityLabel)
            .accessibilityValue(historyDisplayValue)
            .accessibilityAddTraits(numberFirst && selectedWindow != .daily ? .isSelected : [])
            .accessibilityIdentifier("dashboard.historyDisplay")
        } else {
            Menu {
                historyOptionsMenu
            } label: {
                historyDisplayLabel
            }
            .fleetDesignedMenu()
            .accessibilityLabel(historyDisplayAccessibilityLabel)
            .accessibilityValue(historyDisplayValue)
            .accessibilityAddTraits(numberFirst && selectedWindow != .daily ? .isSelected : [])
            .accessibilityIdentifier("dashboard.historyDisplay")
        }
    }

    private var historyDisplayValue: String {
        if numberFirst && isMinerDetail { return rangeTitle }
        return numberFirst && selectedWindow != .daily ? "\(selectedWindow.rangeTitle), \(displayMode.title)" : displayMode.title
    }

    private var historyDisplayAccessibilityLabel: String {
        numberFirst && isMinerDetail ? "Longer history" : "Chart view and longer history"
    }

    @ViewBuilder private var historyDisplayLabel: some View {
        if numberFirst {
            let selected = selectedWindow != .daily
            numberFirstSegment("History", selected: selected, symbol: selected ? "checkmark" : "chevron.down")
        } else {
            originalHistoryDisplayLabel
        }
    }

    private var originalHistoryDisplayLabel: some View {
        ZStack {
            Group {
                if isMinerDetail {
                    Image(systemName: "ellipsis")
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 14 : 11, weight: .semibold))
                } else {
                    Text(selectedWindow == .daily ? "History" : selectedWindow.rangeTitle)
                        .fleetFont(.footnote, weight: .semibold)
                }
            }
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

    @ViewBuilder
    private var historyOptionsPopoverContent: some View {
        if numberFirst {
            ViewThatFits(in: .vertical) {
                historyOptionsPanel.fixedSize(horizontal: false, vertical: true)
                ScrollView { historyOptionsPanel }
            }
            // The popover hosts a separate presentation. Reuse the preview's effective
            // text size here so the same viewport can accommodate the saved ranges.
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        } else {
            historyOptionsPanel
        }
    }

    private var historyOptionsPanel: some View {
        VStack(alignment: .leading, spacing: numberFirst ? 4 : 12) {
            if chartDevices.count > 1 {
                if numberFirst {
                    previewHistoryDisplayChoices
                } else {
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
                }
                Divider()
            }
            VStack(alignment: .leading, spacing: numberFirst ? 2 : 6) {
                Text("Saved history")
                    .fleetFont(numberFirst ? .footnote : .headline, weight: .semibold)
                ForEach(HistoryWindow.allCases.filter { $0 != .daily }, id: \.id) { window in
                    let selected = selectedWindow == window
                    Button {
                        selectedWindow = window
                        isHistoryOptionsPresented = false
                    } label: {
                        let title = Label("\(window.heading) history", systemImage: selected ? "checkmark" : "clock")
                        if numberFirst {
                            title.fleetFont(.subheadline)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        } else {
                            title.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(numberFirst && selected ? .isSelected : [])
                    .accessibilityIdentifier("dashboard.historyRange.\(window.identifier)")
                }
            }
        }
        .padding(.all, numberFirst ? 10 : nil)
        .frame(minWidth: numberFirst ? 260 : 230)
    }
    private var previewHistoryDisplayChoices: some View {
        HStack(spacing: 4) {
            ForEach(FleetHistoryDisplay.allCases, id: \.self) { mode in
                let selected = displayMode == mode
                Button { displayMode = mode } label: {
                    Text(mode.title)
                        .fleetFont(.footnote, weight: .semibold)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(selected ? chartInk : chartSecondary)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 44, minHeight: numberFirstRangeRailHeight)
                        .background {
                            if selected { Capsule().fill(chartInk.opacity(0.13)) }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart view")
    }
    func chartSegments(for window: HistoryWindow) -> [FleetHistorySegment]? {
        pageData(for: window).segments
    }
    func series(for window: HistoryWindow) -> [MinerHistorySeries] {
        pageData(for: window).histories
    }
}
