import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// Independent unit tests for native history presentation:
/// - FleetHistoryKind (availability, device filtering, totals, offline/reconnecting filtering, zero vs absent)
/// - Hashrate normalization and algorithm-aware unit formatting (SHA-256 TH/s vs CPU H/s, kH/s)
/// - FleetHistoryPresentation (boundedPoints filtering & sorting, segmentation gap rules, per-sample mean)
/// - Scoped chart selection preventing cross-algorithm pollution and stale/rollover handling
@MainActor
struct NativeHistoryPresentationTests {
    fileprivate let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - FleetHistoryKind Availability & Scoping

    @Test
    func fleetHistoryKindProperties() {
        #expect(FleetHistoryKind.sha256.id == "sha256")
        #expect(FleetHistoryKind.sha256.title == "SHA-256")
        #expect(FleetHistoryKind.sha256.deviceKind == .espMiner)
        #expect(FleetHistoryKind.cpu.id == "cpu")
        #expect(FleetHistoryKind.cpu.title == "CPU · XMRig")
        #expect(FleetHistoryKind.cpu.deviceKind == .xmrig)
    }

    @Test
    func availableKindsWithEmptyDevicesReturnsEmpty() {
        #expect(FleetHistoryKind.available(in: []).isEmpty)
    }

    @Test
    func availableKindsWithOnlyESPMinerReturnsOnlySHA256() {
        let devices = [
            MinerDevice(name: "Rig 1", address: "192.168.1.10", kind: .espMiner),
            MinerDevice(name: "Rig 2", address: "192.168.1.11", kind: .espMiner)
        ]
        #expect(FleetHistoryKind.available(in: devices) == [.sha256])
    }

    @Test
    func availableKindsWithOnlyXMRigReturnsOnlyCPU() {
        let devices = [MinerDevice(name: "Mac Host", address: "192.168.1.20", kind: .xmrig)]
        #expect(FleetHistoryKind.available(in: devices) == [.cpu])
    }

    @Test
    func availableKindsWithMixedFleetReturnsBothInCaseIterableOrder() {
        let devices = [
            MinerDevice(name: "Mac Host", address: "192.168.1.20", kind: .xmrig),
            MinerDevice(name: "Rig 1", address: "192.168.1.10", kind: .espMiner)
        ]
        #expect(FleetHistoryKind.available(in: devices) == [.sha256, .cpu])
    }

    @Test
    func devicesFilteringPartitionsByKind() {
        let sha1 = MinerDevice(name: "Gamma", address: "192.168.1.10", kind: .espMiner)
        let sha2 = MinerDevice(name: "Naja", address: "192.168.1.11", kind: .espMiner)
        let cpu1 = MinerDevice(name: "Mac Mini", address: "192.168.1.20", kind: .xmrig)
        let fleet = [sha1, cpu1, sha2]

        #expect(FleetHistoryKind.sha256.devices(in: fleet) == [sha1, sha2])
        #expect(FleetHistoryKind.cpu.devices(in: fleet) == [cpu1])
        #expect(FleetHistoryKind.cpu.devices(in: [sha1, sha2]).isEmpty)
    }

    // MARK: - FleetHistoryKind Totals & Status Boundaries

    @Test
    func totalsExcludesOfflineAndReconnectingDevices() {
        let healthy = MinerDevice(name: "Healthy", address: "10.0.0.1", kind: .espMiner)
        let reconnecting = MinerDevice(name: "Reconnecting", address: "10.0.0.2", kind: .espMiner)
        let errored = MinerDevice(name: "Errored", address: "10.0.0.3", kind: .espMiner)
        let offline = MinerDevice(name: "Offline", address: "10.0.0.4", kind: .espMiner)
        let unpolled = MinerDevice(name: "Unpolled", address: "10.0.0.5", kind: .espMiner)

        let snapshots: [UUID: MinerSnapshot] = [
            healthy.id: MinerSnapshot(
                info: MinerInfo(raw: ["hashRate": .number(1200.0), "power": .number(18.0)]),
                error: nil, isReconnecting: false
            ),
            reconnecting.id: MinerSnapshot(
                info: MinerInfo(raw: ["hashRate": .number(1200.0), "power": .number(18.0)]),
                error: nil, isReconnecting: true
            ),
            errored.id: MinerSnapshot(
                info: MinerInfo(raw: ["hashRate": .number(1200.0), "power": .number(18.0)]),
                error: "Host unreachable", isReconnecting: false
            ),
            offline.id: MinerSnapshot(info: nil, error: nil, isReconnecting: false)
        ]

        let devices = [healthy, reconnecting, errored, offline, unpolled]
        let totals = FleetHistoryKind.sha256.totals(devices: devices, snapshots: snapshots)

        #expect(totals.hashrate.online == 1)
        #expect(totals.hashrate.reporting == 1)
        #expect(totals.hashrate.value == 1200.0)
        #expect(totals.power.online == 1)
        #expect(totals.power.reporting == 1)
        #expect(totals.power.value == 18.0)
    }

    @Test
    func totalsDistinguishesZeroHashrateFromAbsentHashrate() {
        let devZero = MinerDevice(name: "ZeroHash", address: "10.0.0.1", kind: .espMiner)
        let devAbsent = MinerDevice(name: "AbsentHash", address: "10.0.0.2", kind: .espMiner)

        let snapZero = MinerSnapshot(
            info: MinerInfo(raw: ["hashRate": .number(0.0), "power": .number(15.0)]),
            error: nil, isReconnecting: false
        )
        let snapAbsent = MinerSnapshot(
            info: MinerInfo(raw: ["power": .number(15.0)]),
            error: nil, isReconnecting: false
        )

        let totalsZero = FleetHistoryKind.sha256.totals(devices: [devZero], snapshots: [devZero.id: snapZero])
        #expect(totalsZero.hashrate.online == 1)
        #expect(totalsZero.hashrate.reporting == 1)
        #expect(totalsZero.hashrate.value == 0.0)
        #expect(totalsZero.hashrate.hasReading == true)

        let totalsAbsent = FleetHistoryKind.sha256.totals(devices: [devAbsent], snapshots: [devAbsent.id: snapAbsent])
        #expect(totalsAbsent.hashrate.online == 1)
        #expect(totalsAbsent.hashrate.reporting == 0)
        #expect(totalsAbsent.hashrate.value == 0.0)
        #expect(totalsAbsent.hashrate.hasReading == false)
    }

    @Test
    func totalsMissingPowerYieldsNoEfficiency() {
        let cpuDev = MinerDevice(name: "MacBook Pro", address: "10.0.0.20", kind: .xmrig)
        let cpuSnapshot = MinerSnapshot(
            info: MinerInfo(raw: ["hashRate": .number(0.00000214)]),
            error: nil, isReconnecting: false
        )

        let cpuTotals = FleetHistoryKind.cpu.totals(devices: [cpuDev], snapshots: [cpuDev.id: cpuSnapshot])
        #expect(cpuTotals.hashrate.online == 1)
        #expect(cpuTotals.hashrate.reporting == 1)
        #expect(cpuTotals.hashrate.value == 0.00000214)
        #expect(cpuTotals.power.online == 1)
        #expect(cpuTotals.power.reporting == 0)
        #expect(cpuTotals.power.hasReading == false)
        #expect(cpuTotals.power.value == 0.0)
        #expect(cpuTotals.efficiency.hasReading == false)
        #expect(cpuTotals.efficiency.value == nil)
        #expect(!cpuTotals.isPublishable)
    }

    @Test
    func totalsSeparatesSHA256FromNormalizedCPUGigaHashes() {
        let asic = MinerDevice(name: "Gamma 602", address: "192.0.2.215", kind: .espMiner)
        let mac = MinerDevice(name: "MacBook M1", address: "192.0.2.127", kind: .xmrig)

        let asicSnap = MinerSnapshot(
            info: MinerInfo(raw: ["hashRate": .number(1500.0), "power": .number(18.5)]),
            error: nil, isReconnecting: false
        )
        let macSnap = MinerSnapshot(
            info: MinerInfo(raw: ["hashRate": .number(0.00000214)]),
            error: nil, isReconnecting: false
        )

        let devices = [asic, mac]
        let snapshots = [asic.id: asicSnap, mac.id: macSnap]

        let shaTotals = FleetHistoryKind.sha256.totals(devices: devices, snapshots: snapshots)
        #expect(shaTotals.hashrate.online == 1)
        #expect(shaTotals.hashrate.reporting == 1)
        #expect(shaTotals.hashrate.value == 1500.0)
        #expect(shaTotals.power.value == 18.5)

        let cpuTotals = FleetHistoryKind.cpu.totals(devices: devices, snapshots: snapshots)
        #expect(cpuTotals.hashrate.online == 1)
        #expect(cpuTotals.hashrate.reporting == 1)
        #expect(cpuTotals.hashrate.value == 0.00000214)
        #expect(cpuTotals.power.value == 0.0)

        #expect(shaTotals.hashrate.value != 1500.00000214)
        #expect(cpuTotals.hashrate.value < 1.0)
    }

    // MARK: - CPU Hashrate Unit Formatting Across Scales

    @Test(arguments: [
        (0.000_000_123, "123.00 H/s"),
        (0.000_002_139_09, "2.14 kH/s"),
        (0.000_123, "123.00 kH/s"),
        (0.000_999_99, "999.99 kH/s"),
        (0.001, "1 MH/s")
    ])
    func cpuNormalizedRateFormattingAcrossScales(rateGHs: Double, expected: String) {
        #expect(FleetFormat.hashrateWithUnit(rateGHs) == expected)
    }
}

// MARK: - Bounded Points & Segmentation Extension

extension NativeHistoryPresentationTests {
    @Test
    func boundedPointsExcludesPointsOutsideDateWindow() {
        let since = baseDate.addingTimeInterval(100)
        let until = baseDate.addingTimeInterval(500)

        let points = [
            HashratePoint(date: baseDate.addingTimeInterval(50), value: 1000.0),
            HashratePoint(date: since, value: 1100.0),
            HashratePoint(date: baseDate.addingTimeInterval(250), value: 1200.0),
            HashratePoint(date: until, value: 1300.0),
            HashratePoint(date: baseDate.addingTimeInterval(600), value: 1400.0)
        ]

        let bounded = FleetHistoryPresentation.boundedPoints(points, since: since, until: until)
        #expect(bounded.count == 3)
        #expect(bounded[0].date == since)
        #expect(bounded[0].value == 1100.0)
        #expect(bounded[1].value == 1200.0)
        #expect(bounded[2].date == until)
        #expect(bounded[2].value == 1300.0)
    }

    @Test
    func boundedPointsInvertedDateRangeReturnsEmpty() {
        let since = baseDate.addingTimeInterval(200)
        let until = baseDate.addingTimeInterval(100)
        let points = [HashratePoint(date: baseDate.addingTimeInterval(150), value: 1000.0)]
        #expect(FleetHistoryPresentation.boundedPoints(points, since: since, until: until).isEmpty)
    }

    @Test
    func boundedPointsSortsUnorderedPointsAscending() {
        let p1 = HashratePoint(date: baseDate.addingTimeInterval(300), value: 1300.0)
        let p2 = HashratePoint(date: baseDate.addingTimeInterval(100), value: 1100.0)
        let p3 = HashratePoint(date: baseDate.addingTimeInterval(400), value: 1400.0)
        let p4 = HashratePoint(date: baseDate.addingTimeInterval(200), value: 1200.0)

        let bounded = FleetHistoryPresentation.boundedPoints(
            [p1, p2, p3, p4], since: baseDate, until: baseDate.addingTimeInterval(500)
        )
        #expect(bounded.map(\.value) == [1100.0, 1200.0, 1300.0, 1400.0])
        #expect(bounded.map(\.date) == [
            baseDate.addingTimeInterval(100),
            baseDate.addingTimeInterval(200),
            baseDate.addingTimeInterval(300),
            baseDate.addingTimeInterval(400)
        ])
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1.0, -0.0001])
    func boundedPointsFiltersOutInvalidValues(invalidValue: Double) {
        let points = [
            HashratePoint(date: baseDate, value: invalidValue),
            HashratePoint(date: baseDate.addingTimeInterval(10), value: 1000.0)
        ]
        let bounded = FleetHistoryPresentation.boundedPoints(
            points, since: baseDate.addingTimeInterval(-10), until: baseDate.addingTimeInterval(20)
        )
        #expect(bounded.count == 1)
        #expect(bounded.first?.value == 1000.0)
    }

    @Test
    func boundedPointsZeroHashrateIsRetained() {
        let zeroPoint = HashratePoint(date: baseDate, value: 0.0)
        let bounded = FleetHistoryPresentation.boundedPoints(
            [zeroPoint], since: baseDate.addingTimeInterval(-10), until: baseDate.addingTimeInterval(10)
        )
        #expect(bounded.count == 1)
        #expect(bounded.first?.value == 0.0)
    }

    @Test
    func segmentsEmptyInputReturnsEmpty() {
        #expect(FleetHistoryPresentation.segments([]).isEmpty)
    }

    @Test
    func segmentsSinglePointReturnsSingleSegment() {
        let pt = HashratePoint(date: baseDate, value: 1200.0)
        let segments = FleetHistoryPresentation.segments([pt])
        #expect(segments.count == 1)
        #expect(segments[0].id == 0)
        #expect(segments[0].points.count == 1)
        #expect(segments[0].points[0].value == 1200.0)
    }

    @Test
    func segmentsWithinMaximumGapRemainConnected() {
        let p1 = HashratePoint(date: baseDate, value: 1000.0)
        let p2 = HashratePoint(date: baseDate.addingTimeInterval(60), value: 1100.0)
        let p3 = HashratePoint(date: baseDate.addingTimeInterval(240), value: 1200.0)

        let segments = FleetHistoryPresentation.segments([p1, p2, p3])
        #expect(segments.count == 1)
        #expect(segments[0].points.count == 3)
    }

    @Test
    func segmentsGapAtExact300SecondBoundaryStaysConnected() {
        let p1 = HashratePoint(date: baseDate, value: 1000.0)
        let p2 = HashratePoint(date: baseDate.addingTimeInterval(300.0), value: 1100.0)
        let segments = FleetHistoryPresentation.segments([p1, p2])
        #expect(segments.count == 1)
        #expect(segments[0].points.count == 2)
    }

    @Test
    func segmentsGapExceeding300SecondsCreatesNewSegment() {
        let p1 = HashratePoint(date: baseDate, value: 1000.0)
        let p2 = HashratePoint(date: baseDate.addingTimeInterval(300.01), value: 1100.0)
        let p3 = HashratePoint(date: baseDate.addingTimeInterval(900.0), value: 1200.0)

        let segments = FleetHistoryPresentation.segments([p1, p2, p3])
        #expect(segments.count == 3)
        #expect(segments.map(\.id) == [0, 1, 2])
        #expect(segments.map(\.points.count) == [1, 1, 1])
    }

    @Test
    func segmentsSkipsInvalidPointsWithoutFalselyBreakingConnectedValidPoints() {
        let p1 = HashratePoint(date: baseDate, value: 1000.0)
        let pInvalid = HashratePoint(date: baseDate.addingTimeInterval(60), value: -50.0)
        let p2 = HashratePoint(date: baseDate.addingTimeInterval(120), value: 1100.0)

        let segments = FleetHistoryPresentation.segments([p1, pInvalid, p2])
        #expect(segments.count == 1)
        #expect(segments[0].points.count == 2)
        #expect(segments[0].points.map(\.value) == [1000.0, 1100.0])
    }

    @Test
    func segmentsSortsUnsortedInputBeforeSegmenting() {
        let p1 = HashratePoint(date: baseDate.addingTimeInterval(100), value: 1100.0)
        let p2 = HashratePoint(date: baseDate, value: 1000.0)
        let p3 = HashratePoint(date: baseDate.addingTimeInterval(500), value: 1200.0)

        let segments = FleetHistoryPresentation.segments([p1, p2, p3])
        #expect(segments.count == 2)
        #expect(segments[0].points.map(\.value) == [1000.0, 1100.0])
        #expect(segments[1].points.map(\.value) == [1200.0])
    }

    @Test
    func segmentsDoesNotInferContinuityAssurance() {
        let p1 = HashratePoint(date: baseDate, value: 1500.0)
        let p2 = HashratePoint(date: baseDate.addingTimeInterval(290), value: 1550.0)

        let segments = FleetHistoryPresentation.segments([p1, p2])
        #expect(segments.count == 1)
        #expect(segments[0].points.count == 2)
        #expect(FleetHistoryPresentation.maximumConnectedGap == 300.0)
    }
}

// MARK: - Mean Reading & Scoped Selection Extension

extension NativeHistoryPresentationTests {
    @Test
    func meanReadingIsPerSampleMeanNotFleetTotal() {
        let seriesA = MinerHistorySeries(
            id: UUID(), name: "Alpha",
            points: [HashratePoint(date: baseDate, value: 1200.0)]
        )
        let seriesB = MinerHistorySeries(
            id: UUID(), name: "Beta",
            points: [
                HashratePoint(date: baseDate, value: 200.0),
                HashratePoint(date: baseDate.addingTimeInterval(10), value: 400.0),
                HashratePoint(date: baseDate.addingTimeInterval(20), value: 600.0)
            ]
        )

        let mean = FleetHistoryPresentation.meanReading(in: [seriesA, seriesB])
        #expect(mean == 600.0, "meanReading must be a per-sample average across all points")
    }

    @Test
    func meanReadingIncludesZeroValues() {
        let series = MinerHistorySeries(
            name: "Intermittent",
            points: [
                HashratePoint(date: baseDate, value: 0.0),
                HashratePoint(date: baseDate.addingTimeInterval(10), value: 1000.0)
            ]
        )
        #expect(FleetHistoryPresentation.meanReading(in: [series]) == 500.0)
    }

    @Test
    func meanReadingFiltersOutNonFiniteAndNegativeValues() {
        let series = MinerHistorySeries(
            name: "Mixed",
            points: [
                HashratePoint(date: baseDate, value: 1000.0),
                HashratePoint(date: baseDate.addingTimeInterval(10), value: Double.nan),
                HashratePoint(date: baseDate.addingTimeInterval(20), value: Double.infinity),
                HashratePoint(date: baseDate.addingTimeInterval(30), value: -500.0),
                HashratePoint(date: baseDate.addingTimeInterval(40), value: 2000.0)
            ]
        )
        #expect(FleetHistoryPresentation.meanReading(in: [series]) == 1500.0)
    }

    @Test
    func meanReadingEmptyOrAllInvalidReturnsNil() {
        #expect(FleetHistoryPresentation.meanReading(in: []) == nil)
        #expect(FleetHistoryPresentation.meanReading(in: [MinerHistorySeries(name: "Empty", points: [])]) == nil)

        let invalidSeries = MinerHistorySeries(
            name: "Invalid",
            points: [
                HashratePoint(date: baseDate, value: Double.nan),
                HashratePoint(date: baseDate.addingTimeInterval(10), value: -100.0)
            ]
        )
        #expect(FleetHistoryPresentation.meanReading(in: [invalidSeries]) == nil)
    }

    @Test
    func selectionOnScopedHistoriesPreventsCrossAlgorithmPollution() {
        let asicSeries = MinerHistorySeries(
            id: UUID(), name: "Gamma 602",
            points: [HashratePoint(date: baseDate, value: 2000.0)]
        )
        let cpuSeries = MinerHistorySeries(
            id: UUID(), name: "MacBook M1",
            points: [HashratePoint(date: baseDate, value: 0.00000214)]
        )

        // 1. Unscoped sums both algorithms
        let unscoped = FleetChartSelection.resolve(at: baseDate, in: [asicSeries, cpuSeries], tolerance: 60)
        #expect(unscoped?.totalRate == 2000.00000214)

        // 2. Scoped to SHA-256
        let shaSelection = FleetChartSelection.resolve(at: baseDate, in: [asicSeries], tolerance: 60)
        #expect(shaSelection != nil)
        #expect(shaSelection?.totalRate == 2000.0)
        #expect(shaSelection?.formattedTotalRate == "2.00 TH/s")
        #expect(shaSelection?.seriesValues.first?.name == "Gamma 602")

        // 3. Scoped to CPU
        let cpuSelection = FleetChartSelection.resolve(at: baseDate, in: [cpuSeries], tolerance: 60)
        #expect(cpuSelection != nil)
        #expect(cpuSelection?.totalRate == 0.00000214)
        #expect(cpuSelection?.formattedTotalRate == "2.14 kH/s")
        #expect(cpuSelection?.seriesValues.first?.name == "MacBook M1")
    }

    @Test
    func selectionInvalidatedWhenActiveKindSwitches() throws {
        let shaSeries = MinerHistorySeries(
            id: UUID(), name: "Gamma",
            points: [HashratePoint(date: baseDate, value: 1500.0)]
        )
        let cpuSeries = MinerHistorySeries(
            id: UUID(), name: "Mac",
            points: [HashratePoint(date: baseDate.addingTimeInterval(7200), value: 0.00000214)]
        )

        let shaSelection = try #require(FleetChartSelection.resolve(at: baseDate, in: [shaSeries], tolerance: 60))

        let isValidForCPU = FleetChartSelection.isSelectionValid(
            at: shaSelection.selectedDate, in: [cpuSeries], tolerance: 60
        )
        #expect(!isValidForCPU)

        let validatedOrDeselected = FleetChartSelection.validateOrDeselect(
            shaSelection, in: [cpuSeries], tolerance: 60
        )
        #expect(validatedOrDeselected == nil)
    }

    @Test
    func selectionDroppedWhenOldestPointPrunedOnBufferRollover() {
        let deviceID = UUID()
        let initialPoints = (0..<360).map {
            HashratePoint(date: baseDate.addingTimeInterval(Double($0) * 10), value: 1000.0)
        }
        let series = MinerHistorySeries(id: deviceID, name: "Rig", points: initialPoints)

        let selection = FleetChartSelection.resolve(at: baseDate, in: [series], tolerance: 5)
        #expect(selection != nil)
        #expect(FleetChartSelection.isSelectionValid(at: baseDate, in: [series], tolerance: 5))

        let rolledPoints = Array((initialPoints + [
            HashratePoint(date: baseDate.addingTimeInterval(3600), value: 1000.0)
        ]).suffix(360))
        let rolledSeries = MinerHistorySeries(id: deviceID, name: "Rig", points: rolledPoints)

        #expect(!FleetChartSelection.isSelectionValid(at: baseDate, in: [rolledSeries], tolerance: 5))
        #expect(FleetChartSelection.validateOrDeselect(selection, in: [rolledSeries], tolerance: 5) == nil)
    }

    @Test
    func selectionOutsideToleranceReturnsNil() {
        let series = MinerHistorySeries(name: "Solo", points: [HashratePoint(date: baseDate, value: 1000.0)])
        #expect(FleetChartSelection.resolve(at: baseDate.addingTimeInterval(7200), in: [series], tolerance: 1800) == nil)
    }
}
