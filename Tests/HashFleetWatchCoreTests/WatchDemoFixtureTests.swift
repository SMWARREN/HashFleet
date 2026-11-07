import Foundation
import Testing
@testable import HashFleetWatchCore

@MainActor
@Suite struct WatchDemoFixtureTests {
    private struct ExpectedDemoMiner: Sendable {
        let name: String
        let normalizedAddress: String
        let hashrateGHs: Double
        let powerWatts: Double
        let chipTemperatureC: Double
        let vrTemperatureC: Double
        let uptimeSeconds: Double
        let acceptedShares: Int
        let rejectedShares: Int
        let isMiningPaused: Bool
    }

    private static let expectedFixtures: [ExpectedDemoMiner] = [
        ExpectedDemoMiner(
            name: "Demo Gamma",
            normalizedAddress: "http://192.168.0.101",
            hashrateGHs: 1_020,
            powerWatts: 14.2,
            chipTemperatureC: 58,
            vrTemperatureC: 49,
            uptimeSeconds: 93_600,
            acceptedShares: 1_204,
            rejectedShares: 3,
            isMiningPaused: false
        ),
        ExpectedDemoMiner(
            name: "Demo Duo",
            normalizedAddress: "http://192.168.0.102",
            hashrateGHs: 2_410,
            powerWatts: 36.8,
            chipTemperatureC: 63,
            vrTemperatureC: 52,
            uptimeSeconds: 410_000,
            acceptedShares: 5_882,
            rejectedShares: 11,
            isMiningPaused: false
        ),
        ExpectedDemoMiner(
            name: "Demo Bitaxe",
            normalizedAddress: "http://192.168.0.103",
            hashrateGHs: 505,
            powerWatts: 11.9,
            chipTemperatureC: 61,
            vrTemperatureC: 47,
            uptimeSeconds: 7_320,
            acceptedShares: 212,
            rejectedShares: 0,
            isMiningPaused: false
        )
    ]

    @Test(arguments: [0, 1, 2])
    func demoMinerFixtureMatchesExpectedValues(index: Int) {
        let store = WatchFleetStore.demo()
        let expected = Self.expectedFixtures[index]
        guard index < store.miners.count else {
            Issue.record("Expected miner index \(index) out of bounds")
            return
        }

        let miner = store.miners[index]
        #expect(miner.name == expected.name)
        #expect(miner.address == expected.normalizedAddress)

        let reading = store.readings[miner.id]
        #expect(reading != nil)
        #expect(reading?.minerID == miner.id)
        #expect(reading?.hashrateGHs == expected.hashrateGHs)
        #expect(reading?.powerWatts == expected.powerWatts)
        #expect(reading?.chipTemperatureC == expected.chipTemperatureC)
        #expect(reading?.vrTemperatureC == expected.vrTemperatureC)
        #expect(reading?.uptimeSeconds == expected.uptimeSeconds)
        #expect(reading?.acceptedShares == expected.acceptedShares)
        #expect(reading?.rejectedShares == expected.rejectedShares)
        #expect(reading?.isMiningPaused == expected.isMiningPaused)
    }

    @Test func demoStoreHasExpectedTotalCountAndNoFailures() {
        let store = WatchFleetStore.demo()
        #expect(store.isDemo)
        #expect(store.miners.count == Self.expectedFixtures.count)
        #expect(store.readings.count == Self.expectedFixtures.count)
        #expect(store.failures.isEmpty)
        #expect(store.storageError == nil)
    }

    @Test func demoTimestampsAreCurrentAndConsistent() {
        let before = Date()
        let store = WatchFleetStore.demo()
        let after = Date()

        for miner in store.miners {
            guard let reading = store.readings[miner.id] else {
                Issue.record("Missing reading for miner \(miner.id)")
                continue
            }
            #expect(reading.observedAt >= before)
            #expect(reading.observedAt <= after)
        }
    }
}
