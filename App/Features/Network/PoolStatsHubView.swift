import SwiftUI
import HashFleetCore

/// Per-pool statistics hub showing every configured pool slot across the user's real miners.
/// Only pools actually configured on connected, non-demo miners appear. Respects the
/// external-data opt-out exactly like NetworkInsightsView.
struct PoolStatsHubView: View {
    let fleet: FleetStore
    @State private var store = ConnectedPoolsStore()
    @Environment(\.scenePhase) private var scenePhase

    private var entries: [PoolStatsHubEntry] {
        let memberships = fleet.devices.flatMap { device -> [PoolStatsHubEntry.Membership] in
            guard let snapshot = fleet.snapshots[device.id],
                  snapshot.error == nil,
                  let info = snapshot.info,
                  let date = snapshot.updatedAt,
                  fleet.isDemo || (-60...300).contains(Date().timeIntervalSince(date))
            else { return [] }
            return ConfiguredMiningPool.resolve(info: info).map {
                PoolStatsHubEntry.Membership(deviceID: device.id, minerName: device.name, pool: $0)
            }
        }
        return PoolStatsHubEntry.grouped(memberships)
    }

    // MARK: - Body

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heading
                    contentBody
                }
                .fleetPageContainer(compactMaxWidth: FleetLayout.listContentWidth)
            }
        }
        .background(FleetTheme.canvas)
        .foregroundStyle(FleetTheme.ink)
        .navigationTitle("Connected pool stats")
        .navigationBarTitleDisplayMode(.inline)
        .task(
            id: LoadIdentity(
                entries: Set(ConnectedPoolsStore.configuredPools(fleet: fleet)),
                enabled: fleet.preferences.externalDataEnabled,
                demo: fleet.isDemo,
                phase: scenePhase
            )
        ) {
            guard scenePhase == .active, fleet.preferences.externalDataEnabled else {
                store.clear()
                return
            }
            while !Task.isCancelled {
                await store.refresh(fleet: fleet)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onDisappear { store.clear() }
        .accessibilityIdentifier("poolHub.page")
    }

    private struct LoadIdentity: Equatable {
        let entries: Set<ConfiguredMiningPool>
        let enabled: Bool
        let demo: Bool
        let phase: ScenePhase
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONNECTED POOL STATS").fleetFont(.caption2, weight: .medium, design: .monospaced).tracking(1.5).foregroundStyle(FleetTheme.secondary)
            Text("Your configured pools").fleetFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
            Text(
                fleet.isDemo
                    ? "Sample pool data. No internet requests."
                    : "Public pool-side statistics for every pool slot configured on your connected miners."
            )
            .foregroundStyle(FleetTheme.secondary)
            if fleet.isDemo {
                Label("Demo · not live", systemImage: "sparkles").foregroundStyle(FleetTheme.accent)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder private var contentBody: some View {
        if !fleet.preferences.externalDataEnabled {
            disabledNotice
        } else {
            let poolEntries = entries
            if poolEntries.isEmpty {
                emptyNotice
            } else {
                VStack(spacing: 16) {
                    ForEach(poolEntries) { item in
                        poolCard(item)
                    }
                }
                Text(
                    "Pool rates are provider rolling estimates, not worker local measurements. "
                        + "Public queries send the payout address and device IP over HTTPS to the respective pool API. "
                        + "No wallet credentials, private keys, or passwords are ever accessed or sent."
                )
                .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
            }
        }
    }

    private var disabledNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("External data disabled", systemImage: "bolt.horizontal.circle")
                .fleetFont(.headline)
            Text(
                "Pool statistics require external data. "
                    + "Enable it in Preferences to see pool-side information for your configured miners."
            )
            .fleetFont(.callout).foregroundStyle(FleetTheme.secondary)
        }
        .fleetCard()
        .accessibilityIdentifier("poolHub.disabled")
    }

    private var emptyNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No configured mining pools reported by online miners.")
                .fleetFont(.callout).foregroundStyle(FleetTheme.secondary)
            Text("Connect a miner with a supported pool (CKPool, SoloFury or SoloPool) to see pool statistics here.")
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
        }
        .fleetCard()
        .accessibilityIdentifier("poolHub.empty")
    }

    // MARK: - Pool Card

    @ViewBuilder private func poolCard(_ item: PoolStatsHubEntry) -> some View {
        let pool = item.pool
        if let provider = pool.provider, provider == .ckpool || provider == .soloFury || provider == .soloPool {
            poolCardBody(item: item, pool: pool, provider: provider)
        }
    }

    private func poolCardBody(
        item: PoolStatsHubEntry,
        pool: ConfiguredMiningPool,
        provider: MiningPoolProvider
    ) -> some View {
        let pKey = PoolKey(provider: provider, coin: pool.coin)
        let aKey: AccountKey? = pool.address.flatMap { address in
            guard !address.isEmpty else { return nil }
            return AccountKey(provider: provider, coin: pool.coin, address: address, host: pool.host)
        }

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pool.providerName ?? provider.rawValue)
                            .fleetFont(.headline)
                            .accessibilityIdentifier("poolHub.provider.\(pool.id)")
                        if let coin = pool.coin {
                            Text(coin.ticker)
                                .font(FleetTheme.mono(12))
                                .foregroundStyle(FleetTheme.accent)
                        }
                    }
                    Spacer()
                    Text("\(item.minerNames.count) connected")
                        .fleetFont(.caption, weight: .semibold)
                        .foregroundStyle(FleetTheme.secondary)
                }
                connectedMinerTags(item.minerNames)
            }

            // Pool-wide stats. SoloPool has no documented pool-wide aggregate endpoint, so show
            // account statistics only for it rather than a permanent "unavailable" pool row.
            if provider != .soloPool {
                poolStatsSection(pKey: pKey)
            }

            // Account stats (if address available)
            if let aKey {
                accountStatsSection(aKey: aKey)
            }

            // Provider web link
            providerLink(provider: provider)

            // Footer
            Text(fleet.isDemo ? "Demo pool sample · not live" : "Pool \(pool.role.lowercased())")
                .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
        }
        .fleetCard(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("poolHub.card.\(provider.rawValue).\(pool.coin?.ticker ?? "unknown")")
    }

    private func connectedMinerTags(_ names: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(names, id: \.self) { name in
                Label(name, systemImage: "cpu")
                    .fleetFont(.caption)
                    .lineLimit(1)
                    .fleetPillPadding()
                    .background(FleetTheme.raised, in: Capsule())
                    .accessibilityIdentifier("poolHub.connectedMiner.\(name)")
            }
        }
        .accessibilityElement(children: .contain)
    }

}

private extension PoolStatsHubView {
    // MARK: - Pool Stats Section

    @ViewBuilder func poolStatsSection(pKey: PoolKey) -> some View {
        if let pResult = store.poolStats[pKey] {
            if let stats = pResult.value {
                FleetSectionLabel(title: "Pool hashrate")
                InsightsRow("Hashrate · 1 hour", value: InsightsFormat.hashrate(stats.hashRate1hrHPS))
                InsightsRow("Hashrate · 1 day", value: InsightsFormat.hashrate(stats.hashRate1dHPS))
                if let users = stats.users {
                    InsightsRow("Users", value: users.formatted())
                }
                if let workers = stats.workers {
                    InsightsRow("Workers", value: workers.formatted())
                }
                if let best = stats.bestShare {
                    InsightsRow("Best share", value: InsightsFormat.compact(best))
                }
                Text("Fetched \(pResult.fetchedAt.formatted(date: .omitted, time: .standard))")
                    .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            } else if let error = pResult.error {
                Label("Pool status unavailable", systemImage: "exclamationmark.circle")
                    .fleetFont(.caption).foregroundStyle(FleetTheme.warning)
                Text(error.localizedDescription)
                    .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            }
        } else if store.isRefreshing {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Loading pool statistics").fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
            .accessibilityIdentifier("poolHub.loading")
        }
    }

    // MARK: - Account Stats Section

    @ViewBuilder func accountStatsSection(aKey: AccountKey) -> some View {
        if let aResult = store.accountStats[aKey] {
            switch aResult {
            case .found(let dataResult):
                accountFoundContent(dataResult)
            case .notFound:
                Text("No pool account statistics recorded for this address yet.")
                    .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            case .failed(let error):
                accountUnavailableLabel(error)
            }
        } else if store.isRefreshing {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Loading account statistics").fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
        }
    }

    @ViewBuilder private func accountFoundContent(
        _ dataResult: MiningDataResult<ConnectedAccountStats>
    ) -> some View {
        if let value = dataResult.value {
            accountStatsRows(value)
            Text("Fetched \(dataResult.fetchedAt.formatted(date: .omitted, time: .standard))")
                .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
        } else if let error = dataResult.error {
            accountUnavailableLabel(error)
        }
    }

    private func accountUnavailableLabel(_ error: Error) -> some View {
        Label("Account unavailable: \(error.localizedDescription)", systemImage: "exclamationmark.circle")
            .fleetFont(.caption2).foregroundStyle(FleetTheme.warning)
    }

    @ViewBuilder private func accountStatsRows(_ value: ConnectedAccountStats) -> some View {
        Divider()
        FleetSectionLabel(title: "Account")
        InsightsRow("Hashrate · 1 hour", value: InsightsFormat.hashrate(value.hashRate1hrHPS))
        InsightsRow("Hashrate · 1 day", value: InsightsFormat.hashrate(value.hashRate1dHPS))
        if let workers = value.workersCount {
            InsightsRow("Workers", value: workers.formatted())
        }
        if let shares = value.shares {
            InsightsRow("Shares", value: InsightsFormat.compact(shares))
        }
        if let best = value.bestShare {
            InsightsRow("Best share", value: InsightsFormat.compact(best))
        }
        if let bestEver = value.bestEver {
            InsightsRow("Best ever", value: InsightsFormat.compact(bestEver))
        }
        if let lastShare = value.lastShare {
            InsightsRow("Last share", value: lastShare.formatted(date: .abbreviated, time: .standard))
        }
    }

    // MARK: - Provider Link

    private func providerLink(provider: MiningPoolProvider) -> some View {
        let (label, urlString): (String, String)
        switch provider {
        case .ckpool: (label, urlString) = ("CKPool", "https://solo.ckpool.org/")
        case .soloFury: (label, urlString) = ("SoloFury", "https://solofury.com/")
        case .soloPool: (label, urlString) = ("SoloPool", "https://dgb-sha.solopool.org/")
        }
        return BrowserLink(
            label: label,
            rawValue: urlString,
            identifier: "poolHub.link.\(provider.rawValue)",
            font: .caption
        )
    }
}

#Preview("Pool stats · demo") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.pool-stats-preview")!)
    store.loadDemo()
    return NavigationStack {
        PoolStatsHubView(fleet: store)
    }
}
