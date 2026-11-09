import Foundation

/// Public REST client for SoloPool mining pool account statistics, DGB only.
/// Hardened privacy controls, matching `SoloFuryClient`'s exact safety posture:
/// - Ephemeral URLSession with credential storage nil, cookies disabled, local cache ignored
/// - Custom URLSessionTaskDelegate blocking redirects per-task
/// - Injected URLSession sanitizes configuration and enforces delegate
/// - Fixed 15s timeout
/// - Task.checkCancellation before and after fetch
/// - Caps response body to 1 MB
/// - GET only
///
/// IMPORTANT HOST DISCREPANCY (verified live 2026-09-10, deviating from the assigned brief):
/// `ConfiguredMiningPool.documentedSoloPoolHosts` (`us1.solopool.org`, `eu2.solopool.org`,
/// `eu3.solopool.org`) are SoloPool's *stratum mining* hosts only. They refuse all HTTP/HTTPS
/// connections outright (connection refused on ports 80 and 443) and do not serve `/api/...`.
/// The real, live JSON HTTP API is served from separate per-coin subdomains discovered from
/// SoloPool's own site bundle (`dgb-sha.solopool.org`, `btc.solopool.org`, `bch.solopool.org`,
/// `doge.solopool.org`, `ltc.solopool.org`, `rvn.solopool.org`, `xec.solopool.org`, ...), and the
/// task-provided `GET https://dgb-sha.solopool.org/api/miners/{address}` was confirmed live and
/// working. If this client literally built the request against `pool.host` from
/// `documentedSoloPoolHosts` as instructed, every real request would fail with a connection error
/// and the feature would never work in production.
///
/// This client therefore follows `SoloFuryClient.account`'s exact structure: `pool.host` is used
/// only as an authorization check (proving the configured pool is genuinely a documented SoloPool
/// DGB entry, not caller-supplied trust), while the actual network request always targets the
/// fixed, verified-working `productionBaseURL` below, exactly as `SoloFuryClient` targets a fixed
/// `https://solofury.com` regardless of the configured stratum host.
public actor SoloPoolClient {
    /// Verified live 2026-09-10: the only confirmed-working HTTP API host for DGB SHA-256d.
    public static let productionBaseURL = URL(string: "https://dgb-sha.solopool.org")!

    private let transport: SoloMiningHTTPClient

    public init(session: URLSession? = nil) {
        transport = SoloMiningHTTPClient(session: session)
    }

    /// Fetches account statistics for a configured SoloPool DGB pool entry.
    /// Re-validates provider, coin, host, and address at the API boundary. The caller-supplied
    /// `ConfiguredMiningPool` is not treated as a trust boundary, exactly like `SoloFuryClient.account`.
    public func account(pool: ConfiguredMiningPool) async -> MiningDataResult<SoloPoolAccountStats> {
        guard !Task.isCancelled else {
            return cancelled(Self.productionBaseURL, error: .cancelled)
        }
        guard pool.provider == .soloPool else {
            return cancelled(Self.productionBaseURL, error: .invalidData)
        }
        guard pool.coin == .dgb else {
            return cancelled(Self.productionBaseURL, error: .invalidData)
        }
        guard let address = pool.address, !address.isEmpty else {
            return cancelled(Self.productionBaseURL, error: .invalidBitcoinAddress)
        }

        // Public ConfiguredMiningPool initializers are not a trust boundary. Re-check the host is
        // an exact documented SoloPool host, never derived from caller-supplied free text. This
        // proves the entry genuinely came from a recognized SoloPool configuration, even though
        // the request itself targets the fixed production API host above (see type doc).
        let host = pool.host.lowercased()
        guard ConfiguredMiningPool.documentedSoloPoolHosts.contains(host) else {
            return cancelled(Self.productionBaseURL, error: .invalidData)
        }

        // Re-validate address matches the coin (DGB).
        guard let validatedAddress = DigiByteAddress.validated(address) else {
            return cancelled(Self.productionBaseURL, error: .invalidBitcoinAddress)
        }

        // No path traversal or URL-structural characters.
        guard !validatedAddress.contains("/"), !validatedAddress.contains("\\"), !validatedAddress.contains("%"),
            !validatedAddress.contains(".."), !validatedAddress.contains("?"), !validatedAddress.contains("#")
        else {
            return cancelled(Self.productionBaseURL, error: .invalidBitcoinAddress)
        }

        guard let directory = URL(string: "/api/miners/", relativeTo: Self.productionBaseURL)?.absoluteURL else {
            return cancelled(Self.productionBaseURL, error: .invalidResponse)
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

    public static func parseAccountStats(_ data: Data) throws -> (SoloPoolAccountStats, Date?) {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
            let obj = json.objectValue
        else {
            throw MiningInsightsError.invalidData
        }

        // `workers` is a dict keyed by worker id, not an array; `blocks`, `blocksSummary`
        // and `charts` stay absent (not empty) when the response omits them.
        let (workersList, workersReported) = parseWorkers(obj)
        let blocks = parseBlocks(obj)
        let blocksSummary = parseBlocksSummary(obj)
        let charts = parseCharts(obj)

        let account = SoloPoolAccountStats(
            hashRateHPS: parseUnsignedInt(obj["hashrate"]),
            averageHashRateHPS: parseUnsignedInt(obj["averageHashrate"]),
            onlineWorkers: parseNonNegativeInt(obj["onlineWorkers"]),
            offlineWorkers: parseNonNegativeInt(obj["offlineWorkers"]),
            deadWorkers: parseNonNegativeInt(obj["deadWorkers"]),
            totalWorkers: parseNonNegativeInt(obj["totalWorkers"]),
            lastShare: parseUnixDate(obj["lastShare"]),
            roundShares: parseUnsignedInt(obj["roundShares"]),
            bestShare: parseUnsignedInt(obj["bestShare"]),
            totalBlocks: parseNonNegativeInt(obj["totalBlocks"]),
            lastBlockTime: parseUnixDate(obj["lastBlockTime"]),
            workers: workersList,
            workersReported: workersReported,
            blocks: blocks,
            blocksSummary: blocksSummary,
            charts: charts
        )

        let validUnsigned: [UInt64?] = [
            account.hashRateHPS, account.averageHashRateHPS, account.roundShares, account.bestShare
        ]
        let validInts: [Int?] = [
            account.onlineWorkers, account.offlineWorkers, account.deadWorkers, account.totalWorkers,
            account.totalBlocks
        ]
        guard
            validUnsigned.contains(where: { $0 != nil }) || validInts.contains(where: { $0 != nil })
                || account.lastShare != nil || account.lastBlockTime != nil || account.workersReported
                || !account.workers.isEmpty || account.blocks != nil || account.blocksSummary != nil
                || account.charts != nil
        else {
            throw MiningInsightsError.invalidData
        }
        return (account, nil)
    }

    // Accepts 0 as a valid telemetry value, rejects negatives/NaNs/infinities/non-integers/overflow.

    private static func parseUnsignedInt(_ value: JSONValue?) -> UInt64? {
        switch value {
        case .unsignedInteger(let val): return val
        case .integer(let val): return val >= 0 ? UInt64(exactly: val) : nil
        case .number(let val):
            return val.isFinite && val >= 0 && val == val.rounded(.towardZero) ? UInt64(exactly: val) : nil
        default: return nil
        }
    }

    private static func parseNonNegativeInt(_ value: JSONValue?) -> Int? {
        MiningInsightsParser.integer(value)
    }

    private static func parseNonNegativeDouble(_ value: JSONValue?) -> Double? {
        guard let val = value?.doubleValue, val.isFinite, val >= 0 else { return nil }
        return val
    }

    private static func parseBool(_ value: JSONValue?) -> Bool? {
        guard case .bool(let value) = value else { return nil }
        return value
    }

    private static func parseState(_ value: JSONValue?) -> Int? {
        // Documented values: 1 confirmed, -1 orphan, 0 pending. Reject anything else as unverified.
        guard case .integer(let value) = value, let intValue = Int(exactly: value),
            [-1, 0, 1].contains(intValue)
        else { return nil }
        return intValue
    }

    private static func text(_ value: JSONValue?) -> String? {
        guard case .string(let value) = value else { return nil }
        return value
    }

    private static func parseUnixDate(_ value: JSONValue?) -> Date? {
        guard let timestamp = value?.doubleValue, timestamp.isFinite, timestamp >= 0,
            timestamp <= Date.distantFuture.timeIntervalSince1970
        else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }
}

extension SoloPoolClient {
    private static func parseWorkers(_ obj: [String: JSONValue]) -> ([SoloPoolWorkerStats], Bool) {
        let workerDict = obj["workers"]?.objectValue
        let list: [SoloPoolWorkerStats] =
            (workerDict?.compactMap { key, item -> SoloPoolWorkerStats? in
                guard let wObj = item.objectValue else { return nil }
                return SoloPoolWorkerStats(
                    name: key,
                    hashRateHPS: parseUnsignedInt(wObj["hr"]),
                    averageHashRateHPS: parseUnsignedInt(wObj["avgHr"]),
                    lastShare: parseUnixDate(wObj["lastShare"]),
                    validShares: parseNonNegativeInt(wObj["validShares"]),
                    invalidShares: parseNonNegativeInt(wObj["invalidShares"]),
                    staleShares: parseNonNegativeInt(wObj["staleShares"]),
                    offline: parseBool(wObj["offline"]),
                    dead: parseBool(wObj["dead"]),
                    port: parseNonNegativeInt(wObj["port"]),
                    geo: text(wObj["geo"])
                )
            } ?? []).sorted { $0.name < $1.name }
        // A malformed entry inside the dict is dropped, not fabricated; only distinguish reported vs absent.
        return (list, workerDict != nil)
    }

    private static func parseBlocks(_ obj: [String: JSONValue]) -> [SoloPoolBlockEntry]? {
        obj["blocks"]?.arrayValue.map { items in
            items.compactMap { item -> SoloPoolBlockEntry? in
                guard let bObj = item.objectValue else { return nil }
                return SoloPoolBlockEntry(
                    height: parseNonNegativeInt(bObj["height"]),
                    hash: text(bObj["hash"]),
                    tx: text(bObj["tx"]),
                    timestamp: parseUnixDate(bObj["timestamp"]),
                    networkDifficulty: parseNonNegativeDouble(bObj["networkDifficulty"]),
                    shareDiff: parseNonNegativeDouble(bObj["shareDiff"]),
                    poolShares: parseNonNegativeDouble(bObj["poolShares"]),
                    minerShares: parseNonNegativeDouble(bObj["minerShares"]),
                    blockReward: parseUnsignedInt(bObj["blockReward"]),
                    minerReward: parseUnsignedInt(bObj["minerReward"]),
                    feeReward: parseUnsignedInt(bObj["feeReward"]),
                    // This endpoint is scoped to the caller's own requested address (an account
                    // lookup, not a public/global block feed), so echoing the pool-reported miner
                    // and worker identifiers here does not leak another wallet's identity.
                    miner: text(bObj["miner"]),
                    worker: text(bObj["worker"]),
                    geo: text(bObj["geo"]),
                    state: parseState(bObj["state"])
                )
            }
        }
    }

    private static func parseBlocksSummary(_ obj: [String: JSONValue]) -> [SoloPoolBlocksSummaryEntry]? {
        obj["blocksSummary"]?.arrayValue.map { items in
            items.compactMap { item -> SoloPoolBlocksSummaryEntry? in
                guard let sObj = item.objectValue else { return nil }
                return SoloPoolBlocksSummaryEntry(
                    period: parseNonNegativeInt(sObj["period"]),
                    blocks: parseNonNegativeInt(sObj["blocks"]),
                    total: parseUnsignedInt(sObj["total"]),
                    luck: parseNonNegativeDouble(sObj["luck"])
                )
            }
        }
    }

    private static func parseCharts(_ obj: [String: JSONValue]) -> [SoloPoolChartPoint]? {
        obj["charts"]?.arrayValue.map { items in
            items.compactMap { item -> SoloPoolChartPoint? in
                guard let cObj = item.objectValue else { return nil }
                return SoloPoolChartPoint(
                    timestamp: parseUnixDate(cObj["x"]),
                    hashRateHPS: parseUnsignedInt(cObj["y"])
                )
            }
        }
    }
}
