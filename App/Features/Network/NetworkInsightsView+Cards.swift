import SwiftUI
import HashFleetCore

extension NetworkInsightsView {
    internal func poolNetworkCard(
        _ coin: MiningPoolCoin, result: MiningDataResult<SoloFuryPoolStats>, now: Date
    ) -> some View {
        InsightsSourceCard(title: "\(coin.ticker) · SoloFury network & pool", result: result,
            isDemo: insights.isDemo, now: now) { value in
            InsightsRow("Reported network difficulty", value: value.networkDifficulty.map(InsightsFormat.compact) ?? "Not reported")
                .accessibilityIdentifier("insights.poolNetwork.\(coin.ticker).difficulty")
            InsightsRow("Reported block height", value: value.blockHeight.map(FleetFormat.blockHeight) ?? "Not reported")
                .accessibilityIdentifier("insights.poolNetwork.\(coin.ticker).height")
            InsightsRow("Pool hashrate · 1 hour", value: InsightsFormat.hashrate(value.totalHashRate1hrHPS))
                .accessibilityIdentifier("insights.poolNetwork.\(coin.ticker).hashrate")
            InsightsRow("Pool miners / workers", value: "\(value.totalMiners?.formatted() ?? "?") / \(value.totalWorkers?.formatted() ?? "?")")
                .accessibilityIdentifier("insights.poolNetwork.\(coin.ticker).counts")
            Text("Pool-reported network data can fill a missing public explorer reading. Pool hashrate is not your miner's hashrate. No wallet is sent for these summaries.")
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            if result.sourceTimestamp == nil {
                Text("No provider snapshot timestamp is supplied. Age reflects retrieval time, not an independently verified node update.")
                    .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
        }

    }

    internal func additionalCoinCard(
        _ coin: MiningPoolCoin, result: MiningDataResult<BitcoinCashStatistics>, now: Date
    ) -> some View {
        InsightsSourceCard(title: "\(coin.ticker) · network", result: result, isDemo: insights.isDemo, now: now) { value in
            InsightsRow(coin == .dgb ? "SHA-256d network difficulty" : "Network difficulty",
                value: value.difficulty.map(InsightsFormat.compact) ?? "Not reported")
                .accessibilityIdentifier("insights.coinNetwork.\(coin.ticker).difficulty")
            InsightsRow("Block height", value: value.tipHeight.map(FleetFormat.blockHeight) ?? "Not reported")
                .accessibilityIdentifier("insights.coinNetwork.\(coin.ticker).height")
            if let price = value.usd {
                InsightsRow("\(coin.ticker) price", value: price.formatted(.currency(code: "USD")))
            }
            Text(coin == .dgb
                ? "DigiByte uses multiple mining algorithms. Only SHA-256d network difficulty is valid for these miners. Pool share difficulty is not network difficulty."
                : "This is eCash network data, not Bitcoin or Bitcoin Cash data.")
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
        }

    }

    internal func cashCard(_ cash: MiningDataResult<BitcoinCashStatistics>, now: Date) -> some View {
        InsightsSourceCard(
            title: "BCH · network",
            result: cash,
            isDemo: insights.isDemo,
            now: now
        ) { value in
            InsightsRow(
                "BCH price",
                value: value.usd.map { $0.formatted(.currency(code: "USD")) } ?? "Not reported"
            )
            InsightsRow(
                "Difficulty",
                value: value.difficulty.map(InsightsFormat.compact) ?? "Not reported"
            )
            InsightsRow("Block height", value: value.tipHeight.map(FleetFormat.blockHeight) ?? "Not reported")
            InsightsRow(
                "Mempool transactions",
                value: value.mempoolTransactions?.formatted() ?? "Not reported"
            )
            InsightsRow(
                "Network hashrate · 24 hours",
                value: InsightsFormat.hashrate(value.hashrate24HoursHPS)
            )
        }.accessibilityIdentifier("insights.cash")
    }

    internal func poolCard(_ pool: MiningDataResult<CKPoolSummary>, now: Date) -> some View {
        InsightsSourceCard(
            title: "CKPool · public pool",
            result: pool,
            isDemo: insights.isDemo,
            now: now
        ) { value in
            InsightsRow(
                "Pool hashrate · 1 hour",
                value: InsightsFormat.hashrate(value.hashrate1HourHPS)
            )
            InsightsRow(
                "Pool hashrate · 1 day",
                value: InsightsFormat.hashrate(value.hashrate1DayHPS)
            )
            InsightsRow("Users", value: value.users?.formatted() ?? "Not reported")
            InsightsRow("Workers", value: value.workers?.formatted() ?? "Not reported")
            Text("Pool-wide estimates, not your miner's local hashrate or a payout balance.")
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
        }
        .accessibilityIdentifier("insights.pool")
    }

    internal var hubLinks: some View {
        Group {
            NavigationLink {
                PoolStatsHubView(fleet: fleet)
            } label: {
                Label("Connected pool stats", systemImage: "square.stack.3d.up")
                    .fleetFont(.headline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .fleetCard()
            }
            .accessibilityIdentifier("insights.poolHub")
            NavigationLink {
                CKPoolLookupView(
                    insights: insights,
                    externalDataEnabled: fleet.preferences.externalDataEnabled
                )
            } label: {
                Label("Look up my CKPool statistics", systemImage: "person.crop.circle.badge.magnifyingglass")
                    .fleetFont(.headline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .fleetCard()
            }
            .accessibilityIdentifier("insights.lookup")
        }
    }

}
