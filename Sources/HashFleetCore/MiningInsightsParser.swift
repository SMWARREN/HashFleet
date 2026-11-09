import Foundation

enum MiningInsightsParser {
    static func fees(_ data: Data) throws -> (BitcoinFeeRecommendations, Date?) {
        let object = try object(data)
        let value = BitcoinFeeRecommendations(
            fastestFee: number(object["fastestFee"]),
            halfHourFee: number(object["halfHourFee"]),
            hourFee: number(object["hourFee"]),
            economyFee: number(object["economyFee"]),
            minimumFee: number(object["minimumFee"])
        )
        guard
            [value.fastestFee, value.halfHourFee, value.hourFee, value.economyFee, value.minimumFee]
                .contains(where: { $0 != nil })
        else { throw MiningInsightsError.invalidData }
        return (value, nil)
    }

    static func backlog(_ data: Data) throws -> (MempoolBacklog, Date?) {
        let object = try object(data)
        let value = MempoolBacklog(
            transactionCount: integer(object["count"]),
            virtualSizeBytes: integer(object["vsize"]),
            totalFeeSatoshis: integer(object["total_fee"]).flatMap(Int64.init(exactly:))
        )
        guard value.transactionCount != nil || value.virtualSizeBytes != nil || value.totalFeeSatoshis != nil else {
            throw MiningInsightsError.invalidData
        }
        return (value, nil)
    }

    static func height(_ data: Data) throws -> (Int, Date?) {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let height = Int(text)
        else {
            throw MiningInsightsError.invalidData
        }
        return (height, nil)
    }

    static func mining(_ data: Data) throws -> (BitcoinMiningStatistics, Date?) {
        let object = try object(data)
        let hashrate = number(object["currentHashrate"], positive: true)
        let difficulty = number(object["currentDifficulty"], positive: true)
        let sampleAt = object["hashrates"]?.arrayValue?.compactMap { sample -> Date? in
            guard number(sample["avgHashrate"], positive: true) != nil else { return nil }
            return date(sample["timestamp"])
        }.max()
        let changedAt = object["difficulty"]?.arrayValue?.compactMap { sample -> Date? in
            // Do not label an unrelated historical difficulty as the current difficulty's source time.
            guard let difficulty, number(sample["difficulty"], positive: true) == difficulty else { return nil }
            return date(sample["time"]) ?? date(sample["timestamp"])
        }.max()
        guard hashrate != nil || difficulty != nil else { throw MiningInsightsError.invalidData }
        return (
            BitcoinMiningStatistics(
                hashrateHPS: hashrate,
                difficulty: difficulty,
                hashrateSampleAt: sampleAt,
                difficultyChangedAt: changedAt
            ), nil
        )
    }

    static func price(_ data: Data) throws -> (BitcoinPrice, Date?) {
        let object = try object(data)
        guard let usd = number(object["USD"], positive: true) else { throw MiningInsightsError.invalidData }
        return (BitcoinPrice(usd: usd), date(object["time"]))
    }

    static func coinMarkets(_ data: Data) throws -> ([MiningPoolCoin: CoinGeckoMarket], Date?) {
            let values: [CoinGeckoResponse]
        do {
            values = try JSONDecoder().decode([CoinGeckoResponse].self, from: data)
        } catch {
            throw MiningInsightsError.invalidData
        }

        var markets: [MiningPoolCoin: CoinGeckoMarket] = [:]
        for value in values {
            guard let coin = MiningPoolCoin.allCases.first(where: { $0.coingeckoID == value.id }),
                !value.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            let imageURL = value.image.flatMap(Self.coinGeckoImageURL)
            markets[coin] = CoinGeckoMarket(
                id: value.id,
                ticker: value.symbol.uppercased(),
                name: value.name,
                imageURL: imageURL,
                currentPriceUSD: value.currentPrice.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
                marketCapRank: value.marketCapRank
            )
        }
        guard !markets.isEmpty else { throw MiningInsightsError.invalidData }
        return (markets, nil)
    }

    static func pool(_ data: Data) throws -> (CKPoolSummary, Date?) {
        let object = try object(data, allowNDJSON: true)
        let value = CKPoolSummary(
            uptimeSeconds: number(object["runtime"]),
            users: integer(object["Users"]),
            workers: integer(object["Workers"]),
            idle: integer(object["Idle"]),
            disconnected: integer(object["Disconnected"]),
            hashrate1MinuteHPS: hashrate(object["hashrate1m"]),
            hashrate5MinutesHPS: hashrate(object["hashrate5m"]),
            hashrate1HourHPS: hashrate(object["hashrate1hr"]),
            hashrate1DayHPS: hashrate(object["hashrate1d"]),
            hashrate7DaysHPS: hashrate(object["hashrate7d"]),
            bestShare: number(object["bestshare"])
        )
        guard
            value.uptimeSeconds != nil || value.users != nil || value.workers != nil || value.idle != nil
                || value.disconnected != nil || value.bestShare != nil
                || [
                    value.hashrate1MinuteHPS, value.hashrate5MinutesHPS, value.hashrate1HourHPS,
                    value.hashrate1DayHPS, value.hashrate7DaysHPS
                ].contains(where: { $0 != nil })
        else {
            throw MiningInsightsError.invalidData
        }
        return (value, date(object["lastupdate"]))
    }

    static func user(_ data: Data) throws -> (CKPoolUserStatistics, Date?) {
        let object = try object(data, allowNDJSON: true)
        let value = CKPoolUserStatistics(
            hashrate1MinuteHPS: hashrate(object["hashrate1m"]),
            hashrate5MinutesHPS: hashrate(object["hashrate5m"]),
            hashrate1HourHPS: hashrate(object["hashrate1hr"]),
            hashrate1DayHPS: hashrate(object["hashrate1d"]),
            hashrate7DaysHPS: hashrate(object["hashrate7d"]),
            workers: integer(object["workers"]),
            shares: number(object["shares"]),
            bestShare: number(object["bestshare"]),
            bestEver: number(object["bestever"]),
            lastShareAt: date(object["lastshare"])
        )
        guard
            value.workers != nil || value.shares != nil || value.bestShare != nil || value.bestEver != nil
                || [
                    value.hashrate1MinuteHPS, value.hashrate5MinutesHPS, value.hashrate1HourHPS,
                    value.hashrate1DayHPS, value.hashrate7DaysHPS
                ].contains(where: { $0 != nil })
        else {
            throw MiningInsightsError.invalidData
        }
        // lastshare is an event time, not the time all user statistics were generated.
        return (value, date(object["lastupdate"]))
    }

    private static func coinGeckoImageURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https",
            ["coin-images.coingecko.com", "assets.coingecko.com"].contains(url.host?.lowercased() ?? ""),
            url.user == nil, url.password == nil, url.fragment == nil
        else { return nil }
        return url
    }

    static func object(_ data: Data, allowNDJSON: Bool = false) throws -> [String: JSONValue] {
        let decoder = JSONDecoder()
        if let value = try? decoder.decode(JSONValue.self, from: data), let object = value.objectValue {
            return object
        }
        guard allowNDJSON, let text = String(data: data, encoding: .utf8) else {
            throw MiningInsightsError.invalidData
        }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter {
            !$0.isEmpty
        }
        guard !lines.isEmpty else { throw MiningInsightsError.invalidData }
        var merged: [String: JSONValue] = [:]
        for line in lines {
            guard let value = try? decoder.decode(JSONValue.self, from: Data(line.utf8)),
                let object = value.objectValue
            else { throw MiningInsightsError.invalidData }
            for (key, value) in object {
                // Do not silently invent precedence for conflicting records.
                if let existing = merged[key], existing != value { throw MiningInsightsError.invalidData }
                merged[key] = value
            }
        }
        return merged
    }

    static func number(_ value: JSONValue?, positive: Bool = false) -> Double? {
        guard let number = value?.doubleValue, number.isFinite, positive ? number > 0 : number >= 0 else {
            return nil
        }
        return number
    }

    static func integer(_ value: JSONValue?) -> Int? {
        if case .integer(let value) = value { return value >= 0 ? Int(exactly: value) : nil }
        if case .unsignedInteger(let value) = value { return Int(exactly: value) }
        guard let number = number(value) else { return nil }
        return Int(exactly: number)
    }

    static func date(_ value: JSONValue?) -> Date? {
        guard let timestamp = number(value, positive: true), timestamp <= Date.distantFuture.timeIntervalSince1970
        else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// CKPool uses decimal SI suffixes generated by suffix_string, such as 999G, 1.25T, or 196P.
    static func hashrate(_ value: JSONValue?) -> Double? {
        if let raw = number(value) { return raw }
        guard case .string(let text) = value, let suffix = text.last else { return nil }
        let multipliers: [Character: Double] = [
            "k": 1e3, "K": 1e3, "M": 1e6, "G": 1e9,
            "T": 1e12, "P": 1e15, "E": 1e18, "Z": 1e21, "Y": 1e24
        ]
        guard let multiplier = multipliers[suffix], let coefficient = Double(text.dropLast()),
            coefficient.isFinite, coefficient >= 0
        else { return nil }
        let rate = coefficient * multiplier
        return rate.isFinite ? rate : nil
    }
}
