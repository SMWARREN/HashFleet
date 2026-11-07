//
//  MinerUptimeHeatmap.swift
//  HashFleet
//
//  Adapted from ShipSwift (MIT) - SWActivityHeatmap.swift
//  A GitHub-style grid of the last 24 hours for one miner. Each cell is one clock hour,
//  shaded by that hour's average hashrate relative to the miner's typical rate.
//

import SwiftUI
import HashFleetCore

/// Pure bucketing for the uptime heatmap, kept free of SwiftUI for unit testing.
enum MinerUptimeHeatmapModel {
    struct Bucket: Identifiable, Equatable, Sendable {
        /// Start of the clock hour this bucket covers.
        let start: Date
        /// Average hashrate of readings inside the hour, nil when there were none.
        let average: Double?
        /// Number of readings inside the hour.
        let readingCount: Int
        /// 0 = no data or not hashing, 1...4 = increasing share of the typical rate.
        let level: Int

        var id: Date { start }
        var isOnline: Bool { level > 0 }
    }

    /// Average below this fraction of typical counts as level 1 (degraded but hashing).
    static let levelThresholds: [Double] = [0.5, 0.8, 0.95]

    struct HourSum: Equatable, Sendable {
        var total: Double = 0
        var count: Int = 0
    }

    /// Sums valid readings by clock hour. Run once on load so a day of per-second readings
    /// is not re-scanned on every live publish.
    static func hourlySums(
        _ readings: [HashratePoint],
        calendar: Calendar = .current
    ) -> [Date: HourSum] {
        var sums: [Date: HourSum] = [:]
        for point in readings where point.value.isFinite && point.value >= 0 {
            guard let hour = calendar.dateInterval(of: .hour, for: point.date)?.start else { continue }
            sums[hour, default: HourSum()].total += point.value
            sums[hour, default: HourSum()].count += 1
        }
        return sums
    }

    /// Groups readings into `hours` clock-hour buckets ending with the hour containing `now`.
    /// Readings outside the window, non-finite or negative values are ignored. Zero hashrate is
    /// recorded as a reading but maps to level 0, because the miner was reachable but not hashing.
    static func buckets(
        readings: [HashratePoint],
        hours: Int = 24,
        now: Date,
        calendar: Calendar = .current
    ) -> [Bucket] {
        buckets(sums: hourlySums(readings, calendar: calendar), hours: hours, now: now, calendar: calendar)
    }

    static func buckets(
        sums: [Date: HourSum],
        hours: Int = 24,
        now: Date,
        calendar: Calendar = .current
    ) -> [Bucket] {
        guard hours > 0,
              let currentHour = calendar.dateInterval(of: .hour, for: now)?.start
        else { return [] }

        let starts: [Date] = (0..<hours).reversed().compactMap {
            calendar.date(byAdding: .hour, value: -$0, to: currentHour)
        }

        let averages = starts.map { start -> Double? in
            guard let entry = sums[start], entry.count > 0 else { return nil }
            return entry.total / Double(entry.count)
        }
        let typical = typicalRate(averages.compactMap { $0 })

        return zip(starts, averages).map { start, average in
            Bucket(
                start: start,
                average: average,
                readingCount: sums[start]?.count ?? 0,
                level: level(average: average, typical: typical)
            )
        }
    }

    /// Adds live samples newer than the last stored reading, so samples already saved to the
    /// database are not counted twice.
    static func merging(
        _ sums: [Date: HourSum],
        recent: [HashratePoint],
        after cutoff: Date?,
        calendar: Calendar = .current
    ) -> [Date: HourSum] {
        let fresh = cutoff.map { cutoff in recent.filter { $0.date > cutoff } } ?? recent
        guard !fresh.isEmpty else { return sums }
        return sums.merging(hourlySums(fresh, calendar: calendar)) {
            HourSum(total: $0.total + $1.total, count: $0.count + $1.count)
        }
    }

    /// The median of hours that actually hashed. A median ignores a single spike or dip.
    static func typicalRate(_ averages: [Double]) -> Double? {
        let hashing = averages.filter { $0 > 0 }.sorted()
        guard !hashing.isEmpty else { return nil }
        let middle = hashing.count / 2
        return hashing.count.isMultiple(of: 2)
            ? (hashing[middle - 1] + hashing[middle]) / 2
            : hashing[middle]
    }

    static func level(average: Double?, typical: Double?) -> Int {
        guard let average, average > 0, let typical, typical > 0 else { return 0 }
        let ratio = average / typical
        if ratio < levelThresholds[0] { return 1 }
        if ratio < levelThresholds[1] { return 2 }
        if ratio < levelThresholds[2] { return 3 }
        return 4
    }

    static func summary(_ buckets: [Bucket]) -> String {
        let online = buckets.filter(\.isOnline).count
        return "Hashing \(online) of last \(buckets.count) hours"
    }

    /// Share of hours that hashed, 0...1. Empty input reads as 0, never as healthy.
    static func onlineFraction(_ buckets: [Bucket]) -> Double {
        guard !buckets.isEmpty else { return 0 }
        return Double(buckets.filter(\.isOnline).count) / Double(buckets.count)
    }
}

/// Small 24-hour uptime ring, adapted from ShipSwift `SWRingChart`. Static: it redraws only
/// when the hourly buckets change, with no looping animation.
struct MinerUptimeRing: View {
    let fraction: Double
    var size: CGFloat = 30
    var lineWidth: CGFloat = 4

    private var clamped: Double { min(max(fraction, 0), 1) }

    private var tint: Color {
        if clamped >= 0.95 { return FleetTheme.positive }
        if clamped >= 0.5 { return FleetTheme.warning }
        return MinerSidebarAttention.hotTint
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(FleetTheme.secondary.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((clamped * 100).rounded()))")
                .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(FleetTheme.ink)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Last-24-hours uptime grid for one miner. Loads saved readings at most once per clock hour
/// (plus when the miner changes), never on the per-second live publish.
struct MinerUptimeHeatmap: View {
    let deviceID: UUID
    let isDemo: Bool
    /// In-memory recent samples, used for Demo and to fill the current hour.
    let recentHistory: [HashratePoint]
    var database: MinerTelemetryDatabase?

    @State private var storedSums: [Date: MinerUptimeHeatmapModel.HourSum] = [:]
    @State private var lastStoredReading: Date?

    private static let hours = 24

    private var currentHourKey: Date {
        Calendar.current.dateInterval(of: .hour, for: .now)?.start ?? .now
    }

    var body: some View {
        let sums = MinerUptimeHeatmapModel.merging(storedSums, recent: recentHistory, after: lastStoredReading)
        let buckets = MinerUptimeHeatmapModel.buckets(sums: sums, hours: Self.hours, now: .now)
        VStack(alignment: .leading, spacing: 8) {
            header(buckets)
            grid(buckets)
            legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Uptime, last 24 hours")
        .accessibilityValue(MinerUptimeHeatmapModel.summary(buckets))
        .accessibilityIdentifier("detail.uptimeHeatmap")
        .task(id: LoadKey(deviceID: deviceID, hour: currentHourKey)) {
            await loadStoredReadings()
        }
    }

    private struct LoadKey: Equatable {
        let deviceID: UUID
        let hour: Date
    }

    private func header(_ buckets: [MinerUptimeHeatmapModel.Bucket]) -> some View {
        HStack(alignment: .center, spacing: 10) {
            MinerUptimeRing(fraction: MinerUptimeHeatmapModel.onlineFraction(buckets))
            Text("LAST 24 HOURS")
                .fleetFont(.caption2, weight: .semibold, design: .monospaced)
                .tracking(0.6)
                .foregroundStyle(FleetTheme.secondary)
            Spacer(minLength: 8)
            Text(MinerUptimeHeatmapModel.summary(buckets))
                .fleetFont(.caption2, design: .monospaced)
                .foregroundStyle(FleetTheme.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func grid(_ buckets: [MinerUptimeHeatmapModel.Bucket]) -> some View {
        // 24 equal cells across the card width, so the grid scales with Mac and phone layouts.
        HStack(spacing: 3) {
            ForEach(buckets) { bucket in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Self.color(for: bucket.level))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .help(Self.tooltip(bucket))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text(hourLabel(hoursAgo: Self.hours - 1))
            Spacer(minLength: 8)
            Text("Less")
            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.color(for: level))
                    .frame(width: 10, height: 10)
            }
            Text("More")
            Spacer(minLength: 8)
            Text("Now")
        }
        .fleetFont(.caption2, design: .monospaced)
        .foregroundStyle(FleetTheme.secondary)
    }

    private func hourLabel(hoursAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .hour, value: -hoursAgo, to: currentHourKey) ?? currentHourKey
        return date.formatted(.dateTime.hour())
    }

    static func color(for level: Int) -> Color {
        switch level {
        case 1: FleetTheme.positive.opacity(0.3)
        case 2: FleetTheme.positive.opacity(0.5)
        case 3: FleetTheme.positive.opacity(0.75)
        case 4: FleetTheme.positive
        default: FleetTheme.separator.opacity(0.6)
        }
    }

    static func tooltip(_ bucket: MinerUptimeHeatmapModel.Bucket) -> String {
        let hour = bucket.start.formatted(.dateTime.weekday(.abbreviated).hour())
        guard let average = bucket.average else { return "\(hour): no readings" }
        return "\(hour): \(FleetFormat.hashrateWithUnit(average)) average, \(bucket.readingCount) readings"
    }

    private func loadStoredReadings() async {
        guard !isDemo else {
            storedSums = [:]
            lastStoredReading = nil
            return
        }
        let now = Date()
        let since = Calendar.current.date(byAdding: .hour, value: -Self.hours, to: currentHourKey) ?? now
        let samples = await (database ?? .shared).getHashrateReadings(
            minerId: deviceID.uuidString, since: since, until: now
        )
        guard !Task.isCancelled else { return }
        storedSums = MinerUptimeHeatmapModel.hourlySums(
            samples.map { HashratePoint(date: $0.timestamp, value: $0.hashrate) }
        )
        lastStoredReading = samples.last?.timestamp
    }
}
