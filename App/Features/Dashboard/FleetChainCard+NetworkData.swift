import SwiftUI
import HashFleetCore

extension ChainObservation {
    static func blockValueUSD(reward: Double?, priceUSD: Double?, priceFresh: Bool) -> Double? {
        guard priceFresh, let reward, reward.isFinite, reward >= 0,
            let priceUSD, priceUSD.isFinite, priceUSD > 0 else { return nil }
        let value = reward * priceUSD
        return value.isFinite && (reward == 0 || value > 0) ? value : nil
    }

    /// Tip APIs identify the last block; a pool's reported height may instead be the candidate.
    /// At a reward boundary, an ambiguous height can't establish the next block's subsidy.
    static func blockReward<Value>(
        for coin: MiningPoolCoin, observation: MiningDataResult<Value>?, now: Date,
        poolHeight: Bool = false, height: (Value) -> Int?
    ) -> Double? {
        guard isFresh(observation, now: now),
            let reported = observation?.value.flatMap(height),
            let next = nextHeight(reported),
            let reward = blockSubsidy(for: coin, height: next),
            !poolHeight || blockSubsidy(for: coin, height: reported) == reward
        else { return nil }
        return reward
    }

    private static func blockSubsidy(for coin: MiningPoolCoin, height: Int) -> Double? {
        switch coin {
        case .btc, .bch, .bc2, .bch2:
            return SoloMiningMath.blockSubsidyBTC(atHeight: height)
        case .xec:
            // A displayed XEC is 100 base units, versus 100 million per BTC.
            return SoloMiningMath.blockSubsidyBTC(atHeight: height).map { $0 * 1_000_000 }
        case .dgb:
            // Mainnet's DigiSpeed schedule. No historical, pre-fork reward is inferred.
            let forkHeight = 1_430_000
            guard height >= forkHeight else { return nil }
            let periods = (height - forkHeight) / 175_200
            let unitsPerCoin: UInt64 = 100_000_000
            var units = 2_157 * unitsPerCoin / 2
            for _ in 0..<periods {
                units = units * 98_884 / 100_000
                if units < unitsPerCoin { return 0 }
            }
            return Double(units) / Double(unitsPerCoin)
        }
    }
}

/// Per-coin network data resolution for FleetChainCard, split out for file/type length.
/// Odds retain their dedicated public sources and existing SoloFury fallback.
extension FleetChainCard {
    struct ChainNetworkData {
        let usd: Double?
        let difficulty: Double?
        let height: Int?
        let fresh: Bool
        let priceFresh: Bool
        let source: String
        var problem: String?
    }

    /// Fallbacks to the whole-fleet hashrate when no miner actively reports this coin.
    func chainRow(coin: MiningPoolCoin, group: ActiveMiningCoins.Group?, now: Date) -> ChainRow {
        let data = networkData(for: coin, now: now)
        return ChainRow(
            coin: coin,
            usd: data.usd,
            difficulty: data.difficulty,
            height: data.height,
            fresh: data.fresh,
            priceFresh: data.priceFresh,
            rate: group.map { $0.rateHPS } ?? ChainObservation.freshFleetRateHPS(devices: fleet.devices, snapshots: fleet.snapshots, now: now, isDemo: fleet.isDemo),
            source: data.source,
            miners: group?.miners ?? 0,
            reward: compactPreview ? blockReward(for: coin, now: now) : nil,
            oddsOverride: data.problem
        )
    }

    private func blockReward(for coin: MiningPoolCoin, now: Date) -> Double? {
        switch coin {
        case .btc:
            return ChainObservation.blockReward(for: coin, observation: insights.network?.tipHeight, now: now,
                                                height: { $0 })
        case .bch, .xec, .dgb:
            let stats = coin == .bch ? insights.cash : (coin == .xec ? insights.xec : insights.dgb)
            return ChainObservation.blockReward(for: coin, observation: stats, now: now, height: \.tipHeight)
        case .bc2, .bch2:
            return ChainObservation.blockReward(for: coin, observation: insights.poolNetworks[coin], now: now,
                                                poolHeight: true, height: \.blockHeight)
        }
    }

    func networkData(for coin: MiningPoolCoin, now: Date) -> ChainNetworkData {
        let primary = primaryNetworkData(for: coin, now: now)
        guard primary.problem != nil, coin != .dgb else { return primary }
        let pool = insights.poolNetworks[coin]
        let problem = ChainObservation.networkProblem(pool, difficulty: pool?.value?.networkDifficulty, now: now)
        guard problem == nil || coin == .bc2 || coin == .bch2 else { return primary }
        return ChainNetworkData(usd: primary.usd,
            difficulty: pool?.value?.networkDifficulty, height: pool?.value?.blockHeight,
            fresh: problem == nil, priceFresh: primary.priceFresh,
            source: "SoloFury · pool-reported network", problem: problem)
    }

    func primaryNetworkData(for coin: MiningPoolCoin, now: Date) -> ChainNetworkData {
        switch coin {
        case .btc:
            return btcNetworkData(now: now)
        case .bch:
            return bchNetworkData(now: now)
        case .xec:
            return xecNetworkData(now: now)
        case .dgb:
            return dgbNetworkData(now: now)
        case .bc2, .bch2:
            return unverifiedNetworkData(for: coin, now: now)
        }
    }

    func btcNetworkData(now: Date) -> ChainNetworkData {
        ChainNetworkData(
            usd: insights.network?.price.value?.usd,
            difficulty: insights.network?.mining.value?.difficulty,
            height: insights.network?.tipHeight.value,
            fresh: ChainObservation.isFresh(insights.network?.mining, now: now),
            priceFresh: ChainObservation.isFresh(insights.network?.price, now: now),
            source: "mempool.space",
            problem: ChainObservation.networkProblem(insights.network?.mining,
                difficulty: insights.network?.mining.value?.difficulty, now: now)
        )
    }

    func bchNetworkData(now: Date) -> ChainNetworkData {
        ChainNetworkData(
            usd: insights.cash?.value?.usd,
            difficulty: insights.cash?.value?.difficulty,
            height: insights.cash?.value?.tipHeight,
            fresh: ChainObservation.isFresh(insights.cash, now: now),
            priceFresh: ChainObservation.isFresh(insights.cash, now: now),
            source: "Blockchair",
            problem: ChainObservation.networkProblem(insights.cash,
                difficulty: insights.cash?.value?.difficulty, now: now)
        )
    }

    func xecNetworkData(now: Date) -> ChainNetworkData {
        // The offline preview already has an XEC quote in its sample stats. The live
        // path continues to use its independently timestamped CoinGecko observation.
        let sample = compactPreview && fleet.isDemo ? insights.xec : nil
        let sampleUSD = sample?.value?.usd
        return ChainNetworkData(
            usd: sampleUSD ?? insights.coinMarkets[.xec]?.currentPriceUSD,
            difficulty: insights.xec?.value?.difficulty,
            height: insights.xec?.value?.tipHeight,
            fresh: ChainObservation.isFresh(insights.xec, now: now),
            priceFresh: sampleUSD != nil ? ChainObservation.isFresh(sample, now: now)
                : ChainObservation.isFresh(insights.coinMarketsResult, now: now),
            source: MiningInsightsEndpoint.xecStats.sourceName,
            problem: ChainObservation.networkProblem(insights.xec,
                difficulty: insights.xec?.value?.difficulty, now: now)
        )
    }

    func dgbNetworkData(now: Date) -> ChainNetworkData {
        ChainNetworkData(
            usd: insights.dgb?.value?.usd ?? insights.coinMarkets[.dgb]?.currentPriceUSD,
            difficulty: insights.dgb?.value?.difficulty,
            height: insights.dgb?.value?.tipHeight,
            fresh: ChainObservation.isFresh(insights.dgb, now: now),
            priceFresh: insights.dgb?.value?.usd != nil
                ? ChainObservation.isFresh(insights.dgb, now: now)
                : ChainObservation.isFresh(insights.coinMarketsResult, now: now),
            source: MiningInsightsEndpoint.dgbStats.sourceName,
            problem: ChainObservation.networkProblem(insights.dgb,
                difficulty: insights.dgb?.value?.difficulty, now: now)
        )
    }

    func unverifiedNetworkData(for coin: MiningPoolCoin, now: Date) -> ChainNetworkData {
        ChainNetworkData(
            usd: insights.coinMarkets[coin]?.currentPriceUSD,
            difficulty: nil,
            height: nil,
            fresh: false,
            priceFresh: ChainObservation.isFresh(insights.coinMarketsResult, now: now),
            source: "No verified network difficulty source",
            problem: "No verified difficulty source"
        )
    }

}
