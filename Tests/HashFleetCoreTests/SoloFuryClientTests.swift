import Testing
import Foundation
@testable import HashFleetCore

@Suite("SoloFury client tests")
struct SoloFuryClientTests {
    @Test func upstreamSourceHealthCannotBeRefreshedBySuccessfulHTTP() throws {
        for sources in ["[]", "null", "{}", "[{}]",
            #"[{"ok":true,"stale":true}]"#,
            #"[{"ok":false,"stale":false}]"#,
            #"[{"ok":true,"stale":false},{"ok":false,"stale":false}]"#] {
            let data = Data("{\"networkDifficulty\":123,\"sources\":\(sources)}".utf8)
            #expect(throws: MiningInsightsError.invalidData) { try SoloFuryClient.parsePoolStats(data) }
        }
        let valid = Data(#"{"networkDifficulty":123,"sources":[{"ok":true,"stale":false}]}"#.utf8)
        let (stats, timestamp) = try SoloFuryClient.parsePoolStats(valid)
        #expect(stats.networkDifficulty == 123)
        #expect(timestamp == nil)
    }

    @Test func liveShapeBlockEventsAreNotInventedLifetimeTotalsOrSourceFreshness() throws {
        let json = #"{"totalHashRate":0,"blocksFound":[{"height":967400,"timestamp":1788740800.5,"# +
                   #""status":"confirmed","minerAddress":"private-wallet","worker":"private-worker"}]}"#
        let data = Data(json.utf8)
        let (stats, timestamp) = try SoloFuryClient.parsePoolStats(data)
        #expect(stats.totalHashRateHPS == 0)
        #expect(stats.blocksFound == nil)
        #expect(stats.reportedBlockEventCount == 1)
        #expect(stats.blockEvents?.first?.height == 967400)
        #expect(stats.blockEvents?.first?.timestamp == Date(timeIntervalSince1970: 1788740800.5))
        #expect(stats.blockEvents?.first?.status == "confirmed")
        #expect(timestamp == nil)
        #expect(String(describing: stats).contains("private-wallet") == false)
        #expect(String(describing: stats).contains("private-worker") == false)
        let (empty, _) = try SoloFuryClient.parsePoolStats(Data(#"{"blocksFound":[]}"#.utf8))
        #expect(empty.reportedBlockEventCount == 0)
        #expect(empty.blocksFound == nil)
        #expect(empty.totalHashRateHPS == nil)
    }

    @Test func absentMalformedAndReportedEmptyWorkersStayDistinct() throws {
        let (absent, _) = try SoloFuryClient.parseAccountStats(Data(#"{"hashRate":0}"#.utf8))
        #expect(absent.workersReported == false)
        #expect(absent.workersCount == nil)
        let (empty, _) = try SoloFuryClient.parseAccountStats(Data(#"{"workers":[]}"#.utf8))
        #expect(empty.workersReported)
        #expect(empty.workersCount == nil)
        let partialData = Data(#"{"workers":[{"hashRate":123},{"name":"real","bestEver":0}]}"#.utf8)
        let (partial, _) = try SoloFuryClient.parseAccountStats(partialData)
        #expect(partial.workersReported == false)
        #expect(partial.workers.map(\.name) == ["real"])
        #expect(partial.workers.first?.bestEver == 0)
        #expect(partial.hashRateHPS == nil)
        #expect(partial.bestEver == nil)
        #expect(partial.workersCount == nil)
    }

    @Test func invalidOnlyFieldsNeverTurnIntoSuccessfulEmptyStatistics() {
        for json in [#"{"totalHashRate":null}"#, #"{"totalWorkers":1.5}"#, #"{"networkDifficulty":0}"#,
                     #"{"totalHashRate":"NaN"}"#, #"{"totalWorkers":true}"#, #"{"blocksFound":[{}]}"#,
                     #"{"totalWorkers":9223372036854775808}"#, #"{"totalHashRate":-1}"#] {
            #expect(throws: MiningInsightsError.self) { try SoloFuryClient.parsePoolStats(Data(json.utf8)) }
        }
        for json in [#"{"hashRate":null}"#, #"{"workers":[{}]}"#, #"{"workers":{}}"#,
                     #"{"workersCount":0.5}"#, #"{"bestEver":"Infinity"}"#, #"{"hashRate":true}"#] {
            #expect(throws: MiningInsightsError.self) { try SoloFuryClient.parseAccountStats(Data(json.utf8)) }
        }
    }

    @Test func zeroCountersAndLargeLuckAreValidWithoutFillingMissingValues() throws {
        let poolJson = #"{"totalWorkers":0,"blockHeight":0,"bestDifficulty":0,"networkDifficulty":0,"fee":0}"#
        let (pool, _) = try SoloFuryClient.parsePoolStats(Data(poolJson.utf8))
        #expect(pool.blockHeight == 0)
        #expect(pool.bestDifficulty == 0)
        #expect(pool.fee == 0)
        #expect(pool.networkDifficulty == nil)
        #expect(pool.totalMiners == nil)
        let accJson = #"{"shares":0,"bestEver":0,"luck":1000,"workersCount":0,"efficiency":0}"#
        let (account, _) = try SoloFuryClient.parseAccountStats(Data(accJson.utf8))
        #expect(account.shares == 0)
        #expect(account.bestEver == 0)
        #expect(account.workersCount == 0)
        #expect(account.luck == 1000)
        #expect(account.efficiency == 0)
        #expect(account.hashRateHPS == nil)
    }

    @Test func parsesPublicPoolSummaryJSON() throws {
        let json = """
        {
            "totalHashRate": 1612625843141.85,
            "totalHashRate1m": 0.0,
            "totalHashRate1hr": 1580000000000.0,
            "totalMiners": 42,
            "totalWorkers": 0,
            "blockHeight": 850123,
            "networkDifficulty": 84000000000.0,
            "networkHashRate": 350000000000000000.0,
            "blocksFound": 5,
            "bestDifficulty": 12500000.0,
            "roundShares": 54200,
            "efficiency": 99.4,
            "fee": 1.0
        }
        """
        let data = Data(json.utf8)
        let (stats, _) = try SoloFuryClient.parsePoolStats(data)

        #expect(stats.totalHashRateHPS == 1612625843141.85)
        // Valid zero values are preserved, not converted to nil
        #expect(stats.totalHashRate1mHPS == 0.0)
        #expect(stats.totalWorkers == 0)
        #expect(stats.totalMiners == 42)
        #expect(stats.blockHeight == 850123)
        #expect(stats.blocksFound == 5)
        #expect(stats.bestDifficulty == 12500000.0)
        #expect(stats.efficiency == 99.4)
        #expect(stats.fee == 1.0)
    }

    @Test func parsesClientAccountJSONWithWorkers() throws {
        let json = """
        {
            "hashRate": 450000000000.0,
            "hashRate1m": 0.0,
            "hashRate1hr": 440000000000.0,
            "workersCount": 1,
            "bestDifficulty": 16384.0,
            "bestEver": 65536.0,
            "lastShare": "2026-08-25T21:17:21.213Z",
            "shares": 1200,
            "efficiency": 99.8,
            "luck": 105.4,
            "workers": [
                {
                    "name": "rig-01",
                    "hashRate": 450000000000.0,
                    "hashRate1m": 445000000000.0,
                    "hashRate1hr": 440000000000.0,
                    "bestDifficulty": 16384.0,
                    "bestEver": 65536.0,
                    "currentDiff": 1024.0,
                    "shares": 1200,
                    "lastSeen": "2026-08-25T21:17:21.213Z",
                    "protocol": "SV1",
                    "region": "us"
                }
            ]
        }
        """
        let data = Data(json.utf8)
        let (account, sourceTs) = try SoloFuryClient.parseAccountStats(data)

        #expect(account.hashRateHPS == 450000000000.0)
        #expect(account.hashRate1mHPS == 0.0) // 0 preserved
        #expect(account.workersCount == 1)
        #expect(account.bestEver == 65536.0)
        #expect(account.efficiency == 99.8)
        #expect(account.luck == 105.4)
        #expect(account.workers.count == 1)
        #expect(account.workers[0].name == "rig-01")
        #expect(account.workers[0].protocolType == "SV1")
        #expect(account.workers[0].region == "us")
        // Per coordinator review: sourceTimestamp for account must be nil, lastShare is miner activity
        #expect(sourceTs == nil)
    }

    @Test func coinPrefixesMatchSoloFuryAPISpec() {
        #expect(MiningPoolCoin.bch.soloFuryPrefix == "/api")
        #expect(MiningPoolCoin.btc.soloFuryPrefix == "/api-btc")
        #expect(MiningPoolCoin.bc2.soloFuryPrefix == "/api-bc2")
        #expect(MiningPoolCoin.bch2.soloFuryPrefix == "/api-bch2")
        #expect(MiningPoolCoin.xec.soloFuryPrefix == "/api-xec")
    }

    @Test func rejectsEmptyObjectOrMalformedJSON() {
        // Empty object {} has no recognized fields and must be rejected
        #expect(throws: MiningInsightsError.self) {
            try SoloFuryClient.parsePoolStats(Data("{}".utf8))
        }
        #expect(throws: MiningInsightsError.self) {
            try SoloFuryClient.parseAccountStats(Data("{}".utf8))
        }
        #expect(throws: MiningInsightsError.self) {
            try SoloFuryClient.parsePoolStats(Data("not json".utf8))
        }
        #expect(throws: MiningInsightsError.self) {
            try SoloFuryClient.parseAccountStats(Data("[]".utf8))
        }
    }

    @Test func clientAccountRejectsImpostorHostOrUnverifiedAddress() async {
        let client = SoloFuryClient()

        // Impostor host rejected
        let impostorPool = ConfiguredMiningPool(
            id: "slot-0",
            host: "evil.solofury.com",
            coin: .bch,
            provider: .soloFury,
            role: "Primary",
            isActive: true,
            address: "bitcoincash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rq9sywjpyy",
            redactedAddress: nil
        )
        let impostorResult = await client.account(pool: impostorPool)
        #expect(impostorResult.error == .invalidData)

        // Nil address rejected
        let emptyPool = ConfiguredMiningPool(
            id: "slot-1",
            host: "bch.solofury.com",
            coin: .bch,
            provider: .soloFury,
            role: "Primary",
            isActive: true,
            address: nil,
            redactedAddress: nil
        )
        let emptyResult = await client.account(pool: emptyPool)
        #expect(emptyResult.error == .invalidBitcoinAddress)
    }
}
