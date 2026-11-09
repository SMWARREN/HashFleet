import SwiftUI
import Charts
import Accessibility
import HashFleetCore

/// Timeframe windows supported by the fleet history chart.
enum HistoryWindow: Int, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: Int { rawValue }

    var identifier: String {
        switch self {
        case .daily: "daily"
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .yearly: "yearly"
        }
    }

    var heading: String {
        switch self {
        case .daily: "24h"
        case .weekly: "7d"
        case .monthly: "30d"
        case .yearly: "365d"
        }
    }

    var summaryLabel: String {
        switch self {
        case .daily: "Daily average"
        case .weekly: "Weekly average"
        case .monthly: "Monthly average"
        case .yearly: "Yearly average"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .daily: return 24 * 60 * 60
        case .weekly: return 7 * 24 * 60 * 60
        case .monthly: return 30 * 24 * 60 * 60
        case .yearly: return 365 * 24 * 60 * 60
        }
    }

    /// Bounded tolerance when snapping a scrub coordinate to the nearest valid point.
    var selectionTolerance: TimeInterval {
        switch self {
        case .daily: return 30 * 60  // 30 minutes
        case .weekly: return 4 * 3600  // 4 hours
        case .monthly: return 24 * 3600  // 24 hours
        case .yearly: return 7 * 24 * 3600  // 7 days
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .daily, .weekly:
            return .dateTime.hour().minute()
        case .monthly:
            return .dateTime.month().day().hour().minute()
        case .yearly:
            return .dateTime.month().day()
        }
    }

    /// Unambiguous timestamp format for selected reading inspection.
    var selectedTimestampFormat: Date.FormatStyle {
        switch self {
        case .daily:
            return .dateTime.hour().minute().second()
        case .weekly:
            return .dateTime.month().day().hour().minute()
        case .monthly:
            return .dateTime.month().day().hour().minute()
        case .yearly:
            return .dateTime.year().month().day()
        }
    }
}

/// A named historical hashrate series corresponding to a single miner.
struct MinerHistorySeries: Identifiable, Sendable {
    let id: UUID
    let name: String
    let points: [HashratePoint]

    init(id: UUID = UUID(), name: String, points: [HashratePoint]) {
        self.id = id
        self.name = name
        self.points = points
    }
}

extension MinerHistorySeries: Equatable {
    static func == (lhs: MinerHistorySeries, rhs: MinerHistorySeries) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.points.count == rhs.points.count
            && zip(lhs.points, rhs.points).allSatisfy { $0.date == $1.date && $0.value == $1.value }
    }
}

/// Standard four-color palette matching the chart's foreground style scale.
enum FleetChartPalette {
    static let colors: [Color] = [
        FleetTheme.accent,
        FleetTheme.positive,
        FleetTheme.chartThird,
        FleetTheme.chartFourth
    ]

    static func color(for index: Int) -> Color {
        colors[index % colors.count]
    }
}

/// Deterministic selection model for interactive chart inspection.
struct FleetChartSelection: Equatable, Sendable {
    /// Per-series snapshot at the selected timestamp.
    struct SeriesValue: Identifiable, Equatable, Sendable {
        let id: UUID
        let name: String
        let value: Double?
        let colorIndex: Int
        let isMissing: Bool

        var formattedRate: String {
            guard let value, value.isFinite, value >= 0 else {
                return "—"
            }
            return FleetFormat.hashrateWithUnit(value)
        }

        var accessibilityText: String {
            if let value, value.isFinite, value >= 0 {
                return "\(name): \(FleetFormat.hashrateWithUnit(value))"
            } else {
                return "\(name): offline or no reading"
            }
        }
    }

    let selectedDate: Date
    let rawTargetDate: Date
    let seriesValues: [SeriesValue]
    let totalRate: Double?

    var formattedTotalRate: String {
        guard let totalRate, totalRate.isFinite, totalRate >= 0 else {
            return "—"
        }
        return FleetFormat.hashrateWithUnit(totalRate)
    }

    func formattedTimestamp(for style: Date.FormatStyle? = nil) -> String {
        if let style {
            return selectedDate.formatted(style)
        }
        return selectedDate.formatted(date: .omitted, time: .standard)
    }

    var accessibleSummary: String {
        let fullDateStr = selectedDate.formatted(date: .abbreviated, time: .standard)
        let rateStr = formattedTotalRate
        let seriesParts = seriesValues.map(\.accessibilityText).joined(separator: ", ")
        return "Selected reading at \(fullDateStr). Total: \(rateStr). Miner breakdown: \(seriesParts)"
    }

    /// Resolves the nearest valid discrete point in `seriesList` to `rawDate` within `tolerance`.
    ///
    /// - Parameters:
    ///   - rawDate: Continuous date from chart touch/drag gesture.
    ///   - seriesList: Historical series displayed on the chart.
    ///   - tolerance: Maximum distance allowed from `rawDate` to snap to a point (bounded explicit).
    ///   - clusterTolerance: Maximum distance allowed for other series to be considered part of the same reading.
    /// - Returns: A resolved `FleetChartSelection`, or `nil` if no point exists within tolerance.
    static func resolve(
        at rawDate: Date,
        in seriesList: [MinerHistorySeries],
        tolerance: TimeInterval,
        clusterTolerance: TimeInterval = 60
    ) -> FleetChartSelection? {
        guard let nearest = nearestPoint(to: rawDate, in: seriesList, tolerance: tolerance) else {
            return nil
        }
        let canonicalDate = nearest.date

        // For each series, resolve whether it has a valid reading near canonicalDate
        let seriesValues = seriesList.enumerated().map { index, series in
            seriesValue(at: canonicalDate, in: series, index: index, clusterTolerance: clusterTolerance)
        }

        // Calculate total hashrate across reporting series
        let reportingValues = seriesValues.compactMap(\.value)
        let totalRate: Double? = reportingValues.isEmpty ? nil : reportingValues.reduce(0, +)

        return FleetChartSelection(
            selectedDate: canonicalDate,
            rawTargetDate: rawDate,
            seriesValues: seriesValues,
            totalRate: totalRate
        )
    }

    /// Returns the canonical timestamp nearest to a continuous chart target when it is within
    /// the same bounded tolerance used by interactive selection.
    static func nearestValidDate(
        to rawDate: Date,
        in seriesList: [MinerHistorySeries],
        tolerance: TimeInterval
    ) -> Date? {
        nearestPoint(to: rawDate, in: seriesList, tolerance: tolerance)?.date
    }

    /// Nearest valid finite point across all series to `rawDate`, when it is within `tolerance`.
    private static func nearestPoint(
        to rawDate: Date,
        in seriesList: [MinerHistorySeries],
        tolerance: TimeInterval
    ) -> HashratePoint? {
        var bestPoint: HashratePoint?
        var bestDistance: TimeInterval = .infinity

        for series in seriesList {
            for point in series.points where point.value.isFinite && point.value >= 0 {
                let distance = abs(point.date.timeIntervalSince(rawDate))
                if distance < bestDistance {
                    bestDistance = distance
                    bestPoint = point
                }
            }
        }

        guard let best = bestPoint, bestDistance <= tolerance else {
            return nil
        }
        return best
    }

    /// Series value at `canonicalDate`; Do not invent continuity for missing values.
    private static func seriesValue(
        at canonicalDate: Date,
        in series: MinerHistorySeries,
        index: Int,
        clusterTolerance: TimeInterval
    ) -> SeriesValue {
        let sortedValid = series.points
            .filter { $0.value.isFinite && $0.value >= 0 }
            .sorted { $0.date < $1.date }

        var match: HashratePoint?
        var bestDistance: TimeInterval = .infinity

        for point in sortedValid {
            let distance = abs(point.date.timeIntervalSince(canonicalDate))
            if distance <= clusterTolerance && distance < bestDistance {
                bestDistance = distance
                match = point
            }
        }

        return SeriesValue(
            id: series.id,
            name: series.name,
            value: match?.value,
            colorIndex: index,
            isMissing: match == nil
        )
    }

    /// Verifies if a selection timestamp remains valid against updated series.
    static func isSelectionValid(
        at date: Date,
        in seriesList: [MinerHistorySeries],
        tolerance: TimeInterval
    ) -> Bool {
        for series in seriesList {
            for point in series.points where point.value.isFinite && point.value >= 0 {
                if abs(point.date.timeIntervalSince(date)) <= tolerance {
                    return true
                }
            }
        }
        return false
    }

    /// Validates an existing selection, returning `nil` if the target point has been removed.
    static func validateOrDeselect(
        _ current: FleetChartSelection?,
        in seriesList: [MinerHistorySeries],
        tolerance: TimeInterval
    ) -> FleetChartSelection? {
        guard let current else { return nil }
        return isSelectionValid(at: current.selectedDate, in: seriesList, tolerance: tolerance) ? current : nil
    }
}

/// Signature capturing history count, boundaries, and timestamps to detect capped-history updates.
struct MinerHistorySignature: Equatable, Sendable {
    let id: UUID
    let count: Int
    let firstDate: Date?
    let lastDate: Date?
    let updatedAt: Date?

    init(id: UUID, history: [HashratePoint], updatedAt: Date? = nil) {
        self.id = id
        self.count = history.count
        self.firstDate = history.first?.date
        self.lastDate = history.last?.date
        self.updatedAt = updatedAt
    }
}

/// Legend item representation for rendering both unselected and selected chart states.
struct FleetChartLegendItem: Identifiable, Sendable {
    let id: UUID
    let name: String
    let color: Color
    let seriesValue: FleetChartSelection.SeriesValue?

    var formattedRate: String {
        seriesValue?.formattedRate ?? ""
    }

    var isMissing: Bool {
        seriesValue?.isMissing ?? false
    }

    var accessibleDescription: String {
        if let seriesValue {
            return seriesValue.accessibilityText
        }
        return name
    }
}

/// VoiceOver Audio Graph descriptor provider for accessibility.
struct FleetAXChartDescriptorProvider: AXChartDescriptorRepresentable {
    let series: [MinerHistorySeries]
    let windowHeading: String
    let isDemo: Bool

    func makeChartDescriptor() -> AXChartDescriptor {
        let allPoints = series.flatMap(\.points).filter { $0.value.isFinite && $0.value >= 0 }
        let dates = allPoints.map(\.date)
        let values = allPoints.map(\.value)

        let minDate = dates.min() ?? Date()
        let maxDate = dates.max() ?? Date().addingTimeInterval(1)
        let maxGHs = values.max() ?? 0
        let displayUnit = FleetFormat.hashrateDisplayUnit(forGHs: maxGHs)
        let minY = 0.0
        let maxY = max(displayUnit.value(fromGHs: maxGHs), 1.0)

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time",
            range: minDate
                .timeIntervalSince1970...max(maxDate.timeIntervalSince1970, minDate.timeIntervalSince1970 + 1),
            gridlinePositions: []
        ) { val in
            Date(timeIntervalSince1970: val).formatted(date: .abbreviated, time: .standard)
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Hashrate in \(displayUnit.rawValue)",
            range: minY...maxY,
            gridlinePositions: []
        ) { val in
            "\(displayUnit.formatScaleValue(val)) \(displayUnit.rawValue)"
        }

        let seriesDescriptors = series.map { seriesDescriptor(for: $0, unit: displayUnit) }

        return AXChartDescriptor(
            title: isDemo ? "Simulated Hashrate History" : "Fleet Hashrate History",
            summary: chartSummary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: seriesDescriptors
        )
    }

    private func seriesDescriptor(for history: MinerHistorySeries, unit: HashrateUnit) -> AXDataSeriesDescriptor {
        let points: [AXDataPoint] = history.points
            .filter { $0.value.isFinite && $0.value >= 0 }
            .sorted { $0.date < $1.date }
            .map { point in
                AXDataPoint(
                    x: point.date.timeIntervalSince1970,
                    y: unit.value(fromGHs: point.value),
                    label:
                        "\(history.name): \(FleetFormat.hashrateWithUnit(point.value)) at " +
                        point.date.formatted(date: .omitted, time: .standard)
                )
            }
        return AXDataSeriesDescriptor(
            name: history.name,
            isContinuous: true,
            dataPoints: points
        )
    }

    private var chartSummary: String {
        isDemo
            ? "Simulated hashrate history for \(series.count) miner(s) over \(windowHeading)."
            : "Recorded hashrate history for \(series.count) miner(s) over \(windowHeading)."
    }
}
