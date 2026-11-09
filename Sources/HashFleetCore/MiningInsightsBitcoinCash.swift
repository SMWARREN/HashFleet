import Foundation

/// Independent Bitcoin Cash main-chain assumptions, not BTC values or inferred miner chain identity.
public struct BitcoinCashStatistics: Hashable, Sendable {
    public let difficulty: Double?
    public let tipHeight: Int?
    public let usd: Double?
    public let hashrate24HoursHPS: Double?
    public let mempoolTransactions: Int?
    public let sourceTimestamp: Date?

    public init(
        difficulty: Double? = nil,
        tipHeight: Int? = nil,
        usd: Double? = nil,
        hashrate24HoursHPS: Double? = nil,
        mempoolTransactions: Int? = nil,
        sourceTimestamp: Date? = nil
    ) {
        self.difficulty = difficulty
        self.tipHeight = tipHeight
        self.usd = usd
        self.hashrate24HoursHPS = hashrate24HoursHPS
        self.mempoolTransactions = mempoolTransactions
        self.sourceTimestamp = sourceTimestamp
    }
}

enum MiningInsightsBitcoinCashParser {
    static func statistics(_ data: Data) throws -> (BitcoinCashStatistics, Date?) {
        let root = try MiningInsightsParser.object(data)
        guard let code = MiningInsightsParser.integer(root["context"]?["code"]),
            (100...599).contains(code)
        else { throw MiningInsightsError.invalidData }
        guard code == 200 else { throw MiningInsightsError.http(statusCode: code) }
        guard let data = root["data"]?.objectValue else { throw MiningInsightsError.invalidData }
        let timestamp = utcTimestamp(root["context"]?["cache"]?["since"])
        let result = BitcoinCashStatistics(
            difficulty: MiningInsightsParser.number(data["difficulty"], positive: true),
            // blocks includes other indexed blocks and is NOT the best block height.
            tipHeight: MiningInsightsParser.integer(data["best_block_height"]),
            usd: MiningInsightsParser.number(data["market_price_usd"], positive: true),
            hashrate24HoursHPS: MiningInsightsParser.number(data["hashrate_24h"], positive: true),
            mempoolTransactions: MiningInsightsParser.integer(data["mempool_transactions"]),
            sourceTimestamp: timestamp
        )
        guard
            result.difficulty != nil || result.tipHeight != nil || result.usd != nil
                || result.hashrate24HoursHPS != nil || result.mempoolTransactions != nil
        else {
            throw MiningInsightsError.invalidData
        }
        return (result, timestamp)
    }

    private static func utcTimestamp(_ value: JSONValue?) -> Date? {
        guard case .string(let text) = value, text.count == 19 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        guard let date = formatter.date(from: text), formatter.string(from: date) == text,
            date.timeIntervalSince1970 > 0
        else { return nil }
        return date
    }
}
