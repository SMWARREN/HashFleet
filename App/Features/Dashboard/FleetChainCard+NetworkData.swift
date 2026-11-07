import SwiftUI
import HashFleetCore

/// Per-coin network data resolution for FleetChainCard, split out for file/type length.
/// Behavior is unchanged: each coin's data comes from its dedicated public source, with
/// SoloFury pool-reported fallback applied uniformly in `networkData(for:now:)`.
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
            oddsOverride: data.problem
        )
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
        ChainNetworkData(
            usd: insights.coinMarkets[.xec]?.currentPriceUSD,
            difficulty: insights.xec?.value?.difficulty,
            height: insights.xec?.value?.tipHeight,
            fresh: ChainObservation.isFresh(insights.xec, now: now),
            priceFresh: ChainObservation.isFresh(insights.coinMarketsResult, now: now),
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
