import SwiftUI
import Charts
import HashFleetCore

/// Chart construction and scrub interaction for FleetHistoryCard.
extension FleetHistoryCard {
    func historyChart(
        _ histories: [MinerHistorySeries],
        window: HistoryWindow,
        selection: FleetChartSelection?,
        segments: [FleetHistorySegment]? = nil
    ) -> some View {
        let pointBudget = isMinerDetail
            ? FleetHistoryPresentation.detailChartPointBudget
            : FleetHistoryPresentation.dashboardChartPointBudget
        let chartSeries = histories.map { history in
            FleetHistoryChartSeries(
                history: history, segments: segments, maximumCount: pointBudget
            )
        }
        let chartHistories = chartSeries.map(\.history)
        let maxGHs = histories.lazy.flatMap(\.points).map(\.value)
            .filter { $0.isFinite && $0 >= 0 }
            .max() ?? 0
        let displayUnit = FleetFormat.hashrateDisplayUnit(forGHs: maxGHs)
        let plottedPoints = chartHistories.flatMap(\.points)
        let yDomain = FleetHistoryPresentation.focusedYDomain(
            for: plottedPoints.map { displayUnit.value(fromGHs: $0.value) }
        ) ?? 0...1

        return Chart {
            historyMarks(chartSeries, unit: displayUnit)
            if let selection {
                selectionMarks(selection, unit: displayUnit)
            }
        }
        // Selection is owned by the overlay below. Keeping Swift Charts' built-in x-selection
        // recognizer active at the same time creates two competing state writers on iPad and can
        // trip an internal Charts dictionary assertion while the chart is redrawn.
        .chartXScale(range: .plotDimension(startPadding: 16, endPadding: 24))
        .chartYScale(domain: yDomain)
        // A focused domain can exclude zero, while AreaMark still draws toward its zero
        // baseline. Contain those marks in the shared plot instead of relying on an iOS
        // page container to clip them. The native Mac pager has no implicit UIKit mask.
        .chartPlotStyle { plot in plot.clipped() }
        .chartForegroundStyleScale(range: FleetChartPalette.colors)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: window.axisFormat)
                    .foregroundStyle(chartSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(FleetTheme.separator.opacity(isFleetView ? 0.45 : 0.7))
                AxisValueLabel()
                    .foregroundStyle(chartSecondary)
            }
        }
        .chartLegend(.hidden)
        .frame(height: effectiveChartHeight)
        .chartOverlay { proxy in
            chartHitOverlay(
                selection: selection,
                proxy: proxy,
                histories: histories,
                window: window
            )
        }
        .accessibilityChartDescriptor(
            FleetAXChartDescriptorProvider(series: chartHistories, windowHeading: window.heading, isDemo: isDemo)
        )
        // Swift Charts does not consistently expose a node when only a custom overlay owns
        // selection on iPad. Keep one stable chart surface for VoiceOver and UI automation,
        // while the overlay continues to receive the actual tap and drag gestures.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFleetView ?
            (isDemo ? "Simulated fleet hashrate history" : "Recorded fleet hashrate history") :
            (isDemo ? "Simulated hashrate history by miner" : "Recorded hashrate history by miner"))
        .accessibilityValue(chartAccessibilityValue(for: histories, selection: selection))
        .accessibilityIdentifier("dashboard.historyChart")
    }

    @ChartContentBuilder
    private func historyMarks(
        _ series: [FleetHistoryChartSeries],
        unit: HashrateUnit
    ) -> some ChartContent {
        ForEach(series) { item in
            ForEach(item.segments) { segment in
                segmentMarks(item.history, segment: segment, unit: unit, showsArea: series.count == 1)
            }
        }
    }

    @ChartContentBuilder
    private func segmentMarks(
        _ history: MinerHistorySeries,
        segment: FleetHistorySegment,
        unit: HashrateUnit,
        showsArea: Bool
    ) -> some ChartContent {
        ForEach(segment.points) { point in
            let value = unit.value(fromGHs: point.value)
            let segmentID = "\(history.id.uuidString).\(segment.id)"
            if showsArea {
                AreaMark(
                    x: .value("Time", point.date), y: .value("Hashrate", value),
                    series: .value("Recorded interval", segmentID), stacking: .unstacked
                )
                .foregroundStyle(LinearGradient(
                    colors: [chartInk.opacity(0.10), chartInk.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                ))
                .accessibilityHidden(true)
            }
            LineMark(
                x: .value("Time", point.date),
                y: .value("Hashrate in \(unit.rawValue)", value),
                series: .value("Recorded interval", segmentID)
            )
            .foregroundStyle(by: .value("Miner", history.name))
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.linear)
            // No per-mark accessibility: the chart is a single `.ignore` element with an
            // AXChartDescriptor, so formatting a date and value string for every plotted
            // point on every body pass was pure main-thread cost.
            if segment.points.count == 1 {
                PointMark(x: .value("Time", point.date), y: .value("Hashrate", value))
                    .foregroundStyle(by: .value("Miner", history.name))
                    .symbolSize(30)
            }
        }
    }

    @ChartContentBuilder
    private func selectionMarks(
        _ selection: FleetChartSelection,
        unit: HashrateUnit
    ) -> some ChartContent {
        RuleMark(x: .value("Selected Time", selection.selectedDate))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            .foregroundStyle(FleetTheme.separator)
            .accessibilityHidden(true)

        ForEach(selection.seriesValues) { item in
            if let value = item.value {
                let plotValue = unit.value(fromGHs: value)
                PointMark(
                    x: .value("Time", selection.selectedDate),
                    y: .value("Hashrate in \(unit.rawValue)", plotValue)
                )
                .foregroundStyle(by: .value("Miner", item.name))
                .symbolSize(45)
                .accessibilityHidden(true)
            }
        }
    }

    /// Tap overlay to immediately snap and select a point, engaging scrollDisabled on TabView.
    @ViewBuilder
    private func chartHitOverlay(
        selection: FleetChartSelection?,
        proxy: ChartProxy,
        histories: [MinerHistorySeries],
        window: HistoryWindow
    ) -> some View {
        GeometryReader { geometry in
            let hitArea = Rectangle().fill(Color.clear).contentShape(Rectangle())
            if selection != nil {
                // Once selected, own the horizontal drag instead of relying on
                // the chart's scroll-sensitive default recognizer inside TabView.
                hitArea.highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            selectChartValue(
                                at: value.location,
                                proxy: proxy,
                                geometry: geometry,
                                histories: histories,
                                window: window
                            )
                        }
                )
            } else {
                // Ordinary swipes continue to page until the user taps a reading.
                // Chart's built-in x-selection recognizer can win the gesture arena on iPad,
                // leaving the overlay without a date to resolve. A high-priority tap keeps the
                // page swipe recognizer available for movement while ensuring a normal tap reaches
                // our snapping path on every supported layout.
                hitArea.highPriorityGesture(
                    SpatialTapGesture().onEnded { value in
                        selectChartValue(
                            at: value.location,
                            proxy: proxy,
                            geometry: geometry,
                            histories: histories,
                            window: window
                        )
                    }
                )
            }
        }
    }

    private func selectChartValue(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        histories: [MinerHistorySeries],
        window: HistoryWindow
    ) {
        let plot = proxy.plotFrame.map { geometry[$0] } ??
            CGRect(origin: .zero, size: geometry.size)
        let x = min(max(location.x - plot.minX, 0), plot.width)
        let proxyDate = proxy.value(atX: x, as: Date.self)
        if let date = proxyDate,
           FleetChartSelection.resolve(
               at: date,
               in: histories,
               tolerance: window.selectionTolerance
           ) != nil {
            rawSelectedDate = date
            return
        }

        // ChartProxy can return no date, or a date outside the plotted samples, when the
        // chart is embedded in a wide paged layout. Use the actual data range as a bounded
        // fallback so a real tap still reaches the same discrete selection model.
        let points = histories
            .flatMap(\.points)
            .filter { $0.value.isFinite && $0.value >= 0 }
        guard let firstDate = points.map(\.date).min(),
              let lastDate = points.map(\.date).max(),
              plot.width > 0 else { return }
        let fraction = min(max(x / plot.width, 0), 1)
        let targetDate = firstDate.addingTimeInterval(
            lastDate.timeIntervalSince(firstDate) * fraction
        )
        if let snappedDate = FleetChartSelection.nearestValidDate(
            to: targetDate,
            in: histories,
            tolerance: window.selectionTolerance
        ) {
            rawSelectedDate = snappedDate
        }
    }

    func chartAccessibilityValue(
        for histories: [MinerHistorySeries],
        selection: FleetChartSelection?
    ) -> String {
        if let selection {
            return selection.accessibleSummary
        }
        let totalCount = histories.reduce(0) { $0 + $1.points.count }
        let minerCount = isFleetView ? chartDevices.count : histories.count
        return "\(minerCount) miners, \(totalCount) total data points recorded."
    }
}

struct HistoryPageHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
