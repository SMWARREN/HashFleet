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
                    statusBar(now: timeline.date)
                    if !fleet.preferences.externalDataEnabled {
                        offlineBanner
                    }
                    toolsAndLookupsSection
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
            #if !os(macOS)
            .refreshable {
                guard fleet.preferences.externalDataEnabled else { return }
                await insights.refresh(force: true)
            }
            #endif
        }
        .background(FleetTheme.canvas)
        .foregroundStyle(FleetTheme.ink)
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .navigationTitle("Network insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: FleetToolbarLocation.trailing) {
                Button {
                    Task { await insights.refresh(force: true) }
                } label: {
                    if insights.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(!fleet.preferences.externalDataEnabled || insights.isLoading)
                .help("Refresh network data (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
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

    internal var poolNetworkPage: some View {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("THE BIGGER PICTURE")
                        .fleetFont(.caption2, weight: .medium, design: .monospaced)
                        .tracking(1.5)
                        .foregroundStyle(FleetTheme.secondary)
                    Text("Beyond your fleet")
                        .fleetFont(.largeTitle, weight: .bold)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                if fleet.isDemo {
                    Label("Demo · not live", systemImage: "sparkles")
                        .fleetFont(.caption, weight: .semibold)
                        .foregroundStyle(FleetTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(FleetTheme.accent.opacity(0.12), in: Capsule())
                } else if !fleet.preferences.externalDataEnabled {
                    Label("Offline", systemImage: "wifi.slash")
                        .fleetFont(.caption, weight: .semibold)
                        .foregroundStyle(FleetTheme.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(FleetTheme.warning.opacity(0.12), in: Capsule())
                }
            }
            Text(
                fleet.isDemo
                    ? "Sample network and pool data. No internet requests."
                    : "Coin network conditions and public pool statistics, without changing a single miner setting."
            )
            .foregroundStyle(FleetTheme.secondary)
        }
    }

    private func statusBar(now: Date) -> some View {
        HStack(alignment: .center) {
            if insights.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Updating network data…")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                }
            } else if let latest = latestFetchDate {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("Updated \(latest.formatted(date: .omitted, time: .standard))")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(fleet.preferences.externalDataEnabled ? Color.green : FleetTheme.secondary)
                        .frame(width: 7, height: 7)
                    Text(fleet.isDemo ? "Sample data" : (fleet.preferences.externalDataEnabled ? "Ready" : "Offline"))
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                }
            }

            Spacer()

            Button {
                Task { await insights.refresh(force: true) }
            } label: {
                HStack(spacing: 5) {
                    if insights.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(insights.isLoading ? "Refreshing…" : "Refresh")
                        .fleetFont(.caption, weight: .medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(FleetTheme.ink.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!fleet.preferences.externalDataEnabled || insights.isLoading)
            .accessibilityIdentifier("insights.load")
            .accessibilityLabel("Refresh network data")
            .help("Refresh network data (⌘R)")
        }
        .padding(.horizontal, 2)
    }

    private var latestFetchDate: Date? {
        insights.network?.mining.fetchedAt
            ?? insights.pool?.fetchedAt
            ?? insights.cash?.fetchedAt
    }

    private var offlineBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "wifi.slash")
                .fleetFont(.title2)
                .foregroundStyle(FleetTheme.warning)
                .frame(width: 32, height: 32)
                .background(FleetTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("External network data is turned off")
                    .fleetFont(.headline, weight: .semibold)
                    .foregroundStyle(FleetTheme.ink)
                Text(
                    "HashFleet is in local-only mode. Public Bitcoin and altcoin network conditions, "
                        + "mempool fee estimates, and pool statistics require external read-only internet access. "
                        + "You can enable external data anytime in Preferences."
                )
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fleetCard(padding: 0, cornerRadius: 16)
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
