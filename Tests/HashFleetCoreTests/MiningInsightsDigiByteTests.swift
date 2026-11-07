import Foundation
import Testing
@testable import HashFleetCore

// MiningInsightsFixture has one shared protocol handler. Extend its serialized suite rather
// than running a second independently serialized suite that could overwrite the first's handler.
extension MiningInsightsClientTests {
    @Test func usesDedicatedSHA256PoolEndpointAndPreservesSourceFreshness() async throws {
        let fixture = MiningInsightsFixture { request in
            #expect(request.url?.absoluteString == "https://dgb-sha.solopool.org/api/stats")
            #expect(request.httpMethod == "GET")
            #expect(request.url?.query == nil)
            #expect(request.url?.user == nil)
            #expect(request.url?.password == nil)
            #expect(request.httpShouldHandleCookies == false)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
            #expect(try requestBody(request).isEmpty)
            let json = """
                {"node":{"height":24199257,"hashrate":34610744867911410,"difficulty":651917699,"lastUpdate":1789231065},"hashrate":3713978806629700,"totalMiners":301,"totalWorkers":514}
                """
            return try stubResponse(for: request, data: Data(json.utf8))
        }

        let result = await fixture.client.digiByte()
        #expect(result.error == nil)
        #expect(result.sourceURL == MiningInsightsEndpoint.dgbStats.url)
        #expect(MiningInsightsEndpoint.dgbStats.sourceName == "SoloPool.org")
        #expect(result.value?.difficulty == 651917699)
        #expect(result.value?.tipHeight == 24199257)
        // The top-level hashrate is pool hashrate, not the model's network 24-hour average.
        #expect(result.value?.hashrate24HoursHPS == nil)
        #expect(result.value?.usd == nil)
        #expect(result.value?.mempoolTransactions == nil)
        #expect(result.sourceTimestamp == Date(timeIntervalSince1970: 1789231065))
        #expect(result.value?.sourceTimestamp == result.sourceTimestamp)
    }

    @Test func rejectsGenericOrIncompleteDigiBytePayloads() async {
        let fixture = MiningInsightsFixture { request in
            #expect(request.url == MiningInsightsEndpoint.dgbStats.url)
            // A Blockchair-shaped response must not be accepted by the SHA256 pool parser.
            return try stubResponse(
                for: request,
                data: Data(#"{"data":{"difficulty":12345,"best_block_height":24199257}}"#.utf8)
            )
        }

        let result = await fixture.client.digiByte()
        #expect(result.value == nil)
        #expect(result.error == .invalidData)
    }

    @Test(arguments: [
        #"{"node":{"height":1,"hashrate":0,"difficulty":2,"lastUpdate":1789231065}}"#,
        #"{"node":{"height":1,"hashrate":2,"difficulty":0,"lastUpdate":1789231065}}"#,
        #"{"node":{"height":1,"hashrate":2,"difficulty":2,"lastUpdate":0}}"#
    ])
    func rejectsNonPositiveNetworkFields(payload: String) async {
        let fixture = MiningInsightsFixture { request in
            try stubResponse(for: request, data: Data(payload.utf8))
        }

        let result = await fixture.client.digiByte()
        #expect(result.value == nil)
        #expect(result.error == .invalidData)
    }

    @Test func endpointAllowlistRejectsTheRetiredBlockchairDGBURL() {
        #expect(throws: MiningInsightsError.self) {
            try MiningInsightsClient().request(
                for: .dgbStats,
                url: URL(string: "https://api.blockchair.com/digibyte/stats")
            )
        }
        #expect(MiningInsightsEndpoint.dgbStats.url.absoluteString == "https://dgb-sha.solopool.org/api/stats")
    }
}
