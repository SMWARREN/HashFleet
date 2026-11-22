import SwiftUI
import Charts
import HashFleetCore

enum MinerHistoryMetric: String, CaseIterable, Identifiable {
    case hashrate, temperature, power

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var unit: String { self == .temperature ? "°C" : "W" }
    private var spokenUnit: String { self == .temperature ? "degrees Celsius" : "watts" }

    func sensorValue(_ sample: MinerSensorHistorySample) -> Double? {
        switch self {
        case .hashrate: nil
        case .temperature: sample.temperature
        case .power: sample.power
        }
    }

    func label(_ value: Double, spoken: Bool = false) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(spoken ? spokenUnit : unit)"
    }
}

struct MinerSensorHistoryPlot: View {
    let deviceID: UUID
    let metric: MinerHistoryMetric
    let rangeTitle: String
    let interval: TimeInterval
    let observationMinute: Int?
    let axisFormat: Date.FormatStyle
    let isDemo: Bool
    let database: MinerTelemetryDatabase
    let height: CGFloat

    private struct Query: Equatable {
        let deviceID: UUID
        let interval: TimeInterval
        let observationMinute: Int?
    }

    private struct Result {
        let query: Query
        let span: ClosedRange<Date>
        let samples: [MinerSensorHistorySample]
    }

    @State private var result: Result?

    var body: some View {
        let query = Query(deviceID: deviceID, interval: interval, observationMinute: observationMinute)
        VStack(alignment: .leading, spacing: 6) {
            if isDemo {
                empty("Sample miners don’t store temperature or power history.")
            } else if let result, result.query.deviceID == query.deviceID, result.query.interval == query.interval {
                let points = result.samples.compactMap { sample -> HashratePoint? in
                    metric.sensorValue(sample).map { HashratePoint(date: sample.date, value: $0) }
                }
                if let first = points.first, let last = points.last {
                    Chart(points) { point in
                        PointMark(x: .value("Time", point.date), y: .value(metric.title, point.value))
                            .foregroundStyle(FleetTheme.accent)
                            .symbolSize(19)
                            .accessibilityLabel(point.date.formatted(.dateTime.month().day().hour().minute()))
                            .accessibilityValue(metric.label(point.value, spoken: true))
                    }
                    .chartXScale(domain: result.span, range: .plotDimension(startPadding: 4, endPadding: 4))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: axisFormat) } }
                    .chartYScale(domain: FleetHistoryPresentation.focusedYDomain(for: points.map(\.value)) ?? 0...1)
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                    .frame(height: height)
                    .accessibilityLabel("Saved \(metric.title.lowercased()) history. \(rangeTitle).")
                    .accessibilityValue("First \(metric.label(first.value, spoken: true)). Latest \(metric.label(last.value, spoken: true)).")
                    .accessibilityIdentifier("detail.sensorHistoryChart")
                    Text("Latest in this range: \(metric.label(last.value))")
                        .fleetFont(.caption, weight: .semibold).foregroundStyle(FleetTheme.ink)
                    Text("Points average saved readings. Times without readings are blank.")
                        .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                } else {
                    empty("No saved \(metric.title.lowercased()) readings in this range.")
                }
            } else {
                ProgressView("Loading saved readings…")
                    .frame(maxWidth: .infinity, minHeight: height)
            }
        }
        .task(id: query) {
            guard !isDemo else { return }
            let end = Date.now
            let start = end.addingTimeInterval(-interval)
            let samples = await database.getSensorHistory(minerId: deviceID.uuidString, since: start, until: end)
            guard !Task.isCancelled else { return }
            result = Result(query: query, span: start...end, samples: samples)
        }
    }

    private func empty(_ message: String) -> some View {
        Text(message)
            .fleetFont(.subheadline)
            .foregroundStyle(FleetTheme.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: height)
            .accessibilityIdentifier("detail.sensorHistoryEmpty")
    }
}

/// Chart construction and scrub interaction for FleetHistoryCard.
extension FleetHistoryCard {
    @ViewBuilder
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
        let trend = chartAccessibilityValue(for: chartHistories, selection: nil)
        let dates = plottedPoints.map(\.date)
        let firstDate = dates.min()
        let lastDate = dates.max()
        let axisFormat = window.axisFormat(recentRange: recentRange)
        let edgeDates: [Date] = if let firstDate, let lastDate, firstDate != lastDate,
            firstDate.formatted(axisFormat) != lastDate.formatted(axisFormat), !numberFirstChartLabelSize.isAccessibilitySize {
            [firstDate, lastDate]
        } else {
            lastDate.map { [$0] } ?? []
        }

        let plot = Chart {
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
            if isMinerDetail && !numberFirst {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: axisFormat).foregroundStyle(chartSecondary)
                }
            } else if !numberFirst {
                AxisMarks(values: edgeDates) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel(anchor: edgeDates.count == 1 || date == lastDate ? .topTrailing : .topLeading) {
                            Text(date.formatted(axisFormat))
                                .fleetFont(.caption)
                                .monospacedDigit()
                                .foregroundStyle(chartSecondary)
                        }
                    }
                }
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
        .frame(height: numberFirst ? nil : effectiveChartHeight)
        .chartOverlay { proxy in
            chartHitOverlay(
                selection: selection,
                proxy: proxy,
                histories: histories,
                window: window
            )
        }
        .accessibilityChartDescriptor(
            FleetAXChartDescriptorProvider(
                series: chartHistories, windowHeading: rangeTitle, isDemo: isDemo, trendSummary: trend
            )
        )
        // Swift Charts does not consistently expose a node when only a custom overlay owns
        // selection on iPad. Keep one stable chart surface for VoiceOver and UI automation,
        // while the overlay continues to receive the actual tap and drag gestures.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFleetView ?
            (isDemo ? "Simulated fleet hashrate history" : "Recorded fleet hashrate history") :
            (isDemo ? "Simulated hashrate history by miner" : "Recorded hashrate history by miner"))
        .accessibilityValue("\(rangeTitle). \(selection?.accessibleSummary ?? trend)")
        .accessibilityIdentifier("dashboard.historyChart")

        if numberFirst {
            VStack(spacing: 4) {
                plot.chartXAxis(.hidden)
                    .dynamicTypeSize(numberFirstChartLabelSize)
                    .frame(maxHeight: .infinity)
                previewTimeLabels(
                    leading: edgeDates.count == 2 ? edgeDates[0].formatted(axisFormat) : "",
                    trailing: lastDate?.formatted(axisFormat) ?? ""
                )
                .accessibilityHidden(true) // The plot's descriptor already exposes the sample times.
            }
            .frame(height: effectiveChartHeight)
        } else {
            plot
        }
    }

    private func previewTimeLabels(leading: String, trailing: String) -> some View {
        // Sample dates change; the endpoints' view identities and their alignment don't.
        // Keep these out of the chart's tick layout and any refresh animation transaction.
        HStack(spacing: 8) {
            Text(leading).frame(maxWidth: .infinity, alignment: .leading)
            Text(trailing).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .fleetFont(.caption)
        .dynamicTypeSize(numberFirstChartLabelSize)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(chartSecondary)
        .padding(.leading, 48)  // Clear the y-axis labels.
        .padding(.trailing, 28) // Align near the plot's padded trailing edge.
        .contentTransition(.identity)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    @ChartContentBuilder
    private func historyMarks(
        _ series: [FleetHistoryChartSeries],
        unit: HashrateUnit
    ) -> some ChartContent {
        ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
            ForEach(item.segments) { segment in
                segmentMarks(item.history, segment: segment, unit: unit, showsArea: series.count == 1, index: index)
            }
        }
    }

    @ChartContentBuilder
    private func segmentMarks(
        _ history: MinerHistorySeries,
        segment: FleetHistorySegment,
        unit: HashrateUnit,
        showsArea: Bool,
        index: Int
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
            .foregroundStyle(FleetChartPalette.color(for: index))
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round,
                                   dash: FleetChartPalette.comparisonDash(for: index)))
            .interpolationMethod(.linear)
            // No per-mark accessibility: the chart is a single `.ignore` element with an
            // AXChartDescriptor, so formatting a date and value string for every plotted
            // point on every body pass was pure main-thread cost.
            if segment.points.count == 1 {
                PointMark(x: .value("Time", point.date), y: .value("Hashrate", value))
                    .foregroundStyle(FleetChartPalette.color(for: index))
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
                .foregroundStyle(FleetChartPalette.color(for: item.colorIndex))
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
        guard histories.count == 1, let points = histories.first?.points, let first = points.first else {
            return "Comparing \(histories.count) miners. Each series is identified in the legend."
        }
        let startValue = FleetFormat.hashrateWithUnit(first.value)
        guard let last = points.last, points.count > 1 else {
            return "One reading, \(startValue). More readings are needed for a trend."
        }
        let endValue = FleetFormat.hashrateWithUnit(last.value)
        if startValue == endValue { return "First and latest readings: \(endValue)." }
        return "First reading: \(startValue). Latest reading: \(endValue)."
    }
}

struct HistoryPageHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
