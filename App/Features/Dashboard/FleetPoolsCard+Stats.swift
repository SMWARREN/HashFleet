import SwiftUI
import HashFleetCore

/// Public pool/account statistics disclosures, badges, and footer copy for FleetPoolsCard.
extension FleetPoolsCard {
    // MARK: - Stats Disclosure

    func statsDisclosure(
        provider: MiningPoolProvider,
        coin: MiningPoolCoin?,
        address: String?,
        host: String
    ) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                if !fleet.preferences.externalDataEnabled {
                    Text("External public data is turned off in preferences.")
                        .fleetFont(.caption2)
                        .foregroundStyle(FleetTheme.secondary)
                } else {
                    // Pool Summary
                    let pKey = PoolKey(provider: provider, coin: coin)
                    if let pResult = store.poolStats[pKey] {
                        if let pVal = pResult.value {
                            poolStatsView(provider: provider, stats: pVal, result: pResult)
                        } else if let error = pResult.error {
                            Text("Pool status unavailable: \(error.localizedDescription)")
                                .fleetFont(.caption2)
                                .foregroundStyle(FleetTheme.warning)
                        }
                    } else if store.isRefreshing {
                        ProgressView().scaleEffect(0.7)
                    }

                    // Account Details
                    if let address, !address.isEmpty {
                        let aKey = AccountKey(provider: provider, coin: coin, address: address, host: host)
                        if let aResult = store.accountStats[aKey] {
                            accountStatsView(result: aResult)
                        } else if store.isRefreshing {
                            ProgressView().scaleEffect(0.7)
                        }
                    } else {
                        Text(
                            "Account lookup unavailable: no valid payout address for this coin was reported. " +
                                "Pool-wide statistics remain available."
                        )
                        .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Public \(provider == .ckpool ? "CKPool" : "SoloFury") statistics", systemImage: "chart.bar")
                .fleetFont(.caption, weight: .medium)
                .foregroundStyle(FleetTheme.accent)
        }.accessibilityIdentifier("fleetPools.stats.\(provider.rawValue).\(coin?.rawValue ?? "unknown")")
    }

    private func poolStatsView(
        provider: MiningPoolProvider,
        stats: ConnectedPoolStats,
        result: MiningDataResult<ConnectedPoolStats>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Pool 1h rolling rate:").fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
                Text(InsightsFormat.hashrate(stats.hashRate1hrHPS))
                    .font(FleetTheme.mono(11))
                Spacer()
                if let workers = stats.workers {
                    Text("\(workers) pool workers").fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
                }
            }
            Text(
                fleet.isDemo
                    ? "Demo pool sample · not live"
                    : "Fetched \(result.fetchedAt.formatted(date: .omitted, time: .standard)); " +
                        "provider cache age may be unknown."
            )
            .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            if let date = result.sourceTimestamp {
                Text("Pool data as of \(date.formatted(date: .omitted, time: .standard))")
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
            }
        }
    }

    private func accountStatsView(result: ConnectedAccountResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            switch result {
            case .found(let dataResult):
                if let value = dataResult.value {
                    accountValuesView(value)
                    accountFetchNote(dataResult)
                }
            case .notFound:
                Text("No pool account statistics recorded for this address yet.")
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
            case .failed(let err):
                Text("Account statistics unavailable: \(err.localizedDescription)")
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.warning)
            }
        }
    }

    @ViewBuilder
    private func accountValuesView(_ value: ConnectedAccountStats) -> some View {
        HStack {
            Text("Account 1h rolling rate:").fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            Text(InsightsFormat.hashrate(value.hashRate1hrHPS))
                .font(FleetTheme.mono(11))
        }
        if let shares = value.shares {
            HStack {
                Text("Reported shares:").fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
                Text(InsightsFormat.compact(shares))
                    .font(FleetTheme.mono(11))
                Spacer()
            }
        }
        if let best = value.bestShare {
            Text("Best share: \(InsightsFormat.compact(best))")
                .font(FleetTheme.mono(11)).foregroundStyle(FleetTheme.secondary)
        }
        if let dailyRate = value.hashRate1dHPS {
            Text("Account 24h rolling rate: \(InsightsFormat.hashrate(dailyRate))").fleetFont(.caption2)
        }
        if let workers = value.workersCount {
            Text("Reported account workers: \(workers)").fleetFont(.caption2)
        }
        if let lastShare = value.lastShare {
            Text("Last share: \(lastShare.formatted(date: .abbreviated, time: .standard))")
                .fleetFont(.caption2)
                .foregroundStyle(FleetTheme.secondary)
        }
        if let best = value.bestEver {
            Text("Account best-ever share: \(InsightsFormat.compact(best))").fleetFont(.caption2)
        }
    }

    private func accountFetchNote(_ result: MiningDataResult<ConnectedAccountStats>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(
                fleet.isDemo
                    ? "Demo account sample · not live"
                    : "Fetched \(result.fetchedAt.formatted(date: .omitted, time: .standard))"
            )
            .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            if let date = result.sourceTimestamp {
                Text("Account response time: \(date.formatted(date: .omitted, time: .standard))")
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
            }
        }
    }

    // MARK: - Badges & Footers

    func activeBadge(_ active: Bool) -> some View {
        Text(active ? "ACTIVE" : "STANDBY")
            .font(FleetTheme.mono(9))
            .foregroundStyle(active ? FleetTheme.positive : FleetTheme.secondary)
            .fleetPillPadding()
            .background(active ? FleetTheme.positive.opacity(0.15) : FleetTheme.separator.opacity(0.4), in: Capsule())
    }

    func coinBadge(_ coin: MiningPoolCoin) -> some View {
        let market = marketData[coin]
        let ticker = market?.ticker ?? coin.ticker
        return CoinGeckoIcon(coin: coin, fallbackTicker: ticker, size: 20)
            .frame(width: 32, height: 28, alignment: .center)
            .accessibilityLabel(ticker)
            .font(FleetTheme.mono(9))
            .foregroundStyle(FleetTheme.accent)
            .fleetPillPadding()
            .background(FleetTheme.accent.opacity(0.12), in: Capsule())
    }

    func coverageBadge(count: Int) -> some View {
        let text = fleet.isDemo ? "DEMO" : "\(count) slot\(count == 1 ? "" : "s")"
        return Text(text)
            .font(FleetTheme.mono(10))
            .foregroundStyle(FleetTheme.secondary)
            .fleetPillPadding()
            .background(FleetTheme.separator.opacity(0.4), in: Capsule())
    }

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                "Accepted shares are work, not a share in another miner’s solo reward. " +
                    "Best share is not a verified block or payout."
            )
            .fleetFont(.caption2)
            .foregroundStyle(FleetTheme.secondary)
            Text(
                "Pool rates are provider rolling estimates, not worker local measurements " +
                    "or worker-online claims. Public queries send the payout address and device IP " +
                    "over HTTPS to the respective pool API. No wallet credentials, private keys, " +
                    "or passwords are ever accessed or sent."
            )
            .fleetFont(.caption2)
            .foregroundStyle(FleetTheme.secondary)
        }
    }
}
