import Foundation
import Testing
import HashFleetCore
#if os(macOS)
@testable import HashFleetMac
#else
@testable import HashFleet
#endif

@Suite("History rendering regression", .serialized)
struct FleetHistoryRenderingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000.5)

    // Frozen pre-optimization algorithms are independent oracles, not replacement acceptance rules.
    private func originalMerge(_ stored: [HashratePoint], _ current: [HashratePoint], since: Date, until: Date) -> [HashratePoint] {
        var readings: [Int: HashratePoint] = [:]
        for source in [stored, current] {
            for point in source.filter({ $0.value.isFinite && $0.value >= 0 && $0.date >= since && $0.date <= until })
                .sorted(by: { $0.date < $1.date }) {
                let seconds = point.date.timeIntervalSince1970
                guard seconds.isFinite, seconds >= Double(Int.min), seconds < Double(Int.max) else { continue }
                readings[Int(seconds)] = point
            }
        }
        return readings.values.sorted { $0.date < $1.date }
    }

    private func originalRanges(_ points: [HashratePoint], now: Date, minimumCoverage: TimeInterval = 0) -> [FleetRecentRange] {
        let dates = points.filter { $0.value.isFinite && $0.value >= 0 && $0.date <= now }.map(\.date).sorted()
        guard dates.count >= 2, let latest = dates.last else { return [.oneMinute] }
        var ranges: [FleetRecentRange] = [.oneMinute]
        for range in FleetRecentRange.allCases.dropFirst() {
            let window = dates.filter { $0 >= latest.addingTimeInterval(-range.interval) }
            guard let first = window.first, let last = window.last,
                  last.timeIntervalSince(first) >= max(range.interval, minimumCoverage) else { break }
            ranges.append(range)
        }
        return ranges
    }

    @Test func mergeRetainsLatestWithinSourceAndCurrentPriorityEvenWhenEarlier() {
        let second = Date(timeIntervalSince1970: 1_800_000_000)
        let stored = [
            HashratePoint(date: second.addingTimeInterval(0.9), value: 1),
            HashratePoint(date: second.addingTimeInterval(0.1), value: 2)
        ]
        let current = [
            HashratePoint(date: second.addingTimeInterval(0.4), value: 3),
            HashratePoint(date: second.addingTimeInterval(0.2), value: 4),
            HashratePoint(date: second.addingTimeInterval(0.4), value: 5)
        ]
        let result = FleetHistorySource.mergedPoints(
            stored: stored, current: current, since: second, until: second.addingTimeInterval(1)
        )
        #expect(result.count == 1)
        #expect(result.first?.date == second.addingTimeInterval(0.4))
        #expect(result.first?.value == 5)
    }

    @Test(arguments: 0..<24)
    func mergeMatchesOriginalForUnsortedDuplicatesBoundsAndInvalidValues(seed: Int) {
        let base = seed.isMultiple(of: 2) ? now : Date(timeIntervalSince1970: -12.5)
        let points = (0..<257).map { index in
            let permuted = (index * 53 + seed * 37) % 257
            let date = base.addingTimeInterval(Double(permuted % 65) / 8 - 4)
            let value = index.isMultiple(of: 19) ? Double.nan : (index.isMultiple(of: 23) ? -1 : Double(index))
            return HashratePoint(date: date, value: value)
        }
        let stored = points + [HashratePoint(date: Date(timeIntervalSince1970: .infinity), value: 1)]
        let current = Array(points.reversed()) + [HashratePoint(date: base, value: .infinity)]
        let since = base.addingTimeInterval(-3)
        let until = base.addingTimeInterval(3)
        let expected = originalMerge(stored, current, since: since, until: until)
        let result = FleetHistorySource.mergedPoints(stored: stored, current: current, since: since, until: until)
        #expect(result.map(\.date) == expected.map(\.date))
        #expect(result.map(\.value) == expected.map(\.value))
        #expect(FleetHistorySource.mergedPoints(stored: stored, current: current, since: until, until: since).isEmpty)
    }

    @Test(arguments: [0.0, 900.0, 901.0, 10_000.0])
    func rangeScanMatchesOriginalForExactCoverageGapsAndInvalidReadings(minimumCoverage: TimeInterval) {
        for shift in [0.0, 0.01, 60.0, 901.0] {
            let points = [0.0, -60, -900, -3_600, -86_400, -86_401, 1].map {
                HashratePoint(date: now.addingTimeInterval($0 + shift), value: 1_000)
            } + [HashratePoint(date: now.addingTimeInterval(-900), value: .nan)]
            for subset in [points, Array(points.reversed()), Array(points.prefix(1)), []] {
                #expect(FleetHistoryPresentation.availableRecentRanges(for: subset, now: now, minimumCoverage: minimumCoverage)
                    == originalRanges(subset, now: now, minimumCoverage: minimumCoverage))
            }
        }
    }

    private func identity(revision: Int = 1, kind: FleetHistoryKind = .sha256,
                          live: [MinerHistorySignature] = [], stored: [MinerHistorySignature] = []) -> FleetHistoryRangeIdentity {
        FleetHistoryRangeIdentity(kind: kind, currentSignatures: live, storedSignatures: stored, storedRevision: revision)
    }

    @Test func rangeCacheReusesUnchangedInputsAndInvalidatesAtTimeBoundaryOrClockRollback() {
        let cache = FleetHistoryRangeCache()
        var calls = 0
        let make = {
            calls += 1
            return (ranges: [FleetRecentRange.oneMinute, .fifteenMinutes], expiration: now.addingTimeInterval(1))
        }
        for _ in 0..<100 {
            #expect(cache.resolve(identity(), now: now, make: make) == [.oneMinute, .fifteenMinutes])
        }
        #expect(calls == 1)
        _ = cache.resolve(identity(), now: now.addingTimeInterval(0.999), make: make)
        #expect(calls == 1)
        _ = cache.resolve(identity(), now: now.addingTimeInterval(1), make: make)
        #expect(calls == 2)
        _ = cache.resolve(identity(), now: now.addingTimeInterval(-1), make: make)
        #expect(calls == 3)
    }

    @Test func rangeCacheInvalidatesForDataRevisionAlgorithmMembershipAndCappedLiveUpdates() {
        let cache = FleetHistoryRangeCache()
        let id = UUID()
        let first = [HashratePoint(date: now.addingTimeInterval(-10), value: 1), HashratePoint(date: now, value: 2)]
        let rolled = [HashratePoint(date: now, value: 2), HashratePoint(date: now.addingTimeInterval(10), value: 3)]
        let a = MinerHistorySignature(id: id, history: first, updatedAt: now)
        let b = MinerHistorySignature(id: id, history: rolled, updatedAt: now.addingTimeInterval(10))
        var calls = 0
        let make = {
            calls += 1
            return (ranges: [FleetRecentRange.oneMinute], expiration: Date.distantFuture)
        }
        let identities = [
            identity(live: [a]), identity(revision: 2, live: [a]),
            identity(revision: 2, kind: .cpu, live: [a]), identity(revision: 2, kind: .cpu, live: [b]),
            identity(revision: 2, kind: .cpu), identity(revision: 2, kind: .cpu, stored: [a])
        ]
        for input in identities {
            _ = cache.resolve(input, now: now, make: make)
            _ = cache.resolve(input, now: now, make: make)
        }
        #expect(calls == identities.count)
    }

    @Test func expirationIncludesFutureAdmissionsShadowedReadingsAndInclusiveLowerBound() {
        let oldest = HashratePoint(date: now.addingTimeInterval(-86_400), value: 1)
        let later = HashratePoint(date: now.addingTimeInterval(-86_399), value: 2)
        let future = HashratePoint(date: now.addingTimeInterval(0.25), value: 3)
        let invalid = HashratePoint(date: now.addingTimeInterval(0.01), value: .nan)
        #expect(FleetHistorySource.recentRangeExpiration(sources: [[oldest, later], [future, invalid]], now: now) == now)
        #expect(FleetHistorySource.recentRangeExpiration(sources: [[oldest, later], [future, invalid]], now: now.addingTimeInterval(0.001)) == future.date)
        #expect(FleetHistorySource.recentRangeExpiration(sources: [[invalid]], now: now) == .distantFuture)
    }

    @Test func cachedAvailabilityMatchesOriginalAcrossAgingFuturePointsAndSameSecondOverrides() {
        let cache = FleetHistoryRangeCache()
        let stored = [-86_400.0, -3_600, -900, 0, 1].map {
            HashratePoint(date: now.addingTimeInterval($0), value: 100)
        }
        let current = [HashratePoint(date: now.addingTimeInterval(-0.25), value: 200)]
        for offset in [0.0, 0.001, 0.2, 0.999, 1.0, 1.001, 900, 86_401, -1] {
            let time = now.addingTimeInterval(offset)
            let actual = cache.resolve(identity(), now: time) {
                let merged = FleetHistorySource.mergedPoints(stored: stored, current: current, since: time.addingTimeInterval(-86_400), until: time)
                return (FleetHistoryPresentation.availableRecentRanges(for: merged, now: time),
                        FleetHistorySource.recentRangeExpiration(sources: [stored, current], now: time))
            }
            let merged = originalMerge(stored, current, since: time.addingTimeInterval(-86_400), until: time)
            #expect(actual == originalRanges(merged, now: time))
        }
    }

    @Test func pageCacheInvalidatesWhenLoadedValuesChangeWithoutChangingCountOrDates() {
        let cache = FleetHistoryPageCache()
        let id = UUID()
        let signature = MinerHistorySignature(id: id, history: [HashratePoint(date: now, value: 1)])
        var calls = 0
        for revision in [1, 1, 2, 2] {
            let input = FleetHistoryPageIdentity(window: .daily, recentRange: .hour, displayMode: .fleet,
                kind: .sha256, currentSignatures: [], storedSignatures: [signature], storedRevision: revision, deviceMetadata: [])
            let result = cache.resolve(input) {
                calls += 1
                return ([MinerHistorySeries(id: id, name: "Fixture", points: [HashratePoint(date: now, value: Double(revision))])], nil)
            }
            #expect(result.histories.first?.points.first?.value == Double(revision))
        }
        #expect(calls == 2)
    }

    @Test func representativeFourMinerHistoryRetainsFullResolutionAndAvoidsRepeatedDerivation() {
        let stored = (0..<110_000).map { index in
            HashratePoint(date: now.addingTimeInterval(-86_399 + Double(index) * 0.78), value: 1_000 + Double(index % 71))
        }
        let current = (0..<360).map { index in
            HashratePoint(date: now.addingTimeInterval(-359 + Double(index)), value: 1_100 + Double(index % 29))
        }
        let expected = originalMerge(stored, current, since: now.addingTimeInterval(-86_400), until: now)
        let expectedRanges = originalRanges(expected, now: now)
        let cache = FleetHistoryRangeCache()
        var calls = 0
        let start = ContinuousClock.now
        for _ in 0..<100 {
            let ranges = cache.resolve(identity(), now: now) {
                calls += 1
                var points: [HashratePoint] = []
                for _ in 0..<4 {
                    let merged = FleetHistorySource.mergedPoints(stored: stored, current: current, since: now.addingTimeInterval(-86_400), until: now)
                    #expect(merged.map(\.date) == expected.map(\.date))
                    #expect(merged.map(\.value) == expected.map(\.value))
                    points.append(contentsOf: merged)
                }
                return (FleetHistoryPresentation.availableRecentRanges(for: points, now: now),
                        FleetHistorySource.recentRangeExpiration(sources: [stored, current], now: now))
            }
            #expect(ranges == expectedRanges)
        }
        #expect(calls == 1)
        print("4x110000 fixture,100 range resolutions,1 derivation: \(start.duration(to: .now))")
    }
}

@Suite("Bounded chart rendering", .serialized)
struct FleetHistoryChartBudgetTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func samePoint(_ lhs: HashratePoint?, _ rhs: HashratePoint?) -> Bool {
        lhs?.date == rhs?.date && lhs?.value == rhs?.value
    }

    private func samePoints(_ lhs: [HashratePoint], _ rhs: [HashratePoint]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { samePoint($0, $1) }
    }

    private func contains(_ points: [HashratePoint], _ point: HashratePoint) -> Bool {
        points.contains { samePoint($0, point) }
    }

    private func fragmentedHistory() -> (MinerHistorySeries, [FleetHistorySegment]) {
        let segments = (0..<128).map { segment in
            FleetHistorySegment(id: segment, points: (0..<96).map { index in
                HashratePoint(
                    date: base.addingTimeInterval(Double(segment * 1_200 + index * 5)),
                    value: 2_500 + sin(Double(segment * 96 + index) / 7) * 120
                )
            })
        }
        return (MinerHistorySeries(name: "Offline fixture", points: segments.flatMap(\.points)), segments)
    }

    @Test(arguments: [-2, 0, 1, 2, 3, 4, 5, 48, 180, 20_000])
    func samplingAlwaysHonorsTheRequestedBudget(budget: Int) {
        let (history, segments) = fragmentedHistory()
        let rendered = FleetHistoryChartSeries(history: history, segments: segments, maximumCount: budget)
        let limit = max(0, budget)
        #expect(rendered.history.points.count <= limit)
        #expect(samePoints(rendered.history.points, rendered.segments.flatMap(\.points)))
        #expect(rendered.id == history.id)
        #expect(rendered.history.name == history.name)
        #expect(history.points.count == 12_288, "Rendering must not mutate full-resolution history")
        if budget == 1 {
            #expect(samePoints(rendered.history.points, [history.points.last!]))
        } else if budget >= 2 {
            #expect(samePoint(rendered.history.points.first, history.points.first))
            #expect(samePoint(rendered.history.points.last, history.points.last))
        } else {
            #expect(rendered.segments.isEmpty)
        }
        for segment in rendered.segments {
            let original = segments.first { $0.id == segment.id }!
            #expect(segment.points.allSatisfy { contains(original.points, $0) },
                    "A rendered line must never bridge different recorded segments")
        }
    }

    @Test func fragmentedFleetUsesOneBudgetRatherThanOnePerSegment() {
        let (history, segments) = fragmentedHistory()
        for budget in [FleetHistoryPresentation.dashboardChartPointBudget,
                       FleetHistoryPresentation.detailChartPointBudget] {
            let legacyCount = segments.reduce(0) {
                $0 + FleetHistoryPresentation.sampledPoints($1.points, maximumCount: budget).count
            }
            #expect(legacyCount > budget, "Positive control must exercise the former budget overflow")
            let rendered = FleetHistoryChartSeries(history: history, segments: segments, maximumCount: budget)
            #expect(rendered.history.points.count <= budget)
            #expect(Set(rendered.segments.map(\.id)).count == rendered.segments.count)
        }
    }

    @Test func continuousDayDoesNotAcquireGapsFromDownsampling() throws {
        let points = (0...1_440).map {
            HashratePoint(date: base.addingTimeInterval(Double($0) * 60), value: Double(2_000 + $0 % 20))
        }
        let rendered = FleetHistoryChartSeries(
            history: MinerHistorySeries(name: "Continuous recording", points: points), maximumCount: 48
        )
        #expect(rendered.segments.count == 1)
        let segment = try #require(rendered.segments.first)
        #expect(segment.points.count <= 48)
        #expect(samePoint(segment.points.first, points.first))
        #expect(samePoint(segment.points.last, points.last))
        #expect(zip(segment.points, segment.points.dropFirst()).contains {
            $1.date.timeIntervalSince($0.date) > FleetHistoryPresentation.maximumConnectedGap
        }, "The fixture must expose the false gaps created by segmenting after downsampling")
    }

    @Test func explicitAlignmentInterruptionsSurviveEvenWhenTheirDatesAreClose() {
        let points = (0..<4).map {
            HashratePoint(date: base.addingTimeInterval(Double($0) * 10), value: Double($0))
        }
        let history = MinerHistorySeries(name: "Interrupted alignment", points: points)
        let segments = [FleetHistorySegment(id: 11, points: Array(points.prefix(2))),
                        FleetHistorySegment(id: 29, points: Array(points.suffix(2)))]
        let rendered = FleetHistoryChartSeries(history: history, segments: segments, maximumCount: 48)
        #expect(rendered.segments.map(\.id) == [11, 29])
        #expect(zip(rendered.segments, segments).allSatisfy { samePoints($0.points, $1.points) })
        #expect(FleetHistoryChartSeries(history: history, segments: [], maximumCount: 48).segments.isEmpty)
    }

    @Test func rollingPayloadKeepsSeriesIdentityAndFullResolutionInspection() throws {
        let id = UUID()
        for revision in 0..<100 {
            let points = (0..<240).map {
                HashratePoint(date: base.addingTimeInterval(Double(revision + $0) * 10),
                              value: 2_500 + sin(Double(revision + $0) / 7) * 120)
            }
            let source = MinerHistorySeries(id: id, name: "Rolling fixture", points: points)
            let rendered = FleetHistoryChartSeries(history: source, maximumCount: 48)
            #expect(rendered.id == id)
            #expect(rendered.segments.map(\.id) == [0])
            #expect(rendered.history.points.count <= 48)
            let omitted = try #require(points.first { !contains(rendered.history.points, $0) })
            let selection = try #require(FleetChartSelection.resolve(
                at: omitted.date, in: [source], tolerance: 0, clusterTolerance: 0
            ))
            #expect(selection.selectedDate == omitted.date)
            #expect(selection.seriesValues.first?.value == omitted.value)
            #expect(samePoints(source.points, points))
        }
    }

    @Test(arguments: [-1, 0, 1, 2, 3, 4, 5, 6, 7, 48])
    func emptyAndShortInputsRemainBounded(budget: Int) {
        for count in 0...9 {
            let points = (0..<count).map {
                HashratePoint(date: base.addingTimeInterval(Double($0)), value: Double($0))
            }
            let sampled = FleetHistoryPresentation.sampledPoints(points, maximumCount: budget)
            #expect(sampled.count <= min(count, max(0, budget)))
            #expect(sampled.allSatisfy { contains(points, $0) })
            if budget >= count { #expect(samePoints(sampled, points)) }
        }
    }
}
