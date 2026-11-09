import Foundation

/// Non-identifying fields from a reported block event. Public wallet/worker identifiers are discarded.
public actor SoloFuryClient {
    public static let productionBaseURL = URL(string: "https://solofury.com")!
    private let transport: SoloMiningHTTPClient

    public init(session: URLSession? = nil) {
        transport = SoloMiningHTTPClient(session: session)
    }

    /// Fetches public pool summary for the requested coin.
    public func summary(coin: MiningPoolCoin) async -> MiningDataResult<SoloFuryPoolStats> {
        guard !Task.isCancelled else {
            return cancelled(Self.productionBaseURL, error: .cancelled)
        }
        guard let prefix = coin.soloFuryPrefix else {
            return cancelled(Self.productionBaseURL, error: .invalidData)
        }
        guard let url = URL(string: "\(prefix)/pool", relativeTo: Self.productionBaseURL)?.absoluteURL else {
            return cancelled(Self.productionBaseURL, error: .invalidResponse)
        }
        return await transport.get(url: url, productionBaseURL: Self.productionBaseURL) { data in
            try Self.parsePoolStats(data)
        }
    }

    /// Fetches account statistics for a configured SoloFury pool entry.
    /// Re-validates provider, coin, host, and address at API boundary.
    public func account(pool: ConfiguredMiningPool) async -> MiningDataResult<SoloFuryAccountStats> {
        guard !Task.isCancelled else {
            return cancelled(Self.productionBaseURL, error: .cancelled)
        }
        guard pool.provider == .soloFury else {
            return cancelled(Self.productionBaseURL, error: .invalidData)
        }
        guard let coin = pool.coin else {
            return cancelled(Self.productionBaseURL, error: .invalidData)
        }
        guard let address = pool.address, !address.isEmpty else {
            return cancelled(Self.productionBaseURL, error: .invalidBitcoinAddress)
        }

        // Public ConfiguredMiningPool initializers are not a trust boundary. Re-check host AND chain here.
        let (hostProvider, hostCoin) = ConfiguredMiningPool.inferProviderAndCoin(host: pool.host)
        guard hostProvider == .soloFury, hostCoin == coin else {
            return cancelled(Self.productionBaseURL, error: .invalidData)
        }

        // Re-validate address matches the coin
        guard let validatedAddress = ConfiguredMiningPool.validateAddress(address, coin: coin) else {
            return cancelled(Self.productionBaseURL, error: .invalidBitcoinAddress)
        }

        // No path traversal characters
        guard !validatedAddress.contains("/"), !validatedAddress.contains("\\"), !validatedAddress.contains("%")
        else {
            return cancelled(Self.productionBaseURL, error: .invalidBitcoinAddress)
        }

        guard let prefix = coin.soloFuryPrefix else {
            return cancelled(Self.productionBaseURL, error: .invalidData)
        }
        guard let directory = URL(string: "\(prefix)/client/", relativeTo: Self.productionBaseURL)?.absoluteURL else {
            return cancelled(Self.productionBaseURL, error: .invalidBitcoinAddress)
        }
        let url = directory.appendingPathComponent(validatedAddress)

        return await transport.get(url: url, productionBaseURL: Self.productionBaseURL) { data in
            try Self.parseAccountStats(data)
        }
    }

    private func cancelled<Value: Sendable>(_ url: URL, error: MiningInsightsError) -> MiningDataResult<Value> {
        SoloMiningHTTPClient.failure(url, error: error)
    }

    // MARK: - Parsing Helpers

    public static func parsePoolStats(_ data: Data) throws -> (SoloFuryPoolStats, Date?) {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
            let obj = json.objectValue
        else {
            throw MiningInsightsError.invalidData
        }

        // A fresh HTTP response is not proof that its upstream node readings are fresh.
        // When source health is supplied, fail closed on degraded or malformed aggregates.
        if let reportedSources = obj["sources"] {
            guard let sources = reportedSources.arrayValue, !sources.isEmpty,
                sources.allSatisfy({ source in
                    guard let fields = source.objectValue else { return false }
                    return fields["ok"] == .bool(true) && fields["stale"] == .bool(false)
                })
            else { throw MiningInsightsError.invalidData }
        }

        let stats = SoloFuryPoolStats(
            totalHashRateHPS: parseNonNegativeDouble(obj["totalHashRate"]),
            totalHashRate1mHPS: parseNonNegativeDouble(obj["totalHashRate1m"]),
            totalHashRate1hrHPS: parseNonNegativeDouble(obj["totalHashRate1hr"]),
            totalHashRate1dHPS: parseNonNegativeDouble(obj["totalHashRate1d"]),
            totalHashRate7dHPS: parseNonNegativeDouble(obj["totalHashRate7d"]),
            totalMiners: parseNonNegativeInt(obj["totalMiners"]),
            totalWorkers: parseNonNegativeInt(obj["totalWorkers"]),
            activeMiners7d: parseNonNegativeInt(obj["activeMiners7d"]),
            activeWorkers7d: parseNonNegativeInt(obj["activeWorkers7d"]),
            blockHeight: parseNonNegativeInt(obj["blockHeight"]),
            networkDifficulty: MiningInsightsParser.number(obj["networkDifficulty"], positive: true),
            networkHashRateHPS: parseNonNegativeDouble(obj["networkHashRate"]),
            blocksFound: parseNonNegativeInt(obj["blocksFound"]),
            bestDifficulty: parseNonNegativeDouble(obj["bestDifficulty"]),
            roundShares: parseNonNegativeInt(obj["roundShares"]),
            efficiency: parsePercentage(obj["efficiency"]),
            fee: parsePercentage(obj["fee"]),
            blockEvents: parseBlockEvents(obj["blocksFound"])
        )
        let validNumbers: [Double?] = [
            stats.totalHashRateHPS, stats.totalHashRate1mHPS, stats.totalHashRate1hrHPS,
            stats.totalHashRate1dHPS, stats.totalHashRate7dHPS, stats.networkDifficulty, stats.networkHashRateHPS,
            stats.bestDifficulty, stats.efficiency, stats.fee
        ]
        let validIntegers: [Int?] = [
            stats.totalMiners, stats.totalWorkers, stats.activeMiners7d, stats.activeWorkers7d,
            stats.blockHeight, stats.blocksFound, stats.roundShares
        ]
        guard
            validNumbers.contains(where: { $0 != nil }) || validIntegers.contains(where: { $0 != nil })
                || stats.blockEvents != nil
        else { throw MiningInsightsError.invalidData }
        return (stats, nil)
    }

    public static func parseAccountStats(_ data: Data) throws -> (SoloFuryAccountStats, Date?) {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
            let obj = json.objectValue
        else {
            throw MiningInsightsError.invalidData
        }

        let workerValues = obj["workers"]?.arrayValue
        let workersList: [SoloFuryWorkerStats] = workerValues?.compactMap(parseWorker) ?? []

        let lastShareDate = parseISO8601(text(obj["lastShare"]))

        let account = SoloFuryAccountStats(
            hashRateHPS: parseNonNegativeDouble(obj["hashRate"]),
            hashRate1mHPS: parseNonNegativeDouble(obj["hashRate1m"]),
            hashRate5mHPS: parseNonNegativeDouble(obj["hashRate5m"]),
            hashRate1hrHPS: parseNonNegativeDouble(obj["hashRate1hr"]),
            hashRate1dHPS: parseNonNegativeDouble(obj["hashRate1d"]),
            hashRate7dHPS: parseNonNegativeDouble(obj["hashRate7d"]),
            workersCount: parseNonNegativeInt(obj["workersCount"]),
            bestDifficulty: parseNonNegativeDouble(obj["bestDifficulty"]),
            bestShare: parseNonNegativeDouble(obj["bestShare"]),
            bestEver: parseNonNegativeDouble(obj["bestEver"]),
            lastShare: lastShareDate,
            shares: parseNonNegativeInt(obj["shares"]),
            efficiency: parsePercentage(obj["efficiency"]),
            luck: parsePercentage(obj["luck"]),
            workers: workersList,
            workersReported: workerValues.map { $0.count == workersList.count } ?? false
        )
        let validNumbers: [Double?] = [
            account.hashRateHPS, account.hashRate1mHPS, account.hashRate5mHPS,
            account.hashRate1hrHPS, account.hashRate1dHPS, account.hashRate7dHPS, account.bestDifficulty,
            account.bestShare, account.bestEver, account.efficiency, account.luck
        ]
        guard
            validNumbers.contains(where: { $0 != nil }) || account.workersCount != nil || account.shares != nil
                || account.lastShare != nil || account.workersReported || !account.workers.isEmpty
        else {
            throw MiningInsightsError.invalidData
        }
        // Per coordinator review: lastShare is miner activity, NOT response sourceTimestamp. Return nil.
        return (account, nil)
    }

    private static func parseWorker(_ item: JSONValue) -> SoloFuryWorkerStats? {
        guard let wObj = item.objectValue, let name = text(wObj["name"]), !name.isEmpty else { return nil }
        return SoloFuryWorkerStats(
            name: name,
            hashRateHPS: parseNonNegativeDouble(wObj["hashRate"]),
            hashRate1mHPS: parseNonNegativeDouble(wObj["hashRate1m"]),
            hashRate1hrHPS: parseNonNegativeDouble(wObj["hashRate1hr"]),
            bestDifficulty: parseNonNegativeDouble(wObj["bestDifficulty"]),
            bestEver: parseNonNegativeDouble(wObj["bestEver"]),
            currentDiff: parseNonNegativeDouble(wObj["currentDiff"]),
            shares: parseNonNegativeInt(wObj["shares"]),
            lastSeen: parseISO8601(text(wObj["lastSeen"])),
            protocolType: text(wObj["protocol"]),
            region: text(wObj["region"])
        )
    }

    // Accepts 0 as a valid telemetry value, rejects negatives/NaNs/infinities
    private static func parseNonNegativeDouble(_ value: JSONValue?) -> Double? {
        guard let val = value?.doubleValue, val.isFinite, val >= 0 else { return nil }
        return val
    }

    private static func parseNonNegativeInt(_ value: JSONValue?) -> Int? {
        MiningInsightsParser.integer(value)
    }
}

/// Small JSON field helpers, split out so the actor declaration stays small.
extension SoloFuryClient {

    private static func parseBlockEvents(_ value: JSONValue?) -> [SoloFuryBlockEvent]? {
        guard let events = value?.arrayValue else { return nil }
        var result: [SoloFuryBlockEvent] = []
        for event in events {
            guard let object = event.objectValue else { return nil }
            let height = parseNonNegativeInt(object["height"])
            let timestamp = MiningInsightsParser.date(object["timestamp"])
            let status = text(object["status"]).flatMap {
                ["confirmed", "pending", "orphan", "orphaned", "rejected"].contains($0) ? $0 : nil
            }
            guard height != nil || timestamp != nil || status != nil else { return nil }
            result.append(SoloFuryBlockEvent(height: height, timestamp: timestamp, status: status))
        }
        return result
    }

    private static func text(_ value: JSONValue?) -> String? {
        guard case .string(let value) = value else { return nil }
        return value
    }

    private static func parsePercentage(_ value: JSONValue?) -> Double? {
        guard let val = value?.doubleValue, val.isFinite, val >= 0 else { return nil }
        return val
    }

    private static func parseISO8601(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
