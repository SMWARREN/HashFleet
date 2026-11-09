//
//  MinerUptimeHeatmapTests.swift
//  MacAppTests
//
//  Tests for MinerUptimeHeatmapModel bucketing.
//

import Foundation
import Testing
@testable import HashFleetMac

@Suite("Miner uptime heatmap")
struct MinerUptimeHeatmapTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    /// 2026-11-06 21:30 EST.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 21, minute: 30))!
    }

    private func point(hoursAgo: Double, value: Double) -> HashratePoint {
        HashratePoint(date: now.addingTimeInterval(-hoursAgo * 3600), value: value)
    }

    @Test func emptyReadingsGiveTwentyFourGrayHours() {
        let buckets = MinerUptimeHeatmapModel.buckets(readings: [], now: now, calendar: calendar)
        #expect(buckets.count == 24)
        #expect(buckets.allSatisfy { $0.level == 0 && $0.average == nil && $0.readingCount == 0 })
        #expect(MinerUptimeHeatmapModel.summary(buckets) == "Hashing 0 of last 24 hours")
    }

    @Test func bucketsAreOrderedOldestToCurrentHour() {
        let buckets = MinerUptimeHeatmapModel.buckets(readings: [], now: now, calendar: calendar)
        let currentHour = calendar.dateInterval(of: .hour, for: now)!.start
        #expect(buckets.last?.start == currentHour)
        #expect(buckets.first?.start == calendar.date(byAdding: .hour, value: -23, to: currentHour))
        #expect(zip(buckets, buckets.dropFirst()).allSatisfy { $0.start < $1.start })
    }

    @Test func gapsStayGrayAndHashingHoursCount() {
        let readings = [
            point(hoursAgo: 0, value: 1000),
            point(hoursAgo: 0.1, value: 1000),
            point(hoursAgo: 2, value: 1000),
            point(hoursAgo: 5, value: 1000)
        ]
        let buckets = MinerUptimeHeatmapModel.buckets(readings: readings, now: now, calendar: calendar)
        #expect(buckets.filter(\.isOnline).count == 3)
        #expect(buckets[23].readingCount == 2)
        #expect(buckets[22].level == 0)
        #expect(buckets[21].level == 4)
    }

    @Test func partialHourAveragesOnlyItsOwnReadings() {
        // 21:00 and 21:29 fall in the current hour; 20:59 belongs to the previous one.
        let readings = [
            point(hoursAgo: 0.5, value: 800),
            point(hoursAgo: 0.0167, value: 1200),
            point(hoursAgo: 0.5167, value: 400)
        ]
        let buckets = MinerUptimeHeatmapModel.buckets(readings: readings, now: now, calendar: calendar)
        #expect(buckets[23].readingCount == 2)
        #expect(buckets[23].average == 1000)
        #expect(buckets[22].readingCount == 1)
        #expect(buckets[22].average == 400)
    }

    @Test func levelThresholdsRelativeToMedianTypicalRate() {
        #expect(MinerUptimeHeatmapModel.level(average: nil, typical: 1000) == 0)
        #expect(MinerUptimeHeatmapModel.level(average: 0, typical: 1000) == 0)
        #expect(MinerUptimeHeatmapModel.level(average: 500, typical: nil) == 0)
        #expect(MinerUptimeHeatmapModel.level(average: 499, typical: 1000) == 1)
        #expect(MinerUptimeHeatmapModel.level(average: 500, typical: 1000) == 2)
        #expect(MinerUptimeHeatmapModel.level(average: 800, typical: 1000) == 3)
        #expect(MinerUptimeHeatmapModel.level(average: 950, typical: 1000) == 4)
        #expect(MinerUptimeHeatmapModel.level(average: 1500, typical: 1000) == 4)
        #expect(MinerUptimeHeatmapModel.typicalRate([0, 100, 300, 200]) == 200)
        #expect(MinerUptimeHeatmapModel.typicalRate([0, 0]) == nil)
    }

    @Test func zeroHashrateHourIsReachableButNotHashing() {
        let readings = [point(hoursAgo: 1, value: 0), point(hoursAgo: 0, value: 1000)]
        let buckets = MinerUptimeHeatmapModel.buckets(readings: readings, now: now, calendar: calendar)
        #expect(buckets[22].readingCount == 1)
        #expect(buckets[22].level == 0)
        #expect(buckets[23].level == 4)
    }

    @Test func invalidAndOutOfWindowReadingsAreIgnored() {
        let readings = [
            point(hoursAgo: 0, value: .nan),
            point(hoursAgo: 0, value: -5),
            point(hoursAgo: 30, value: 1000),
            point(hoursAgo: -2, value: 1000)
        ]
        let buckets = MinerUptimeHeatmapModel.buckets(readings: readings, now: now, calendar: calendar)
        #expect(buckets.allSatisfy { $0.readingCount == 0 })
    }

    @Test func liveSamplesMergeWithoutDoubleCountingStoredOnes() {
        let stored = [point(hoursAgo: 0.2, value: 1000)]
        let sums = MinerUptimeHeatmapModel.hourlySums(stored, calendar: calendar)
        let recent = stored + [point(hoursAgo: 0.1, value: 2000)]
        let merged = MinerUptimeHeatmapModel.merging(
            sums, recent: recent, after: stored.last?.date, calendar: calendar
        )
        let buckets = MinerUptimeHeatmapModel.buckets(sums: merged, now: now, calendar: calendar)
        #expect(buckets[23].readingCount == 2)
        #expect(buckets[23].average == 1500)
    }

    @Test func ringFractionMatchesHashingHours() {
        #expect(MinerUptimeHeatmapModel.onlineFraction([]) == 0)
        let empty = MinerUptimeHeatmapModel.buckets(readings: [], now: now, calendar: calendar)
        #expect(MinerUptimeHeatmapModel.onlineFraction(empty) == 0)
        let readings = [
            point(hoursAgo: 0, value: 1000),
            point(hoursAgo: 2, value: 1000),
            point(hoursAgo: 5, value: 1000)
        ]
        let buckets = MinerUptimeHeatmapModel.buckets(readings: readings, now: now, calendar: calendar)
        #expect(MinerUptimeHeatmapModel.onlineFraction(buckets) == 3.0 / 24.0)
    }
}
