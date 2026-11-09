import Foundation
import Testing
@testable import HashFleetCore

// MARK: - Live realistic fixture (matching the verified shape, wallet/worker identifiers scrubbed)

private let realisticSoloPoolFixture = """
{
    "hashrate": 108687993308120,
    "averageHashrate": 98842320157066,
    "onlineWorkers": 1,
    "offlineWorkers": 0,
    "deadWorkers": 0,
    "totalWorkers": 1,
    "lastShare": 1789048798,
    "roundShares": 404700000,
    "bestShare": 412159349,
    "totalBlocks": 57,
    "lastBlockTime": 1789030036,
    "workers": {
        "0": {
            "hr": 108687993308120,
            "avgHr": 98842320157066,
            "lastShare": 1789048798,
            "validShares": 1979,
            "invalidShares": 0,
            "staleShares": 0,
            "offline": false,
            "dead": false,
            "port": 250000,
            "geo": "US"
        }
    },
    "blocks": [
        {
            "height": 24185838,
            "hash": "00000000000000036b8758c7c435f87e80676e6862fe75796cadf2fa4d203248",
            "tx": "523cde81b24784c313d4822b83e3d946c7b609b2e7d91c8d7bfd05d3793d5dce",
            "timestamp": 1789030036,
            "networkDifficulty": 963901078,
            "shareDiff": 1255806751,
            "poolShares": 624862500,
            "minerShares": 869725000,
            "blockReward": 25355810338,
            "minerReward": 24848694131,
            "feeReward": 507116207,
            "miner": "DRGenRKV9FUg15qkXyLAgXL4aP93RHrdh9",
            "worker": "0",
            "geo": "US",
            "state": 1
        },
        {
            "height": 24157494,
            "hash": "0000000000000006477a0d1cf6ed69c84abb3b813d9ec86cec4884b3d86e766f",
            "tx": "0000000000000000000000000000000000000000000000000000000000000000",
            "timestamp": 1788605078,
            "networkDifficulty": 501747263,
            "shareDiff": 683988022,
            "poolShares": 589237500,
            "minerShares": 129437500,
            "blockReward": 25355847838,
            "minerReward": 24848730881,
            "feeReward": 507116957,
            "miner": "DRGenRKV9FUg15qkXyLAgXL4aP93RHrdh9",
            "worker": "0",
            "geo": "US",
            "state": -1
        }
    ],
    "blocksSummary": [
        {"period": 3600, "blocks": 0, "total": 0, "luck": 0},
        {"period": 86400, "blocks": 2, "total": 49697388262, "luck": 0.9},
        {"period": 604800, "blocks": 22, "total": 472141631635, "luck": 0.86},
        {"period": 2592000, "blocks": 31, "total": 671877137583, "luck": 1.04},
        {"period": 5184000, "blocks": 31, "total": 671877137583, "luck": 1.04}
    ],
    "charts": [
        {"x": 1789048800, "y": 108687993308120},
        {"x": 1789048200, "y": 106837013060589}
    ]
}
"""

@Suite("SoloPoolClient parsing tests", .timeLimit(.minutes(1)))
struct SoloPoolClientParsingTests {
    @Test func fullDecodeOfRealisticFixtureMatchesVerifiedShape() throws {
        let (account, sourceTs) = try SoloPoolClient.parseAccountStats(Data(realisticSoloPoolFixture.utf8))
        #expect(account.hashRateHPS == 108687993308120)
        #expect(account.averageHashRateHPS == 98842320157066)
        #expect(account.onlineWorkers == 1)
        #expect(account.offlineWorkers == 0)
        #expect(account.deadWorkers == 0)
        #expect(account.totalWorkers == 1)
        #expect(account.lastShare == Date(timeIntervalSince1970: 1789048798))
        #expect(account.roundShares == 404700000)
        #expect(account.bestShare == 412159349)
        #expect(account.totalBlocks == 57)
        #expect(account.lastBlockTime == Date(timeIntervalSince1970: 1789030036))

        #expect(account.workersReported)
        #expect(account.workers.count == 1)
        let worker = try #require(account.workers.first)
        #expect(worker.name == "0")
        #expect(worker.hashRateHPS == 108687993308120)
        #expect(worker.averageHashRateHPS == 98842320157066)
        #expect(worker.lastShare == Date(timeIntervalSince1970: 1789048798))
        #expect(worker.validShares == 1979)
        #expect(worker.invalidShares == 0)
        #expect(worker.staleShares == 0)
        #expect(worker.offline == false)
        #expect(worker.dead == false)
        #expect(worker.port == 250000)
        #expect(worker.geo == "US")

        let blocks = try #require(account.blocks)
        #expect(blocks.count == 2)
        #expect(blocks[0].height == 24185838)
        #expect(blocks[0].state == 1)
        #expect(blocks[0].blockReward == 25355810338)
        #expect(blocks[0].minerReward == 24848694131)
        #expect(blocks[0].feeReward == 507116207)
        #expect(blocks[0].timestamp == Date(timeIntervalSince1970: 1789030036))
        #expect(blocks[1].state == -1) // orphan, verified as a real distinct value from live data

        let summary = try #require(account.blocksSummary)
        #expect(summary.count == 5)
        #expect(summary[0].period == 3600)
        #expect(summary[0].blocks == 0)
        #expect(summary[0].total == 0)
        #expect(summary[0].luck == 0)
        #expect(summary[2].period == 604800)
        #expect(summary[2].luck == 0.86)

        let charts = try #require(account.charts)
        #expect(charts.count == 2)
        #expect(charts[0].timestamp == Date(timeIntervalSince1970: 1789048800))
        #expect(charts[0].hashRateHPS == 108687993308120)

        // Per coordinator pattern established in SoloFuryClient: lastShare/lastBlockTime are
        // account activity fields, not the response's own generation timestamp.
        #expect(sourceTs == nil)
    }

    @Test func blocksSummaryIsOptionalWhenAccountHasNoBlocks() throws {
        let (account, _) = try SoloPoolClient.parseAccountStats(Data(#"{"hashrate":0,"totalBlocks":0}"#.utf8))
        #expect(account.blocksSummary == nil)
        #expect(account.blocks == nil)
        #expect(account.totalBlocks == 0)
        #expect(account.hashRateHPS == 0)
    }

    @Test func absentMalformedAndReportedEmptyWorkersStayDistinct() throws {
        let (absent, _) = try SoloPoolClient.parseAccountStats(Data(#"{"hashrate":0}"#.utf8))
        #expect(absent.workersReported == false)
        #expect(absent.workers.isEmpty)

        let (empty, _) = try SoloPoolClient.parseAccountStats(Data(#"{"workers":{}}"#.utf8))
        #expect(empty.workersReported)
        #expect(empty.workers.isEmpty)

        // A malformed individual worker entry is dropped, not fabricated, but the dict itself
        // was still reported.
        let (partial, _) = try SoloPoolClient.parseAccountStats(Data(#"{"workers":{"0":123,"1":{"hr":42}}}"#.utf8))
        #expect(partial.workersReported)
        #expect(partial.workers.count == 1)
        #expect(partial.workers.first?.name == "1")
        #expect(partial.workers.first?.hashRateHPS == 42)
    }

    @Test func zeroCountersAreValidWithoutFillingMissingValues() throws {
        let zeroJSON = #"{"onlineWorkers":0,"offlineWorkers":0,"deadWorkers":0,"totalWorkers":0,"#
            + #""roundShares":0,"bestShare":0}"#
        let (account, _) = try SoloPoolClient.parseAccountStats(Data(zeroJSON.utf8))
        #expect(account.onlineWorkers == 0)
        #expect(account.offlineWorkers == 0)
        #expect(account.deadWorkers == 0)
        #expect(account.totalWorkers == 0)
        #expect(account.roundShares == 0)
        #expect(account.bestShare == 0)
        #expect(account.hashRateHPS == nil)
        #expect(account.averageHashRateHPS == nil)
    }

    @Test func invalidOnlyFieldsNeverTurnIntoSuccessfulEmptyStatistics() {
        for json in [
            #"{"hashrate":null}"#, #"{"totalWorkers":1.5}"#, #"{"hashrate":"NaN"}"#,
            #"{"totalWorkers":true}"#, #"{"hashrate":-1}"#, #"{"workers":[]}"#,
            #"{"blocks":{}}"#, #"{"blocksSummary":{}}"#, #"{"charts":{}}"#
        ] {
            #expect(throws: MiningInsightsError.self) { try SoloPoolClient.parseAccountStats(Data(json.utf8)) }
        }
    }

    @Test func rejectsEmptyObjectOrMalformedJSON() {
        #expect(throws: MiningInsightsError.self) {
            try SoloPoolClient.parseAccountStats(Data("{}".utf8))
        }
        #expect(throws: MiningInsightsError.self) {
            try SoloPoolClient.parseAccountStats(Data("not json".utf8))
        }
        #expect(throws: MiningInsightsError.self) {
            try SoloPoolClient.parseAccountStats(Data("[]".utf8))
        }
    }

    @Test func overflowAndNonIntegerUnsignedFieldsAreRejectedNotTruncated() throws {
        // A value beyond UInt64 range or a fractional value must stay nil, never silently truncated.
        // totalWorkers is a companion always-valid field so the overall-object validity guard
        // does not itself throw; this isolates the per-field overflow/fractional rejection.
        let (huge, _) = try SoloPoolClient.parseAccountStats(Data(
            #"{"hashrate":18446744073709551616,"bestShare":123.5,"totalWorkers":1}"#.utf8))
        #expect(huge.hashRateHPS == nil)
        #expect(huge.bestShare == nil)
        #expect(huge.totalWorkers == 1)
    }

    @Test func blockStateOnlyAcceptsDocumentedValues() throws {
        let blocksJSON = #"{"blocks":[{"height":1,"state":1},{"height":2,"state":-1},"#
            + #"{"height":3,"state":0},{"height":4,"state":2}]}"#
        let (account, _) = try SoloPoolClient.parseAccountStats(Data(blocksJSON.utf8))
        let blocks = try #require(account.blocks)
        #expect(blocks.count == 4)
        #expect(blocks[0].state == 1)
        #expect(blocks[1].state == -1)
        #expect(blocks[2].state == 0)
        #expect(blocks[3].state == nil) // undocumented value 2 rejected, not fabricated
    }
}
