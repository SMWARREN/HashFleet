import Foundation
import Testing
@testable import HashFleetWatchCore

struct WatchThorOSReadingTests {
    @Test func decodesWrappedThorMinerStatus() throws {
        let json = """
        {"ok": true, "data": {"current_hashrate": 10000000000000, "power_consumption": 157, \
        "temp_board": 60, "temp_board_1": 63, "temp_vcore": 50, "shares_accepted": 9}}
        """
        let reading = try WatchMinerInfoDecoder.reading(from: Data(json.utf8), minerID: UUID(), observedAt: Date())
        #expect(reading.hashrateGHs == 10_000)
        #expect(reading.powerWatts == 157)
        #expect(reading.chipTemperatureC == 63)
        #expect(reading.acceptedShares == 9)
        #expect(WatchMinerHTTPClient.fallbackPaths.contains("/v2/miner/status"))
    }

    @Test func discoveryNamesThorMiner() {
        let body = Data(#"{"current_hashrate": 3.2e12, "power_consumption": 46}"#.utf8)
        #expect(WatchDiscoveryIdentification.minerName(from: body, path: "/v2/miner/status") == "Hammer ThorOS Miner")
    }
}
