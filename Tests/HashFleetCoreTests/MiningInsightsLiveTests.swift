import Foundation
import Testing
import HashFleetCore

/// Never runs in ordinary tests. These public GETs contain no address, credentials, or miner configuration.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HASHFLEET_PUBLIC_DATA_SMOKE"] == "1"), .timeLimit(.minutes(1)))
struct MiningInsightsLiveTests {
    @Test func bitcoinCashAggregateDecodesThroughProductionClient() async throws {
        let result = await MiningInsightsClient().bitcoinCash()
        #expect(result.error == nil)
        let stats = try #require(result.value)
        #expect(stats.difficulty != nil)
        #expect(stats.tipHeight != nil)
        #expect(stats.usd != nil)
        #expect(stats.sourceTimestamp != nil)
        print("PUBLIC_DATA_SMOKE BCH fetchedAt=\(result.fetchedAt.ISO8601Format()) " +
              "tip=\(String(describing: stats.tipHeight)) difficulty=\(String(describing: stats.difficulty)) " +
              "usd=\(String(describing: stats.usd)) sourceTimestamp=\(String(describing: stats.sourceTimestamp))")
    }

    @Test func verifiedPublicAggregatesDecodeThroughProductionClient() async throws {
        let client = MiningInsightsClient()
        async let networkRequest = client.bitcoinNetwork()
        async let poolRequest = client.ckPoolSummary()
        let (network, pool) = await (networkRequest, poolRequest)
        #expect(network.fees.error == nil)
        #expect(network.backlog.error == nil)
        #expect(network.tipHeight.error == nil)
        #expect(network.mining.error == nil)
        #expect(network.price.error == nil)
        #expect(pool.error == nil)
        let fees = try #require(network.fees.value)
        let backlog = try #require(network.backlog.value)
        let height = try #require(network.tipHeight.value)
        let mining = try #require(network.mining.value)
        let price = try #require(network.price.value)
        let summary = try #require(pool.value)
        #expect(fees.fastestFee != nil)
        #expect(backlog.transactionCount != nil)
        #expect(mining.difficulty != nil)
        #expect(mining.hashrateHPS != nil)
        #expect(price.usd != nil)
        #expect(summary.users != nil)
        #expect(summary.hashrate1MinuteHPS != nil)
        print("PUBLIC_DATA_SMOKE fetchedAt=\(network.fetchedAt.ISO8601Format()) height=\(height) " +
              "fastestFee=\(String(describing: fees.fastestFee)) " +
              "count=\(String(describing: backlog.transactionCount)) " +
              "difficulty=\(String(describing: mining.difficulty)) " +
              "hashrateHPS=\(String(describing: mining.hashrateHPS)) usd=\(String(describing: price.usd))")
        print("PUBLIC_DATA_SMOKE CKPool users=\(String(describing: summary.users)) " +
              "workers=\(String(describing: summary.workers)) " +
              "hashrate1mHPS=\(String(describing: summary.hashrate1MinuteHPS)) " +
              "sourceTimestamp=\(String(describing: pool.sourceTimestamp))")
    }

    @Test func coinMarketsDecodeThroughProductionClient() async throws {
        let result = await MiningInsightsClient().coinMarkets()
        #expect(result.error == nil)
        let markets = try #require(result.value)
        for coin in MiningPoolCoin.allCases {
            let market = try #require(markets[coin])
            #expect(market.ticker.isEmpty == false)
            #expect(market.imageURL?.scheme == "https")
            #expect(["coin-images.coingecko.com", "assets.coingecko.com"].contains(market.imageURL?.host ?? ""))
        }
        print("PUBLIC_DATA_SMOKE CoinGecko coins=\(markets.keys.map(\.rawValue).sorted()) " +
              "source=\(result.sourceURL.absoluteString)")
    }
}
