import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

struct ChainObservationTests {
    @Test func coinVisibilityIsUniqueActiveFirstAndExplicitlyOverridable() {
        #expect(FleetCoinVisibility.displayed(active: [.btc, .btc, .bch], configured: [.dgb, .xec], custom: nil) == [.btc, .bch])
        #expect(FleetCoinVisibility.displayed(active: [], configured: [.dgb, .btc, .dgb], custom: nil) == [.btc, .dgb])
        #expect(FleetCoinVisibility.displayed(active: [], configured: [], custom: nil).isEmpty)
        #expect(FleetCoinVisibility.displayed(active: [.btc], configured: [.bch], custom: [.xec, .dgb]) == [.xec, .dgb])
        #expect(FleetCoinVisibility.displayed(active: [.btc], configured: [.bch], custom: []).isEmpty)
        #expect(FleetCoinVisibility.displayed(active: [.bch], configured: [.btc], custom: nil) == [.bch])
    }

    @Test func configuredFallbackUsesOnlyCurrentDevicesAndRecognizedCoins() {
        let now = Date()
        let a = MinerDevice(name: "A", address: "10.0.0.1")
        let b = MinerDevice(name: "B", address: "10.0.0.2")
        var cached = MinerSnapshot(info: MinerInfo(raw: ["stratumURL": .string("us1.solopool.org"),
            "stratumPort": .integer(8004)]), updatedAt: now)
        cached.isCached = true
        let snapshots = [a.id: cached, b.id: snapshot(now: now)]
        #expect(FleetCoinVisibility.configured(devices: [a], snapshots: snapshots) == [.dgb])
        #expect(FleetCoinVisibility.configured(devices: [], snapshots: snapshots).isEmpty)
        #expect(FleetCoinVisibility.configured(devices: [a], snapshots: [a.id: snapshot(host: "unknown.invalid", now: now)]).isEmpty)
    }

    @Test func freshFleetFallbackRequiresCompleteCurrentReadingsAndFiniteSum() {
        let now = Date()
        let a = MinerDevice(name: "A", address: "10.0.0.1")
        let b = MinerDevice(name: "B", address: "10.0.0.2")
        let fresh = snapshot(now: now)
        func rate(_ devices: [MinerDevice], _ snapshots: [UUID: MinerSnapshot], demo: Bool = false) -> Double? {
            ChainObservation.freshFleetRateHPS(devices: devices, snapshots: snapshots, now: now, isDemo: demo)
        }
        #expect(rate([], [:]) == nil)
        #expect(rate([a], [:]) == nil)
        #expect(rate([a, b], [a.id: fresh]) == nil)
        #expect(rate([a, b], [a.id: fresh, b.id: fresh]) == 2e12)
        #expect(rate([a], [a.id: snapshot(rate: .integer(0), now: now)]) == 0)
        for offset in [-FleetGlance.freshnessInterval * 3, 60] {
            #expect(rate([a], [a.id: snapshot(now: now.addingTimeInterval(offset))]) == 1e12)
        }
        var cached = fresh
        cached.isCached = true
        var failed = fresh
        failed.error = "offline"
        var noInfo = fresh
        noInfo.info = nil
        var noDate = fresh
        noDate.updatedAt = nil
        for invalid in [cached, failed, noInfo, noDate,
            snapshot(now: now.addingTimeInterval(-FleetGlance.freshnessInterval * 3 - 1)),
            snapshot(now: now.addingTimeInterval(61)), snapshot(rate: nil, now: now),
            snapshot(rate: .integer(-1), now: now), snapshot(rate: .number(.infinity), now: now),
            snapshot(rate: .number(.greatestFiniteMagnitude), now: now)] {
            #expect(rate([a, b], [a.id: fresh, b.id: invalid]) == nil)
        }
        let huge = snapshot(rate: .number(1e299), now: now)
        #expect(rate([a], [a.id: huge]) != nil)
        #expect(rate([a, b], [a.id: huge, b.id: huge]) == nil)
        #expect(rate([a], [a.id: snapshot(now: .distantPast)], demo: true) == 1e12)
        #expect(rate([a], [a.id: cached], demo: true) == nil)
    }

    @Test func distinguishesSourceOutageStalenessAndMissingDifficulty() {
        let now = Date()
        let source = URL(string: "https://example.invalid/stats")!
        let missing: MiningDataResult<Int>? = nil
        #expect(ChainObservation.networkProblem(missing, difficulty: nil, now: now) == "Loading network data")
        let failed = MiningDataResult<Int>(error: .http(statusCode: 404), fetchedAt: now, sourceURL: source)
        #expect(ChainObservation.networkProblem(failed, difficulty: nil, now: now) == "Network source unavailable (HTTP 404)")
        let stale = MiningDataResult(value: 1, fetchedAt: now, sourceURL: source, sourceTimestamp: now.addingTimeInterval(-301))
        #expect(ChainObservation.networkProblem(stale, difficulty: 100, now: now) == "Network data is stale")
        let fresh = MiningDataResult(value: 1, fetchedAt: now, sourceURL: source)
        #expect(ChainObservation.networkProblem(fresh, difficulty: nil, now: now) == "Network difficulty not reported")
        #expect(ChainObservation.networkProblem(fresh, difficulty: .infinity, now: now) == "Network difficulty not reported")
        #expect(ChainObservation.networkProblem(fresh, difficulty: 100, now: now) == nil)
    }

    private func snapshot(
        host: String = "solo.ckpool.org",
        rate: JSONValue? = .integer(1000),
        active: JSONValue? = .bool(false),
        now: Date
    ) -> MinerSnapshot {
        var raw: [String: JSONValue] = ["stratumURL": .string(host)]
        raw["hashRate"] = rate
        raw["isUsingFallbackStratum"] = active
        return MinerSnapshot(info: MinerInfo(raw: raw), updatedAt: now)
    }

    @Test func activeGroupsUseOnlyTheirOwnMinersAndPreserveZero() {
        let now = Date()
        let devices = (0..<3).map { MinerDevice(name: "Test \($0)", address: "http://10.0.0.\($0 + 1)") }
        let snapshots = [
            devices[0].id: snapshot(now: now),
            devices[1].id: snapshot(rate: .integer(0), now: now),
            devices[2].id: snapshot(host: "bch.solofury.com", rate: .integer(500), now: now)
        ]
        let groups = ActiveMiningCoins.groups(devices: devices, snapshots: snapshots, now: now, isDemo: false)
        #expect(groups.map(\.coin) == [.btc, .bch])
        #expect(groups[0].miners == 2 && groups[0].rateHPS == 1e12)
        #expect(groups[1].rateHPS == 5e11)
        #expect(ChainObservation.chance(hashrateHPS: 0, difficulty: 1, fresh: true) == "0.00%")
    }

    @Test func incompleteGroupNeverSilentlyUsesPartialHashrate() {
        let now = Date()
        let devices = [MinerDevice(name: "A", address: "10.0.0.1"), MinerDevice(name: "B", address: "10.0.0.2")]
        let groups = ActiveMiningCoins.groups(
            devices: devices,
            snapshots: [devices[0].id: snapshot(now: now), devices[1].id: snapshot(rate: nil, now: now)],
            now: now,
            isDemo: false
        )
        #expect(groups.count == 1)
        #expect(groups[0].miners == 2 && groups[0].rateHPS == nil)
    }

    @Test func staleOfflineUnknownAndMerelyConfiguredCoinsAreExcluded() {
        let now = Date()
        let device = MinerDevice(name: "A", address: "10.0.0.1")
        var offline = snapshot(now: now)
        offline.error = "offline"
        var cached = snapshot(now: now)
        cached.isCached = true
        for candidate in [
            snapshot(now: now.addingTimeInterval(-301)),
            snapshot(now: now.addingTimeInterval(61)), offline, cached,
            snapshot(host: "unknown.invalid", now: now), snapshot(active: nil, now: now)
        ] {
            #expect(
                ActiveMiningCoins.groups(
                    devices: [device],
                    snapshots: [device.id: candidate],
                    now: now,
                    isDemo: false
                ).isEmpty
            )
        }
    }

    @Test @MainActor func demoCoversEveryCoinAndRotationChangesGroups() {
        let devices = DemoFleet.poolIconDevices
        var snapshots = DemoFleet.poolIconSnapshots(for: devices)
        let now = Date()
        var groups = ActiveMiningCoins.groups(devices: devices, snapshots: snapshots, now: now, isDemo: true)
        #expect(groups.map(\.coin) == MiningPoolCoin.allCases)
        #expect(groups.first?.miners == 2)
        for device in devices {
            var item = snapshots[device.id]!
            var raw = item.info!.raw
            raw["activePoolIndex"] = .integer(6)
            item.info = MinerInfo(raw: raw)
            snapshots[device.id] = item
        }
        groups = ActiveMiningCoins.groups(devices: devices, snapshots: snapshots, now: now, isDemo: true)
        #expect(groups.count == 1 && groups[0].coin == .dgb)
        #expect(groups[0].miners == 7)
    }
    @Test func providerCacheAgeCannotBeRefreshedByNewFetch() {
        let now = Date()
        let source = URL(string: "https://api.blockchair.com/bitcoin-cash/stats")!
        #expect(ChainObservation.isFresh(MiningDataResult(value: 10, fetchedAt: now, sourceURL: source), now: now))
        #expect(
            !ChainObservation.isFresh(
                MiningDataResult(
                    value: 10,
                    fetchedAt: now,
                    sourceURL: source,
                    sourceTimestamp: now.addingTimeInterval(-301)
                ),
                now: now
            )
        )
        #expect(
            !ChainObservation.isFresh(
                MiningDataResult(value: 10, fetchedAt: now.addingTimeInterval(-301), sourceURL: source),
                now: now
            )
        )
        #expect(
            !ChainObservation.isFresh(
                MiningDataResult<Int>(error: .http(statusCode: 503), fetchedAt: now, sourceURL: source),
                now: now
            )
        )
    }
    @Test func perChainOddsUseIndependentDifficultyAndRequireFreshness() {
        let btc = ChainObservation.chance(hashrateHPS: 2e12, difficulty: 140e12, fresh: true)
        let bch = ChainObservation.chance(hashrateHPS: 2e12, difficulty: 430e9, fresh: true)
        #expect(btc.contains("%") && bch.contains("%"))
        #expect(btc != bch)
        #expect(ChainObservation.chance(hashrateHPS: 2e12, difficulty: 430e9, fresh: false) == "Needs fresh readings")
        #expect(ChainObservation.chance(hashrateHPS: nil, difficulty: 430e9, fresh: true) == "Needs fresh readings")
        #expect(InsightsFormat.hashrate(.infinity) == "Not reported")
    }

    @Test func soloOddsWindowsUseDistinctDurations() {
        #expect(SoloOddsWindow.day.duration == 24 * 60 * 60)
        #expect(SoloOddsWindow.month.duration == 30 * 24 * 60 * 60)
        #expect(SoloOddsWindow.year.duration == 365 * 24 * 60 * 60)

        let day = ChainObservation.chance(
            hashrateHPS: 2e12,
            difficulty: 140e12,
            fresh: true,
            duration: SoloOddsWindow.day.duration
        )
        let month = ChainObservation.chance(
            hashrateHPS: 2e12,
            difficulty: 140e12,
            fresh: true,
            duration: SoloOddsWindow.month.duration
        )
        let year = ChainObservation.chance(
            hashrateHPS: 2e12,
            difficulty: 140e12,
            fresh: true,
            duration: SoloOddsWindow.year.duration
        )
        #expect(day != month)
        #expect(month != year)
    }
    @Test func nextCandidateHeightHandlesHalvingAndOverflow() {
        #expect(ChainObservation.nextHeight(839999) == 840000)
        #expect(SoloMiningMath.blockSubsidyBTC(atHeight: ChainObservation.nextHeight(839999)!) == 3.125)
        #expect(ChainObservation.nextHeight(Int.max) == nil)
        #expect(ChainObservation.nextHeight(-1) == nil)
    }

    @Test func nonHTTPErrorsReportGenericNetworkUnavailable() {
        let now = Date()
        let source = URL(string: "https://example.invalid/stats")!
        let errors: [MiningInsightsError] = [
            .timedOut,
            .cancelled,
            .invalidData,
            .invalidResponse,
            .redirected,
            .network(code: -1009)
        ]
        for error in errors {
            let result = MiningDataResult<Int>(error: error, fetchedAt: now, sourceURL: source)
            #expect(ChainObservation.networkProblem(result, difficulty: 100, now: now) == "Network source unavailable")
        }
    }

    @Test(arguments: [0.0, -1.0, -100.0, Double.nan, -.infinity])
    func nonPositiveOrNonFiniteDifficultyReportsProblem(difficulty: Double) {
        let now = Date()
        let source = URL(string: "https://example.invalid/stats")!
        let fresh = MiningDataResult(value: 42, fetchedAt: now, sourceURL: source)
        #expect(ChainObservation.networkProblem(fresh, difficulty: difficulty, now: now) == "Network difficulty not reported")
    }

    @Test func freshnessDriftAndExpiryBoundaries() {
        let now = Date()
        let source = URL(string: "https://example.invalid/stats")!

        let exactFuture = MiningDataResult(value: 1, fetchedAt: now.addingTimeInterval(60), sourceURL: source)
        #expect(ChainObservation.isFresh(exactFuture, now: now))
        let beyondFuture = MiningDataResult(value: 1, fetchedAt: now.addingTimeInterval(61), sourceURL: source)
        #expect(!ChainObservation.isFresh(beyondFuture, now: now))

        let exactPast = MiningDataResult(value: 1, fetchedAt: now.addingTimeInterval(-300), sourceURL: source)
        #expect(ChainObservation.isFresh(exactPast, now: now))
        let beyondPast = MiningDataResult(value: 1, fetchedAt: now.addingTimeInterval(-301), sourceURL: source)
        #expect(!ChainObservation.isFresh(beyondPast, now: now))

        let errorWithValue = MiningDataResult(value: 1, error: .timedOut, fetchedAt: now, sourceURL: source)
        #expect(!ChainObservation.isFresh(errorWithValue, now: now))

        let nilValue = MiningDataResult<Int>(value: nil, fetchedAt: now, sourceURL: source)
        #expect(!ChainObservation.isFresh(nilValue, now: now))
    }

    @Test(arguments: [
        (0.0, 100.0, "0.00%"),
        (-1.0, 100.0, "Needs fresh readings"),
        (Double.nan, 100.0, "Needs fresh readings"),
        (Double.infinity, 100.0, "Needs fresh readings"),
        (1e12, 0.0, "Needs fresh readings"),
        (1e12, -50.0, "Needs fresh readings"),
        (1e12, Double.nan, "Needs fresh readings"),
        (1e12, Double.infinity, "Needs fresh readings")
    ])
    func soloMiningOddsDeterministicBoundaries(hashrate: Double, difficulty: Double, expected: String) {
        #expect(ChainObservation.chance(hashrateHPS: hashrate, difficulty: difficulty, fresh: true) == expected)
    }

    @Test func nextHeightBoundaryValidation() {
        #expect(ChainObservation.nextHeight(0) == 1)
        #expect(ChainObservation.nextHeight(nil) == nil)
        #expect(ChainObservation.nextHeight(-50) == nil)
        #expect(ChainObservation.nextHeight(Int.max - 1) == Int.max)
        #expect(ChainObservation.nextHeight(Int.max) == nil)
    }
}
