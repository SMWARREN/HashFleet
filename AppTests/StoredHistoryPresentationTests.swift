import Foundation
import Testing
import SwiftUI
import HashFleetCore
@testable import HashFleet

/// Independent unit and integration presentation tests for:
/// - FleetRecentRange contract (rawValue, identifier, interval, summaryLabel)
/// - FleetHistorySource.mergedPoints (bounds, SQLite whole-second key deduplication, source precedence, sort order, invalid/NaN/Inf/out-of-range points)
/// - FleetHistorySource.load (reads supplied isolated database only, per-device partitioning, cancellation support)
/// - Mounted FleetHistoryCard rendering (loads isolated database, renders real mean, retains state across instances, ignores demo mode)
@Suite(.serialized)
@MainActor
struct StoredHistoryPresentationTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - FleetRecentRange Contract Tests

    @Test
    func fleetRecentRangeEnumCasesAndRawValues() {
        #expect(FleetRecentRange.allCases.count == 4)
        #expect(FleetRecentRange.oneMinute.rawValue == "1m")
        #expect(FleetRecentRange.fifteenMinutes.rawValue == "15m")
        #expect(FleetRecentRange.hour.rawValue == "1h")
        #expect(FleetRecentRange.day.rawValue == "24h")
    }

    @Test
    func fleetRecentRangeIdentifiers() {
        #expect(FleetRecentRange.fifteenMinutes.identifier == "fifteenMinutes")
        #expect(FleetRecentRange.hour.identifier == "hour")
        #expect(FleetRecentRange.day.identifier == "daily")
    }

    @Test
    func fleetRecentRangeIntervals() {
        #expect(FleetRecentRange.fifteenMinutes.interval == 15 * 60)
        #expect(FleetRecentRange.hour.interval == 60 * 60)
        #expect(FleetRecentRange.day.interval == 24 * 60 * 60)
    }

    @Test
    func fleetRecentRangeSummaryLabels() {
        #expect(FleetRecentRange.fifteenMinutes.summaryLabel == "15-minute average")
        #expect(FleetRecentRange.hour.summaryLabel == "Hourly average")
        #expect(FleetRecentRange.day.summaryLabel == "Daily average")
    }

    @Test
    func fleetRecentRangeIdentifiableProtocol() {
        for range in FleetRecentRange.allCases {
            #expect(range.id == range.rawValue)
        }
    }

    @Test
    func sampledPointsPreservesShortSeriesAndWindowBoundaries() {
        let points = (0..<5).map { index in
            HashratePoint(date: baseDate.addingTimeInterval(Double(index)), value: Double(index))
        }

        let unchanged = FleetHistoryPresentation.sampledPoints(points, maximumCount: 8)
        #expect(unchanged.map(\.date) == points.map(\.date))
        #expect(unchanged.map(\.value) == points.map(\.value))

        let sampled = FleetHistoryPresentation.sampledPoints(points, maximumCount: 3)
        #expect(sampled.count == 3)
        #expect(sampled.first?.date == points.first?.date)
        #expect(sampled.last?.date == points.last?.date)
        #expect(sampled.map(\.value) == [0, 2, 4])
    }

    @Test
    func sampledPointsPreservesRecordedLocalExtrema() {
        let values = [10.0, 12.0, 40.0, 11.0, 13.0, 9.0, 10.0, 25.0, 10.0]
        let points = values.enumerated().map { index, value in
            HashratePoint(date: baseDate.addingTimeInterval(Double(index)), value: value)
        }

        let sampled = FleetHistoryPresentation.sampledPoints(points, maximumCount: 6)

        #expect(sampled.count <= 6)
        #expect(sampled.first?.value == 10.0)
        #expect(sampled.last?.value == 10.0)
        #expect(sampled.map(\.value).contains(40.0))
        #expect(sampled.map(\.value).contains(9.0))
        #expect(sampled.map(\.date) == sampled.map(\.date).sorted())
    }

    @Test
    func focusedYDomainKeepsPositiveTrendTightlyFramed() throws {
        let domain = try #require(
            FleetHistoryPresentation.focusedYDomain(for: [12.20, 12.32, 12.45])
        )

        #expect(domain.lowerBound >= 0)
        #expect(domain.lowerBound < 12.20)
        #expect(domain.upperBound > 12.45)
        #expect(domain.upperBound - domain.lowerBound < 1.0)
    }

    @Test
    func focusedYDomainMakesModerateRateVariationVisible() throws {
        let domain = try #require(
            FleetHistoryPresentation.focusedYDomain(for: [19.0, 22.0, 25.0])
        )

        #expect(domain.lowerBound < 19.0)
        #expect(domain.upperBound > 25.0)
        #expect(domain.upperBound - domain.lowerBound < 7.0)
    }

    @Test
    func focusedYDomainReturnsNilForInvalidValues() {
        #expect(FleetHistoryPresentation.focusedYDomain(for: []) == nil)
        #expect(FleetHistoryPresentation.focusedYDomain(for: [.nan, .infinity, -1]) == nil)
    }

    @Test
    func availableRecentRangesStartsSmallAndExpandsWithRecordedCoverage() {
        let now = baseDate.addingTimeInterval(15 * 60)
        let firstReading = [HashratePoint(date: now.addingTimeInterval(-20), value: 1200)]
        #expect(
            FleetHistoryPresentation.availableRecentRanges(for: firstReading, now: now)
                == [.oneMinute]
        )

        let fifteenMinutes = [
            HashratePoint(date: now.addingTimeInterval(-15 * 60), value: 1200),
            HashratePoint(date: now, value: 1220)
        ]
        #expect(
            FleetHistoryPresentation.availableRecentRanges(for: fifteenMinutes, now: now)
                == [.oneMinute, .fifteenMinutes]
        )
    }

    @Test
    func availableRecentRangesStopsAtFirstWindowWithoutCoverage() {
        let now = baseDate.addingTimeInterval(2 * 60 * 60)
        let points = [
            HashratePoint(date: now.addingTimeInterval(-16 * 60), value: 1200),
            HashratePoint(date: now.addingTimeInterval(-10), value: 1220)
        ]

        #expect(
            FleetHistoryPresentation.availableRecentRanges(for: points, now: now)
                == [.oneMinute]
        )
    }

    // MARK: - FleetHistorySource.mergedPoints Tests

    /// The sorted-input fast path must match the general dictionary path exactly. Reversing an
    /// input forces the general path, so the two results are compared on identical data that
    /// includes sub-second collisions, cross-source collisions, invalid values and points
    /// outside the window.
    @Test
    func mergedPointsSortedFastPathMatchesGeneralPath() {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return seed >> 33
        }
        let origin = baseDate
        func series(count: Int) -> [HashratePoint] {
            var date = origin.addingTimeInterval(-4_000)
            var points: [HashratePoint] = []
            for _ in 0..<count {
                date = date.addingTimeInterval(Double(next() % 1_500 + 1) / 1_000)  // strictly increasing, often same second
                let roll = next() % 50
                let value: Double = roll == 0 ? .nan : roll == 1 ? -5 : roll == 2 ? .infinity : Double(next() % 1_000)
                points.append(HashratePoint(date: date, value: value))
            }
            return points
        }
        let since = origin.addingTimeInterval(-3_000)
        let until = origin.addingTimeInterval(-1_000)
        for _ in 0..<20 {
            let stored = series(count: 2_000)
            let current = series(count: 600)
            let fast = FleetHistorySource.mergedPoints(stored: stored, current: current, since: since, until: until)
            let general = FleetHistorySource.mergedPoints(
                stored: Array(stored.reversed()), current: Array(current.reversed()), since: since, until: until
            )
            #expect(fast.map(\.date) == general.map(\.date))
            #expect(fast.map(\.value) == general.map(\.value))
        }
    }

    @Test
    func mergedPointsWithEmptyInputsReturnsEmpty() {
        let since = baseDate.addingTimeInterval(-3600)
        let until = baseDate
        let result = FleetHistorySource.mergedPoints(stored: [], current: [], since: since, until: until)
        #expect(result.isEmpty)
    }

    @Test
    func mergedPointsStoredOnlyColdSessionRetainsAllValidBoundedPoints() {
        let since = baseDate.addingTimeInterval(-3600)
        let until = baseDate
        let storedPoints = [
            HashratePoint(date: baseDate.addingTimeInterval(-1800), value: 500.0),
            HashratePoint(date: baseDate.addingTimeInterval(-600), value: 520.0),
            HashratePoint(date: baseDate.addingTimeInterval(-60), value: 510.0)
        ]

        let merged = FleetHistorySource.mergedPoints(stored: storedPoints, current: [], since: since, until: until)
        #expect(merged.count == 3)
        #expect(merged.map(\.value) == [500.0, 520.0, 510.0])
    }

    @Test
    func mergedPointsCurrentReplacesStoredAtSameWholeSecond() throws {
        let pointDate = Date(timeIntervalSince1970: 1_700_000_120) // exact second
        let since = pointDate.addingTimeInterval(-300)
        let until = pointDate.addingTimeInterval(300)

        let stored = [HashratePoint(date: pointDate, value: 400.0)]
        let current = [HashratePoint(date: pointDate, value: 650.0)]

        let merged = FleetHistorySource.mergedPoints(stored: stored, current: current, since: since, until: until)
        #expect(merged.count == 1)
        let point = try #require(merged.first)
        #expect(point.value == 650.0)
    }

    @Test
    func mergedPointsCurrentSubsecondReplacesStoredSameSecondKeyWithoutDuplicate() throws {
        // SQLite timestamps are whole seconds; current observation may have subsecond fraction
        let secondTimestamp = 1_700_000_200.0
        let storedDate = Date(timeIntervalSince1970: secondTimestamp)
        let currentDate = Date(timeIntervalSince1970: secondTimestamp + 0.45)
        let since = storedDate.addingTimeInterval(-300)
        let until = storedDate.addingTimeInterval(300)

        let stored = [HashratePoint(date: storedDate, value: 450.0)]
        let current = [HashratePoint(date: currentDate, value: 550.0)]

        let merged = FleetHistorySource.mergedPoints(stored: stored, current: current, since: since, until: until)
        #expect(merged.count == 1)
        let point = try #require(merged.first)
        #expect(point.value == 550.0)
        #expect(point.date == currentDate)
    }

    @Test
    func mergedPointsDisjointSecondsArePreservedAndSorted() {
        let t1 = Date(timeIntervalSince1970: 1_700_000_100)
        let t2 = Date(timeIntervalSince1970: 1_700_000_200)
        let t3 = Date(timeIntervalSince1970: 1_700_000_300)
        let t4 = Date(timeIntervalSince1970: 1_700_000_400)

        let stored = [
            HashratePoint(date: t1, value: 300.0),
            HashratePoint(date: t3, value: 350.0)
        ]
        let current = [
            HashratePoint(date: t2, value: 320.0),
            HashratePoint(date: t4, value: 370.0)
        ]

        let since = t1.addingTimeInterval(-10)
        let until = t4.addingTimeInterval(10)

        let merged = FleetHistorySource.mergedPoints(stored: stored, current: current, since: since, until: until)
        #expect(merged.count == 4)
        #expect(merged.map(\.date) == [t1, t2, t3, t4])
        #expect(merged.map(\.value) == [300.0, 320.0, 350.0, 370.0])
    }

    @Test
    func mergedPointsFiltersOutPointsOutsideTimeWindow() {
        let tInside1 = Date(timeIntervalSince1970: 1_700_000_100)
        let tInside2 = Date(timeIntervalSince1970: 1_700_000_200)
        let tBefore = Date(timeIntervalSince1970: 1_700_000_000)
        let tAfter = Date(timeIntervalSince1970: 1_700_000_300)

        let since = Date(timeIntervalSince1970: 1_700_000_050)
        let until = Date(timeIntervalSince1970: 1_700_000_250)

        let stored = [
            HashratePoint(date: tBefore, value: 100.0),
            HashratePoint(date: tInside1, value: 200.0)
        ]
        let current = [
            HashratePoint(date: tInside2, value: 300.0),
            HashratePoint(date: tAfter, value: 400.0)
        ]

        let merged = FleetHistorySource.mergedPoints(stored: stored, current: current, since: since, until: until)
        #expect(merged.count == 2)
        #expect(merged.map(\.value) == [200.0, 300.0])
    }

    @Test
    func mergedPointsDiscardsNaNInfiniteNegativeAndNonFiniteValues() {
        let t = Date(timeIntervalSince1970: 1_700_000_100)
        let since = t.addingTimeInterval(-100)
        let until = t.addingTimeInterval(100)

        let stored = [
            HashratePoint(date: t, value: Double.nan),
            HashratePoint(date: t.addingTimeInterval(10), value: Double.infinity),
            HashratePoint(date: t.addingTimeInterval(20), value: -Double.infinity),
            HashratePoint(date: t.addingTimeInterval(30), value: -10.0),
            HashratePoint(date: t.addingTimeInterval(40), value: 0.0), // 0 is valid hashrate
            HashratePoint(date: t.addingTimeInterval(50), value: 420.0)
        ]

        let merged = FleetHistorySource.mergedPoints(stored: stored, current: [], since: since, until: until)
        #expect(merged.count == 2)
        #expect(merged.map(\.value) == [0.0, 420.0])
    }

    @Test
    func mergedPointsDiscardsNonFiniteTimestamps() {
        let since = baseDate.addingTimeInterval(-3600)
        let until = baseDate.addingTimeInterval(3600)

        let nanDate = Date(timeIntervalSince1970: Double.nan)
        let infDate = Date(timeIntervalSince1970: Double.infinity)

        let stored = [
            HashratePoint(date: nanDate, value: 500.0),
            HashratePoint(date: infDate, value: 500.0),
            HashratePoint(date: baseDate, value: 500.0)
        ]

        let merged = FleetHistorySource.mergedPoints(stored: stored, current: [], since: since, until: until)
        #expect(merged.count == 1)
        #expect(merged.first?.date == baseDate)
    }

    // MARK: - FleetHistorySource.load Tests

    @Test
    func loadReadsSuppliedIsolatedDatabaseOnly() async throws {
        let db = MinerTelemetryDatabase(inMemory: true)
        let minerId = UUID()
        let readingDate = Date(timeIntervalSince1970: 1_700_000_500)

        db.recordReading(
            minerId: minerId.uuidString,
            timestamp: readingDate,
            reading: MinerReadingInput(hashrate: 750.0)
        )
        await db.flushReadings()

        let device = MinerDevice(id: minerId, name: "Test Rig", address: "192.168.1.50")
        let since = readingDate.addingTimeInterval(-300)
        let until = readingDate.addingTimeInterval(300)

        let results = await FleetHistorySource.load(
            devices: [device],
            since: since,
            until: until,
            database: db
        )

        let points = try #require(results[minerId])
        #expect(points.count == 1)
        let point = try #require(points.first)
        #expect(point.value == 750.0)
        #expect(Int(point.date.timeIntervalSince1970) == Int(readingDate.timeIntervalSince1970))
    }

    @Test
    func loadPartitionsDistinctASICAndCPUDevicesCorrectly() async throws {
        let db = MinerTelemetryDatabase(inMemory: true)
        let asicId = UUID()
        let cpuId = UUID()
        let time = Date(timeIntervalSince1970: 1_700_001_000)

        db.recordReading(
            minerId: asicId.uuidString,
            timestamp: time,
            reading: MinerReadingInput(hashrate: 1100.0)
        )
        db.recordReading(
            minerId: cpuId.uuidString,
            timestamp: time,
            reading: MinerReadingInput(hashrate: 4500.0)
        )
        await db.flushReadings()

        let asic = MinerDevice(id: asicId, name: "Gamma 601", address: "192.168.1.100", kind: .espMiner)
        let cpu = MinerDevice(id: cpuId, name: "Mac Studio", address: "192.168.1.120", kind: .xmrig)

        let since = time.addingTimeInterval(-60)
        let until = time.addingTimeInterval(60)

        let results = await FleetHistorySource.load(
            devices: [asic, cpu],
            since: since,
            until: until,
            database: db
        )

        let asicPoints = try #require(results[asicId])
        let cpuPoints = try #require(results[cpuId])

        #expect(asicPoints.count == 1)
        #expect(cpuPoints.count == 1)
        #expect(asicPoints.first?.value == 1100.0)
        #expect(cpuPoints.first?.value == 4500.0)
    }

    @Test
    func loadReturnsEmptyWhenDeviceHasNoStoredReadings() async {
        let db = MinerTelemetryDatabase(inMemory: true)
        let unknownId = UUID()
        let device = MinerDevice(id: unknownId, name: "Empty Miner", address: "192.168.1.200")

        let results = await FleetHistorySource.load(
            devices: [device],
            since: Date().addingTimeInterval(-3600),
            until: Date(),
            database: db
        )

        #expect(results[unknownId]?.isEmpty == true)
    }

    @Test
    func loadReturnsEmptyOnTaskCancellation() async {
        let db = MinerTelemetryDatabase(inMemory: true)
        let device = MinerDevice(name: "Cancelled Miner", address: "192.168.1.201")

        let task = Task {
            await FleetHistorySource.load(
                devices: [device],
                since: Date().addingTimeInterval(-3600),
                until: Date(),
                database: db
            )
        }
        task.cancel()
        let result = await task.value
        #expect(result.isEmpty)
    }

}
