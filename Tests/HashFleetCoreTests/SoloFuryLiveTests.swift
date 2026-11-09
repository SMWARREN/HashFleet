import Foundation
import Testing
@testable import HashFleetCore

/// Opt-in aggregate-only smoke test. Never calls /client, /user or a miner endpoint.
@Suite("SoloFury aggregate live smoke",
       .enabled(if: ProcessInfo.processInfo.environment["HASHFLEET_SOLOFURY_SMOKE"] == "1"))
struct SoloFuryLiveTests {
    @Test func publicBCHAggregateDecodesThroughProductionTransport() async throws {
        let result = await SoloFuryClient().summary(coin: .bch)
        #expect(result.error == nil)
        let value = try #require(result.value)
        #expect(result.sourceURL.absoluteString == "https://solofury.com/api/pool")
        #expect(value.totalHashRateHPS.map { $0.isFinite && $0 >= 0 } == true)
        #expect(value.totalWorkers.map { $0 >= 0 } == true)
        #expect(value.blockEvents != nil)
        #expect(value.blocksFound == nil)
        #expect(result.sourceTimestamp == nil)
        // Aggregate metadata only. Do not print public user/worker identifiers from the upstream body.
        print("SoloFury aggregate GET success: fetchedAt=\(result.fetchedAt.ISO8601Format()), " +
              "HPS=\(value.totalHashRateHPS ?? -1), workers=\(value.totalWorkers ?? -1), " +
              "reportedBlockEvents=\(value.reportedBlockEventCount ?? -1), sourceTimestamp=unreported")
    }
}
