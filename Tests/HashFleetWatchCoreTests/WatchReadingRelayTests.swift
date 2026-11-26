import Foundation
import Testing
@testable import HashFleetWatchCore

@Suite struct WatchReadingRelayTests {
    @Test func relayTypesRoundTrip() throws {
        let minerID = UUID()
        let request = WatchMinerRelayRequest(minerID: minerID, host: "192.168.86.207", port: 4028)
        let decodedReq = try JSONDecoder().decode(WatchMinerRelayRequest.self, from: JSONEncoder().encode(request))
        #expect(decodedReq == request)

        let reading = WatchMinerReading(
            minerID: minerID,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            hashrateGHs: 3_950,
            powerWatts: 138,
            chipTemperatureC: 62,
            uptimeSeconds: 3_600,
            acceptedShares: 42,
            rejectedShares: 1
        )
        let response = WatchMinerRelayResponse(reading: reading)
        let decodedResp = try JSONDecoder().decode(WatchMinerRelayResponse.self, from: JSONEncoder().encode(response))
        #expect(decodedResp == response)

        let transfer = WatchCachedReadingsTransfer(
            readings: [reading],
            sentAt: Date(timeIntervalSince1970: 1_700_000_005)
        )
        let decodedTransfer = try JSONDecoder().decode(
            WatchCachedReadingsTransfer.self,
            from: JSONEncoder().encode(transfer)
        )
        #expect(decodedTransfer == transfer)
        #expect(decodedTransfer.version == WatchCachedReadingsTransfer.currentVersion)
    }

    @Test @MainActor func applyRelayedReadingsUpdatesKnownMinersAndPreservesNewer() throws {
        let store = WatchFleetStore(storageURL: nil)
        try store.addMiner(name: "Avalon Nano 3S", address: "192.168.86.207:4028")
        let miner = try #require(store.miners.first)

        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_060)
        let unknownID = UUID()

        store.applyRelayedReadings([
            WatchMinerReading(minerID: miner.id, observedAt: t2, hashrateGHs: 4_000, powerWatts: 140),
            WatchMinerReading(minerID: unknownID, observedAt: t2, hashrateGHs: 999)
        ])
        #expect(store.readings[miner.id]?.hashrateGHs == 4_000)
        #expect(store.readings[unknownID] == nil)

        // Older relayed reading must not overwrite newer reading.
        store.applyRelayedReadings([
            WatchMinerReading(minerID: miner.id, observedAt: t1, hashrateGHs: 1_000)
        ])
        #expect(store.readings[miner.id]?.hashrateGHs == 4_000)
    }
}
