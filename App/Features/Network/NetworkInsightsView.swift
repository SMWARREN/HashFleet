import SwiftUI
import HashFleetCore

struct NetworkInsightsView: View {
    let fleet: FleetStore
    let insights: MiningInsightsStore
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heading
                    loadControl(now: timeline.date)
                    hubLinks
                    NavigationLink {
                        poolNetworkPage
                    } label: {
                        Label("Pool-reported network data", systemImage: "network")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("insights.poolNetworks")
                    FleetSectionGrid(spacing: 18, minimumRows: 2) {
                        if let network = insights.network {
                            networkCards(network, now: timeline.date)
                            soloCard(network, now: timeline.date)
                        }
                        if let cash = insights.cash {
                            cashCard(cash, now: timeline.date)
                        }
                        if let xec = insights.xec {
                            additionalCoinCard(.xec, result: xec, now: timeline.date)
                        }
                        if let dgb = insights.dgb {
                            additionalCoinCard(.dgb, result: dgb, now: timeline.date)
                        }
                        if let pool = insights.pool {
                            poolCard(pool, now: timeline.date)
                        }
                    }
                    Text(
                        "Each coin uses its own network data source. Pool-reported account rates and shares "
                            + "are separate from miner readings and network difficulty. "
                            + "Your existing miner controls remain on each miner’s detail screen."
                    )
                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                }
                .fleetPageContainer(compactMaxWidth: FleetLayout.listContentWidth)
            }
        }
        .background(FleetTheme.canvas)
        .foregroundStyle(FleetTheme.ink)
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .navigationTitle("Network insights")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: NetworkLoadIdentity(enabled: fleet.preferences.externalDataEnabled,
            demo: fleet.isDemo, phase: scenePhase)) {
            guard fleet.preferences.externalDataEnabled, scenePhase == .active else {
                insights.cancel()
                return
            }
            insights.setDemo(fleet.isDemo)
            while !Task.isCancelled {
                await insights.refresh()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onDisappear { insights.cancel() }
    }

    private var poolNetworkPage: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            ScrollView {
                FleetSectionGrid(spacing: 18, minimumRows: 2) {
                    ForEach(MiningPoolCoin.soloFuryCoins, id: \.self) { coin in
                        if let result = insights.poolNetworks[coin] {
                            poolNetworkCard(coin, result: result, now: timeline.date)
                        }
                    }
                }
                .fleetPageContainer(compactMaxWidth: FleetLayout.listContentWidth)
            }
        }
        .background(FleetTheme.canvas)
        .navigationTitle("Pool network data")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: NetworkLoadIdentity(enabled: fleet.preferences.externalDataEnabled,
            demo: fleet.isDemo, phase: scenePhase)) {
            guard fleet.preferences.externalDataEnabled, scenePhase == .active else { return }
            while !Task.isCancelled {
                await insights.refresh()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }

    private struct NetworkLoadIdentity: Equatable {
        let enabled: Bool
        let demo: Bool
        let phase: ScenePhase
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THE BIGGER PICTURE").fleetFont(.caption2, weight: .medium, design: .monospaced).tracking(1.5).foregroundStyle(FleetTheme.secondary)
            Text("Beyond your fleet").fleetFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
            Text(
                fleet.isDemo
                    ? "Sample network and pool data. No internet requests."
                    : "Coin network conditions and public pool statistics, without changing a single miner setting."
            )
            .foregroundStyle(FleetTheme.secondary)
            if fleet.isDemo { Label("Demo · not live", systemImage: "sparkles").foregroundStyle(FleetTheme.accent) }
        }
    }

    private var loadControlCaption: String {
        fleet.isDemo
            ? "Samples are separate from your real fleet and external services."
            : "Read-only public chain and pool APIs are also shown on the fleet home screen. Each card identifies its source. "
                + "Providers see your internet IP, but public summaries receive no wallet or miner credentials. "
                + "Disable external data in Preferences to stay local-only."
    }

    private func loadControl(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await insights.refresh() }
            } label: {
                HStack {
                    if insights.isLoading { ProgressView() }
                    Label(
                        fleet.isDemo
                            ? "Load sample data"
                            : (insights.network == nil ? "Load public data" : "Refresh public data"),
                        systemImage: "arrow.clockwise"
                    )
                }.frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent).foregroundStyle(FleetTheme.buttonInk)
            .disabled(
                !fleet.preferences.externalDataEnabled || insights.isLoading || now < insights.refreshAvailableAt
            )
            .accessibilityIdentifier("insights.load")
            Text(loadControlCaption)
            .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            if now < insights.refreshAvailableAt {
                Text("Refresh available shortly").fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
        }
    }

    @ViewBuilder private func networkCards(_ network: NetworkSnapshot, now: Date) -> some View {
        priceCard(network, now: now)
        miningCard(network, now: now)
        latestBlockCard(network, now: now)
        mempoolFeeCard(network, now: now)
        backlogCard(network, now: now)
    }

    private func priceCard(_ network: NetworkSnapshot, now: Date) -> some View {
        InsightsSourceCard(title: "BTC · USD", result: network.price, isDemo: insights.isDemo, now: now) {
            let priceText = $0.usd.map { $0.formatted(.currency(code: "USD")) } ?? "Not reported"
            Text(priceText)
                .fleetFont(.largeTitle, weight: .bold).monospacedDigit()
                .fleetNumericUpdate(priceText, reduceMotion: reduceMotion)
        }.accessibilityIdentifier("insights.price")
    }

    private func miningCard(_ network: NetworkSnapshot, now: Date) -> some View {
        InsightsSourceCard(
            title: "Network difficulty & hashrate",
            result: network.mining,
            isDemo: insights.isDemo,
            now: now
        ) { value in
            // Two headline figures side by side, as the approved design shows. Both keep the
            // same audited values and the same row semantics for VoiceOver.
            InsightsMetricColumns(metrics: [
                .init(title: "Estimated network hashrate", value: InsightsFormat.hashrate(value.hashrateHPS)),
                .init(
                    title: "Difficulty",
                    value: value.difficulty.map { InsightsFormat.compact($0) } ?? "Not reported"
                )
            ])
            if let date = value.hashrateSampleAt {
                InsightsRow("Latest historical sample", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            Text("Network estimates are not a measurement of your miner.").fleetFont(.caption).foregroundStyle(
                FleetTheme.secondary
            )
        }.accessibilityIdentifier("insights.mining")
    }

    private func latestBlockCard(_ network: NetworkSnapshot, now: Date) -> some View {
        InsightsSourceCard(
            title: "Latest block",
            result: network.tipHeight,
            isDemo: insights.isDemo,
            now: now
        ) { height in
            InsightsRow("Block height", value: FleetFormat.blockHeight(height))
            InsightsRow(
                "Block subsidy",
                value: SoloMiningMath.blockSubsidyBTC(atHeight: height).map {
                    "\(FleetFormat.number($0, decimals: 8)) BTC"
                } ?? "Not available"
            )
            Text("Subsidy excludes transaction fees and any pool fees.").fleetFont(.caption).foregroundStyle(
                FleetTheme.secondary
            )
        }
    }

    private func mempoolFeeCard(_ network: NetworkSnapshot, now: Date) -> some View {
        InsightsSourceCard(
            title: "Mempool · fee estimates",
            result: network.fees,
            isDemo: insights.isDemo,
            now: now
        ) { value in
            InsightsMetricColumns(metrics: [
                .init(
                    title: "Fastest",
                    value: InsightsFormat.feeRate(value.fastestFee),
                    unit: InsightsFormat.feeUnit(value.fastestFee),
                    caption: "~10 min"
                ),
                .init(
                    title: "Normal",
                    value: InsightsFormat.feeRate(value.halfHourFee),
                    unit: InsightsFormat.feeUnit(value.halfHourFee),
                    caption: "~30 min"
                ),
                .init(
                    title: "Hour",
                    value: InsightsFormat.feeRate(value.hourFee),
                    unit: InsightsFormat.feeUnit(value.hourFee),
                    caption: "~1 hour"
                ),
                .init(
                    title: "Economy",
                    value: InsightsFormat.feeRate(value.economyFee),
                    unit: InsightsFormat.feeUnit(value.economyFee),
                    caption: "~1+ hour"
                )
            ])
            Text("Suggested transaction fees, not confirmation guarantees or mining revenue.").fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
        }.accessibilityIdentifier("insights.fees")
    }

    private func backlogCard(_ network: NetworkSnapshot, now: Date) -> some View {
        InsightsSourceCard(
            title: "Mempool · waiting transactions",
            result: network.backlog,
            isDemo: insights.isDemo,
            now: now
        ) { value in
            InsightsRow("Transactions", value: value.transactionCount?.formatted() ?? "Not reported")
            InsightsRow(
                "Virtual size",
                value: value.virtualSizeBytes.map { "\(FleetFormat.number(Double($0) / 1e6, decimals: 2)) vMB" }
                    ?? "Not reported"
            )
            InsightsRow(
                "Total pending fees",
                value: value.totalFeeSatoshis.map { "\(FleetFormat.number(Double($0) / 1e8, decimals: 8)) BTC" }
                    ?? "Not reported"
            )
        }.accessibilityIdentifier("insights.backlog")
    }
}

#Preview("Network insights · demo") {
    let defaults = UserDefaults(suiteName: "app.hashfleet.network-preview")!
    let fleet = FleetStore(defaults: defaults)
    fleet.loadDemo()
    let insights = MiningInsightsStore()
    insights.setDemo(true)
    return NavigationStack {
        NetworkInsightsView(fleet: fleet, insights: insights)
    }
}
