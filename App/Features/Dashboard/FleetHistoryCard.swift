import SwiftUI
import Charts
import HashFleetCore

struct FleetHistoryCard: View {
    let devices: [MinerDevice]
    let snapshots: [UUID: MinerSnapshot]
    let isDemo: Bool
    let database: MinerTelemetryDatabase?
    let isMinerDetail: Bool
    let isCompactDashboard: Bool
    /// Miner detail only: a 24-hour uptime row rendered inside this card under the chart.
    var uptime: MinerUptimeHeatmap?
    /// The dashboard history card is a compact companion to the live hashrate card. Detail views
    /// still scale naturally through Dynamic Type, but the dashboard should not make the chart
    /// consume the height of a second hero card.
    @ScaledMetric(relativeTo: .body) var chartHeight: CGFloat = 92
    @ScaledMetric(relativeTo: .body) private var baseContentHeight: CGFloat = 112
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @State var selectedWindow: HistoryWindow = .daily
    @State var recentRange: FleetRecentRange
    @State private var selectedKind: FleetHistoryKind?
    @State var displayMode: FleetHistoryDisplay

    init(devices: [MinerDevice], snapshots: [UUID: MinerSnapshot], isDemo: Bool,
         initialDisplay: FleetHistoryDisplay = .fleet, initialRecentRange: FleetRecentRange = .hour,
         database: MinerTelemetryDatabase? = nil, isMinerDetail: Bool = false,
         isCompactDashboard: Bool = false, uptime: MinerUptimeHeatmap? = nil) {
        self.devices = devices
        self.snapshots = snapshots
        self.isDemo = isDemo
        self.database = database
        self.isMinerDetail = isMinerDetail
        self.isCompactDashboard = isCompactDashboard
        self.uptime = uptime
        _displayMode = State(initialValue: initialDisplay)
        _recentRange = State(initialValue: initialRecentRange)
        _isLoadingHistory = State(initialValue: !isDemo)
    }

    var isFleetView: Bool { displayMode == .fleet }

    /// Both dashboard and miner detail charts use the surrounding neutral theme roles. The
    /// top fleet summary remains the deliberately dark panel, so these cards stay distinct.
    var chartInk: Color { FleetTheme.ink }
    var chartSecondary: Color { FleetTheme.secondary }
    var chartAccent: Color { FleetTheme.accent }

    var effectiveChartHeight: CGFloat {
        if isMinerDetail { return chartHeight }
        return min(chartHeight, isCompactDashboard ? 56 : 64)
    }

    private var effectiveBaseContentHeight: CGFloat {
        if isMinerDetail { return baseContentHeight }
        return min(baseContentHeight, isCompactDashboard ? 72 : 80)
    }

    private var effectiveMeasuredPageHeight: CGFloat {
        guard !isMinerDetail else { return measuredPageHeight }
        let compactLimit = isCompactDashboard ? 72 : .greatestFiniteMagnitude
        return min(measuredPageHeight, compactLimit)
    }

    /// The website's miner detail page shows one chart directly below the reading. It does not
    /// repeat the per-miner summary or a one-item legend that is useful only in fleet breakdowns.
    var isSingleMinerDetail: Bool {
        isMinerDetail && !isFleetView && chartDevices.count == 1
    }

    var activeKind: FleetHistoryKind {
        let available = FleetHistoryKind.available(in: devices)
        return selectedKind.flatMap { available.contains($0) ? $0 : nil } ?? available.first ?? .sha256
    }

    var chartDevices: [MinerDevice] { activeKind.devices(in: devices) }
    @State var rawSelectedDate: Date?
    @State var isHistoryOptionsPresented = false
    @State private var measuredPageHeight: CGFloat = 0
    @State var databaseSeries: [UUID: [HashratePoint]] = [:]
    @State var databaseSeriesRevision = 0
    @State private var isLoadingHistory = false
    @State var pageDataCache = FleetHistoryPageCache()
    @State var recentRangeCache = FleetHistoryRangeCache()

    var rangeHeading: String { selectedWindow == .daily ? recentRange.rawValue : selectedWindow.heading }

    /// Tracks history boundaries and timestamps so capped buffer rollovers (e.g. at 360 points)
    /// are detected even when `points.count` remains constant.
    var historySignatures: [MinerHistorySignature] {
        devices.map { device in
            let snap = snapshots[device.id]
            return MinerHistorySignature(
                id: device.id,
                history: snap?.history ?? [],
                updatedAt: snap?.updatedAt
            )
        }
    }

    var body: some View {
        // The selected window's page data feeds both the header unit and its page. Resolving it
        // once per body pass avoids repeating the merge and fleet alignment for the same window.
        let selectedPage: PageData? = devices.isEmpty ? nil : pageData(for: selectedWindow)
        VStack(alignment: .leading, spacing: isMinerDetail ? 8 : 5) {
            VStack(alignment: .leading, spacing: isMinerDetail ? 5 : 3) {
                ViewThatFits(in: .horizontal) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            chartTitle.fixedSize()
                            Spacer(minLength: 0)
                            if !devices.isEmpty {
                                windowControls.fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        chartTitle
                        if !devices.isEmpty { windowControls }
                    }
                }
                if isMinerDetail || !isFleetView || dynamicTypeSize.isAccessibilitySize {
                    Text((isDemo ? "Simulated hashrate history" : "Recorded hashrate history") + " · \(activeKind.title)")
                        .fleetFont(.caption2)
                        .foregroundStyle(chartSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(rangeHeading) · \(displayUnit(forHistories: selectedPage?.histories ?? []).rawValue)")
                    .fleetFont(.caption2, design: .monospaced)
                    .foregroundStyle(chartSecondary)
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isHeader)

            if devices.isEmpty {
                emptyState
            } else {
                algorithmControls
                windowPager(selectedPage: selectedPage)
                if isLoadingHistory {
                    Text("Loading saved readings…").fleetFont(.caption2).foregroundStyle(chartSecondary)
                }
                if isMinerDetail && !isSingleMinerDetail {
                    Text(isFleetView ? "Complete samples · aligned within 30s · gaps stay visible." :
                         "Recorded samples only. Gaps over 5 minutes are not connected.")
                        .fleetFont(.caption2)
                        .foregroundStyle(chartSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let uptime {
                    Divider().overlay(FleetTheme.separator.opacity(0.5)).padding(.top, 4)
                    uptime
                }
            }
        }
        .fleetCard(
            padding: FleetSurfaceSpacing.cardInset,
            fill: FleetTheme.surface,
            border: isMinerDetail ? FleetTheme.controlBorder.opacity(0.35) : .clear,
            cornerRadius: isMinerDetail ? 24 : 16
        )
        .padding(.horizontal, 0)
        .onChange(of: activeKind) { _, _ in
            rawSelectedDate = nil
        }
        .onChange(of: selectedWindow) { _, _ in
            rawSelectedDate = nil
        }
        .onChange(of: displayMode) { _, _ in
            rawSelectedDate = nil
        }
        .onChange(of: recentRange) { _, _ in
            rawSelectedDate = nil
        }
        .onChange(of: historySignatures) { _, _ in
            validateSelection()
        }
        .task(id: FleetHistoryLoadIdentity(window: selectedWindow, devices: devices.map(\.id))) {
            await loadHistoricalData(for: selectedWindow)
        }
    }

    private var chartTitle: some View {
        Text("Hashrate trend")
            .fleetFont(.caption, weight: .semibold)
            .foregroundStyle(chartInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path")
                .fleetFont(.title)
                .foregroundStyle(chartAccent)
                .accessibilityHidden(true)
            Text("Your history will appear here over time.")
                .fleetFont(.subheadline, weight: .medium)
            Text("Readings appear here as your miners report in. Pull down to refresh.")
                .fleetFont(.footnote)
                .foregroundStyle(chartSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private func windowPager(selectedPage: PageData?) -> some View {
        Group {
            #if os(macOS)
            // Native Mac displays one page directly. Let its content determine its height,
            // rather than feeding its measured height back into its own frame. The fixed
            // height below exists only because the iOS paging TabView has no intrinsic height.
            periodPage(for: selectedWindow, selectedPage: selectedPage)
                .frame(minHeight: effectiveBaseContentHeight)
                .clipped()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("dashboard.historyWindow.\(selectedWindow.identifier)")
            #else
            TabView(selection: $selectedWindow) {
                ForEach(HistoryWindow.allCases) { window in
                    periodPage(for: window, selectedPage: window == selectedWindow ? selectedPage : nil)
                        .tag(window)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("dashboard.historyWindow.\(window.identifier)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Only the paging container needs a measured, explicit height. Do not attach this
            // state-writing preference observer to the native Mac page's layout graph.
            .frame(height: max(effectiveMeasuredPageHeight, effectiveBaseContentHeight))
            .onPreferenceChange(HistoryPageHeightPreferenceKey.self) { height in
                let rounded = height.rounded(.up)
                if rounded > 0, abs(rounded - measuredPageHeight) >= 1 {
                    measuredPageHeight = rounded
                }
            }
            #endif
        }
        // Disable parent page swiping while a point is actively selected/scrubbed to eliminate gesture conflict
        .scrollDisabled(rawSelectedDate != nil)
        .accessibilityLabel(
            (isDemo ? "Simulated" : "Recorded") +
                (isFleetView ? " fleet hashrate history" : " hashrate history by miner")
        )
        .accessibilityHint(FleetLayout.isMac
            ? "Choose a time range to switch daily, weekly, monthly, and yearly windows"
            : "Swipe to switch daily, weekly, monthly, and yearly windows")
    }

    @ViewBuilder
    private var algorithmControls: some View {
        let kinds = FleetHistoryKind.available(in: devices)
        if kinds.count > 1 {
            HStack(spacing: 8) {
                ForEach(kinds) { kind in
                    let selected = kind == activeKind
                    Button { selectedKind = kind } label: {
                        ZStack {
                            Text(kind.title)
                                .font(.system(
                                    size: dynamicTypeSize.isAccessibilitySize ? 14 : 10,
                                    weight: .semibold
                                ))
                                .fleetPillPadding()
                                .frame(minWidth: 44, minHeight: 44)
                                .foregroundStyle(selected ? chartAccent : chartSecondary)
                                .background(
                                    selected ? chartAccent.opacity(0.14) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                            .frame(minWidth: 44, minHeight: 44)
                            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("dashboard.historyKind.\(kind.rawValue)")
                }
            }
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(FleetTheme.raised)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Hashrate chart source")
        }
    }

    @ViewBuilder
    private func periodPage(for window: HistoryWindow, selectedPage: PageData?) -> some View {
        // TabView keeps neighboring pages alive for swipe navigation. Keep those pages as empty
        // shells so their charts, stored-history merges, and fleet alignment are not rebuilt on
        // every dashboard observation update. The selected page is recomputed when the binding
        // changes, preserving the existing swipe behavior without paying for four charts at once.
        if window == selectedWindow, let selectedPage {
            periodPageContent(for: window, page: selectedPage)
        } else {
            Color.clear
        }
    }

    private func periodPageContent(for window: HistoryWindow, page: PageData) -> some View {
        let histories = page.histories
        let activeSelection = selection(for: histories, window: window)

        return VStack(alignment: .leading, spacing: 8) {
            if activeSelection != nil || (!isFleetView && !isSingleMinerDetail) {
                periodHeader(for: window, histories: histories, selection: activeSelection)
            }

            if histories.isEmpty {
                if isLoadingHistory {
                    ProgressView("Loading saved readings…")
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    emptyWindow(for: window)
                }
            } else {
                historyChart(histories, window: window, selection: activeSelection, segments: page.segments)

                if histories.allSatisfy({ $0.points.count == 1 }) {
                    Text("The first readings are in. More samples will show the trend.")
                        .fleetFont(.caption)
                        .foregroundStyle(chartSecondary)
                }

                if !isFleetView && !isSingleMinerDetail {
                    historyLegend(for: histories, selection: activeSelection)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        #if !os(macOS)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HistoryPageHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        )
        #endif
    }

    private func emptyWindow(for window: HistoryWindow) -> some View {
        let missingAlignment = isFleetView && !minerSeries(for: window).isEmpty
        return VStack(spacing: 10) {
            Text(missingAlignment ? "No complete fleet samples in this window." : "No readings in this time window yet.")
                .fleetFont(.subheadline, weight: .medium)
            Text(
                missingAlignment ?
                    "Each miner needs a recorded reading within 30 seconds. Choose Individual miners to inspect available history." :
                    "Only this app's recorded readings are shown. " +
                    "Longer windows require stored telemetry; a range is not a retention promise."
            )
            .fleetFont(.caption)
            .foregroundStyle(chartSecondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private func selection(for histories: [MinerHistorySeries], window: HistoryWindow) -> FleetChartSelection? {
        guard let rawSelectedDate else {
            return nil
        }
        return FleetChartSelection.resolve(
            at: rawSelectedDate,
            in: histories,
            tolerance: window.selectionTolerance,
            clusterTolerance: 60
        )
    }

    private func validateSelection() {
        guard let raw = rawSelectedDate else { return }
        let currentSeries = series(for: selectedWindow)
        if !FleetChartSelection.isSelectionValid(
            at: raw,
            in: currentSeries,
            tolerance: selectedWindow.selectionTolerance
        ) {
            rawSelectedDate = nil
        }
    }

    func periodSummary(for histories: [MinerHistorySeries]) -> String? {
        FleetHistoryPresentation.meanReading(in: histories).map { FleetFormat.hashrateWithUnit($0) }
    }

    func displayUnit(for window: HistoryWindow) -> HashrateUnit {
        displayUnit(forHistories: series(for: window))
    }

    func displayUnit(forHistories histories: [MinerHistorySeries]) -> HashrateUnit {
        guard let maxGHs = histories.lazy.flatMap(\.points).map(\.value)
            .filter({ $0.isFinite && $0 >= 0 }).max() else {
            return activeKind == .cpu ? .hashesPerSecond : .gigaHashesPerSecond
        }
        return FleetFormat.hashrateDisplayUnit(forGHs: maxGHs)
    }

    func minerSeries(for window: HistoryWindow) -> [MinerHistorySeries] {
        let now = Date()
        let interval = window == .daily ? recentRange.interval : window.interval
        return chartDevices.compactMap { device in
            let sourceInterval = window == .daily
                ? max(interval, FleetRecentRange.day.interval)
                : interval
            let sourcePoints = FleetHistorySource.mergedPoints(
                stored: databaseSeries[device.id] ?? [],
                current: window == .daily ? snapshots[device.id]?.history ?? [] : [],
                since: now.addingTimeInterval(-sourceInterval),
                until: now
            )
            let anchor = window == .daily ? sourcePoints.last?.date ?? now : now
            let cutoff = anchor.addingTimeInterval(-interval)
            let points = sourcePoints.filter { $0.date >= cutoff && $0.date <= anchor }
            guard !points.isEmpty else { return nil }
            let duplicateName = devices.contains { $0.id != device.id && $0.name == device.name }
            let label = duplicateName ? "\(device.name) · \(device.address)" : device.name
            return MinerHistorySeries(id: device.id, name: label, points: points)
        }
    }

    private func loadHistoricalData(for window: HistoryWindow) async {
        guard !isDemo else {
            normalizeRecentRange()
            return
        }
        isLoadingHistory = true
        defer { if !Task.isCancelled { isLoadingHistory = false } }
        let now = Date()
        // Load the full recent day once. The 15m and 1h controls filter this local cache
        // rather than issuing new miner requests or discarding saved readings on relaunch.
        let results = await FleetHistorySource.load(
            devices: devices, since: now.addingTimeInterval(-window.interval), until: now, database: database ?? .shared
        )
        guard !Task.isCancelled else { return }
        databaseSeries = results
        databaseSeriesRevision += 1
        normalizeRecentRange()
    }
}
