import SwiftUI
import HashFleetCore

struct FleetChainCard: View {
    let fleet: FleetStore
    let insights: MiningInsightsStore
    var compact: Bool = false
    var compactPreview: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingAssumptions = false
    @State private var selectedOddsWindow: SoloOddsWindow = .month
    @State private var previewDestination: PreviewDestination?

    private enum PreviewDestination: Hashable { case coins, network }

    private var cardInk: Color { compactPreview ? FleetTheme.ink : FleetTheme.panelInk }
    private var cardSecondary: Color { compactPreview ? FleetTheme.secondary : FleetTheme.panelSecondary }

    private var canLoad: Bool {
        FleetChainDataPolicy.canDisplay(isDemo: fleet.isDemo,
                                       externalDataEnabled: fleet.preferences.externalDataEnabled)
            && !fleet.devices.isEmpty && (fleet.isDemo || fleet.onlineCount > 0)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(alignment: .leading, spacing: compactPreview ? 2 : 6) {
                if compactPreview {
                    previewHeader
                } else {
                    standardHeader(now: timeline.date)
                    oddsWindowHeader
                }
                coinRows(now: timeline.date)
                if compactPreview && showingAssumptions {
                    previewAssumptions
                }
            }
            .foregroundStyle(cardInk)
            .padding(.horizontal, compactPreview ? 10 : 0)
            .padding(.bottom, compactPreview ? 9 : 0)
            .fleetCard(
                padding: compactPreview ? 0 : (compact ? 10 : 14),
                fill: compactPreview ? FleetTheme.surface : FleetTheme.soloSurface,
                border: compactPreview ? .clear : FleetTheme.comparisonBorder.opacity(0.25),
                borderWidth: 0.5,
                cornerRadius: compactPreview ? 16 : 24
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dashboard.chains")
        }
        .navigationDestination(item: $previewDestination) { destination in
            switch destination {
            case .coins: coinSelectionPage(now: .now)
            case .network: networkPage
            }
        }
        .task(id: LoadIdentity(enabled: canLoad, demo: fleet.isDemo, phase: scenePhase)) {
            guard canLoad, scenePhase == .active else { insights.cancel(); return }
            insights.setDemo(fleet.isDemo)
            while !Task.isCancelled {
                await insights.refresh()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }

    private var previewHeader: some View {
        HStack(spacing: 4) {
            Text("Solo odds")
                .fleetFont(.subheadline, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            oddsWindowControls
            Menu {
                Button(showingAssumptions ? "Hide assumptions" : "Show assumptions", systemImage: "info.circle") {
                    showingAssumptions.toggle()
                }
                .accessibilityIdentifier("dashboard.soloAssumptions")
                Button("Coins to show", systemImage: "line.3.horizontal.decrease") { previewDestination = .coins }
                    .accessibilityIdentifier("dashboard.coinSelection")
                Button("Network", systemImage: "globe") { previewDestination = .network }
                    .accessibilityIdentifier("dashboard.networkDetails")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(cardSecondary)
                    .frame(width: 24, height: 24)
                    .background(FleetTheme.raised, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .fleetDesignedMenu()
            .accessibilityLabel("Solo odds options")
            .accessibilityIdentifier("dashboard.soloOptions")
        }
    }

    private func standardHeader(now: Date) -> some View {
        HStack {
            HStack(spacing: 6) {
                brandMark("light.beacon.max.fill", color: FleetTheme.panelAccent)
                brandMark("cpu.fill", color: FleetTheme.panelPositive)
                Text("Solo odds")
            }
            .fleetFont(.caption, weight: .semibold)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Solo odds")
            Spacer()
            coinSelectionLink(now: now)
            networkLink
            if insights.isLoading { ProgressView().controlSize(.mini) }
        }
    }

    @ViewBuilder
    private func coinRows(now: Date) -> some View {
        if !FleetChainDataPolicy.canDisplay(isDemo: fleet.isDemo,
                                           externalDataEnabled: fleet.preferences.externalDataEnabled) {
            Text("External data is off. Enable it in Fleet preferences to see public chain and pool statistics.")
                .fleetFont(.caption).foregroundStyle(cardSecondary)
        } else {
            let groups = ActiveMiningCoins.groups(devices: fleet.devices, snapshots: fleet.snapshots,
                                                  now: now, isDemo: fleet.isDemo)
            let activeByCoin = Dictionary(uniqueKeysWithValues: groups.map { ($0.coin, $0) })
            let displayedCoins = FleetCoinVisibility.displayed(active: groups.map(\.coin),
                configured: FleetCoinVisibility.configured(devices: fleet.devices, snapshots: fleet.snapshots),
                custom: fleet.preferences.dashboardCoins)
            if displayedCoins.isEmpty {
                Text(fleet.preferences.dashboardCoins == nil
                    ? "No coin detected yet. Choose coins to show, or wait for a miner reading."
                    : (compactPreview ? "No coins selected. Choose them in Solo odds options." : "No coins selected. Choose coins to show above."))
                    .fleetFont(.caption).foregroundStyle(cardSecondary)
                    .accessibilityIdentifier("dashboard.coinsEmpty")
            } else if groups.isEmpty && fleet.preferences.dashboardCoins == nil {
                Text("Active coin unavailable · showing configured coins")
                    .fleetFont(.caption2).foregroundStyle(cardSecondary)
            }

            ForEach(displayedCoins, id: \.self) { coin in
                chain(row: chainRow(coin: coin, group: activeByCoin[coin], now: now))
                if coin != displayedCoins.last {
                    Divider().overlay(cardSecondary.opacity(0.35))
                        .padding(.vertical, compactPreview ? 3 : 0)
                }
            }
            if !compactPreview { standardAssumptions }
        }
    }

    private var standardAssumptions: some View {
        DisclosureGroup(isExpanded: $showingAssumptions) {
            Text(
                fleet.isDemo
                    ? "DEMO · Sample active coins and hashrates, not live."
                    : "Rows with active miners use their current combined hashrate. Other rows are " +
                        "hypothetical comparisons using the fresh fleet rate, not simultaneous mining across rows. " +
                        "Every row assumes that rate runs on that coin continuously for 30 days at " +
                        "unchanged difficulty. Rotation duty fractions are not applied, so these are " +
                        "not your scheduled mining odds. This does not switch pools."
            )
            Text(
                "Probability, not a countdown or promised reward. Accepted shares and past best shares " +
                    "do not make a block due. Coin price is not mining profitability."
            )
        } label: {
            Text(fleet.isDemo ? "DEMO · assumptions" : "Continuous-rate scenarios · assumptions")
        }
        .fleetFont(.caption2).foregroundStyle(FleetTheme.panelSecondary)
        .tint(FleetTheme.panelSecondary)
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("dashboard.soloAssumptions")
    }

    private var previewAssumptions: some View {
        Text((fleet.isDemo ? "Sample readings and prices, not live. " : "") +
             "Block reward is the base subsidy before network allocations, excluding transaction fees. " +
             "Its estimated USD value uses a recent coin price. Neither is a promised miner payout. " +
             "Odds assume steady hashrate and difficulty, without pool rotation. " +
             "Coins without active miners use the fleet rate as a separate comparison.")
            .fleetFont(.caption2)
            .foregroundStyle(cardSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
            .accessibilityIdentifier("dashboard.soloAssumptionsDetails")
    }

    private var networkPage: some View {
        NetworkInsightsView(fleet: fleet, insights: insights)
            .foregroundStyle(FleetTheme.ink)
            .tint(FleetTheme.accent)
    }

    private var networkLink: some View {
        NavigationLink {
            networkPage
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .fleetFont(.caption, weight: .semibold)
                    .frame(width: 20, height: 20)
                Text("Network")
                    .lineLimit(1)
            }
            .fleetFont(.caption, weight: .semibold).frame(minHeight: 44)
        }
        .accessibilityIdentifier("dashboard.networkDetails")
    }

    private func coinSelectionPage(now: Date) -> some View {
        FleetCoinSelectionView(preferences: fleet.preferences, automaticCoins: automaticCoins(now: now))
            .foregroundStyle(FleetTheme.ink)
            .tint(FleetTheme.accent)
    }

    private func coinSelectionLink(now: Date) -> some View {
        NavigationLink {
            coinSelectionPage(now: now)
        } label: {
            Label("Coins", systemImage: "line.3.horizontal.decrease")
                .fleetFont(.caption2, weight: .semibold)
                .foregroundStyle(FleetTheme.panelSecondary)
                .lineLimit(1)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Coins to show")
        .accessibilityHint("Choose which coins appear in solo odds.")
        .accessibilityIdentifier("dashboard.coinSelection")
        .fleetTourTarget("guide.coinSelection")
    }

    @ViewBuilder
    private var oddsWindowHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                oddsWindowSummary
                HStack {
                    Spacer(minLength: 0)
                    oddsWindowControls
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    oddsWindowSummary
                    Spacer(minLength: 0)
                    oddsWindowControls
                }
                VStack(alignment: .leading, spacing: 6) {
                    oddsWindowSummary
                    HStack {
                        Spacer(minLength: 0)
                        oddsWindowControls
                    }
                }
            }
        }
    }

    private var oddsWindowSummary: some View {
        Text("Continuous-rate chance · \(selectedOddsWindow.title)")
            .fleetFont(.caption2)
            .foregroundStyle(FleetTheme.panelSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }

    private var oddsWindowControls: some View {
        HStack(spacing: compactPreview ? 0 : 2) {
            ForEach(SoloOddsWindow.allCases) { window in
                let selected = window == selectedOddsWindow
                Button {
                    selectedOddsWindow = window
                } label: {
                    if compactPreview {
                        Text(window.shortLabel)
                            .fleetFont(.caption2, weight: selected ? .semibold : .medium).monospacedDigit()
                            .foregroundStyle(selected ? cardInk : cardSecondary)
                            .frame(width: 44, height: 24)
                            .background {
                                if selected { Capsule().fill(cardInk.opacity(0.13)).padding(2) }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    } else {
                        Text(window.shortLabel)
                            .fleetFont(.caption2, weight: .semibold).monospacedDigit()
                            .foregroundStyle(selected ? FleetTheme.panelAccent : FleetTheme.panelSecondary)
                            .fleetPillPadding()
                            .frame(minWidth: 44, minHeight: 44)
                            .background(
                                selected ? FleetTheme.panelAccent.opacity(0.16) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityLabel(window.accessibilityLabel)
                .accessibilityIdentifier("dashboard.soloOddsWindow.\(window.rawValue)")
            }
        }
        .padding(compactPreview ? 0 : 4)
        .background {
            if compactPreview {
                Capsule().fill(FleetTheme.raised).frame(height: 24)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(FleetTheme.charcoal)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Solo odds window")
        .accessibilityIdentifier("dashboard.soloOddsWindows")
    }

    private func automaticCoins(now: Date) -> [MiningPoolCoin] {
        FleetCoinVisibility.displayed(
            active: ActiveMiningCoins.groups(devices: fleet.devices, snapshots: fleet.snapshots,
                now: now, isDemo: fleet.isDemo).map(\.coin),
            configured: FleetCoinVisibility.configured(devices: fleet.devices, snapshots: fleet.snapshots),
            custom: nil)
    }

    /// One row's resolved inputs for the active-coin comparison.
    struct ChainRow {
        let coin: MiningPoolCoin
        let usd: Double?
        let difficulty: Double?
        let height: Int?
        let fresh: Bool
        let priceFresh: Bool
        let rate: Double?
        let source: String
        let miners: Int
        let reward: Double?
        var oddsOverride: String?
    }

    private func chain(row: ChainRow) -> some View {
        let coin = row.coin
        let ticker = coin.ticker
        let fresh = row.fresh
        let rate = row.rate
        let difficulty = row.difficulty
        let problem = row.oddsOverride ?? (rate == nil ? "Miner hashrate unavailable" : nil)
        let odds = problem.map { ChainObservation.OddsReading(summary: $0) }
            ?? ChainObservation.oddsReading(hashrateHPS: rate, difficulty: difficulty,
                                            fresh: fresh, duration: selectedOddsWindow.duration)
        let price = row.usd
            .map { $0.formatted(.currency(code: "USD").precision(.significantDigits(3))) } ?? "Unavailable"
        let priceFresh = row.priceFresh
        let usd = row.usd
        let miners = row.miners
        let displayedTicker = compactPreview ? ticker : (insights.coinMarkets[coin]?.ticker ?? ticker)
        let reward = row.reward.map {
            $0.formatted(.number.precision(.fractionLength(0...(coin == .xec ? 2 : 8)))) + " " + ticker
        } ?? "Unavailable"
        let valuePerBlock = ChainObservation.blockValueUSD(reward: row.reward, priceUSD: usd, priceFresh: priceFresh)
            .map(blockValueText)
        return Group {
            if compactPreview {
                compactCoinRow(coin: coin, miners: miners, odds: odds, reward: reward, valuePerBlock: valuePerBlock)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 8) {
                        chainIdentity(coin: coin, ticker: displayedTicker, miners: miners)
                        Text(odds.fullLabel).fleetFont(.caption).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        chainPrice(price, usd: usd, fresh: priceFresh)
                    }
                    VStack(alignment: .leading, spacing: compact ? 2 : 5) {
                        chainIdentity(coin: coin, ticker: displayedTicker, miners: miners)
                        Text(odds.fullLabel).fleetFont(.caption).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                        chainPrice(price, usd: usd, fresh: priceFresh)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            (compactPreview ? "Block reward \(reward). \(valuePerBlock ?? unavailableBlockValue). " : "") +
                "\(displayedTicker), \(miners) active miners, hashrate \(InsightsFormat.hashrate(rate)), " +
                "Full-time \(selectedOddsWindow.title) scenario, rotation not applied. Chance \(odds.fullLabel). " +
                (compactPreview ? "" : "Price \(price)\(priceFresh ? "" : ", stale or unavailable"). ") +
                "Difficulty \(difficulty.map(InsightsFormat.compact) ?? "unavailable"), " +
                "height \(row.height.map(FleetFormat.blockHeight) ?? "unavailable"). " +
                "\(row.source)\(fresh ? "" : ", stale or unavailable")."
        )
        .accessibilityIdentifier("dashboard.chain.\(ticker)")
        .fleetTourTarget("guide.chain.\(ticker)")
    }

    private func compactCoinRow(coin: MiningPoolCoin, miners: Int,
                                odds: ChainObservation.OddsReading, reward: String, valuePerBlock: String?) -> some View {
        let blockReward = VStack(alignment: .leading, spacing: 1) {
            Text("Block reward").fleetFont(.caption2).foregroundStyle(cardSecondary)
            HStack(spacing: 5) {
                CoinGeckoIcon(coin: coin, fallbackTicker: coin.ticker, size: 17)
                Text(reward).fleetFont(.subheadline, weight: .bold).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(valuePerBlock ?? unavailableBlockValue).fleetFont(.caption, weight: .medium).monospacedDigit()
                .foregroundStyle(valuePerBlock == nil ? cardSecondary : FleetTheme.accent)
        }
        let chance = VStack(alignment: .leading, spacing: 1) {
            Text("\(selectedOddsWindow.title) chance").fleetFont(.caption2).foregroundStyle(cardSecondary)
            Text(odds.compactLabel).fleetFont(.subheadline, weight: .semibold).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if miners == 0 || odds.reciprocal != nil {
                Text(miners == 0 ? "Fleet scenario" : odds.summary)
                    .fleetFont(.caption).monospacedDigit().foregroundStyle(cardSecondary)
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                blockReward.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                chance.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 6) {
                blockReward
                chance
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unavailableBlockValue: String {
        insights.isLoading && !fleet.isDemo ? "Checking USD value…" : "USD value unavailable"
    }

    private func blockValueText(_ value: Double) -> String {
        let currency = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        if value > 0 && value < 0.01 {
            return "Less than \(0.01.formatted(currency)) per block"
        }
        let amount = value.formatted(currency.precision(.fractionLength(value >= 1_000 || value == 0 ? 0 : 2)))
        return "≈ \(amount) per block"
    }

    private func chainIdentity(coin: MiningPoolCoin, ticker: String, miners: Int) -> some View {
        HStack(spacing: 8) {
            CoinGeckoIcon(coin: coin, fallbackTicker: ticker, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(ticker).fleetFont(.caption, weight: .bold)
                Text(miners > 0 ? "\(miners) miner\(miners == 1 ? "" : "s")" : "Full fleet")
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.panelInk)
            }
            .frame(minWidth: 30, alignment: .leading)
        }
    }

    private func chainPrice(_ price: String, usd: Double?, fresh: Bool) -> some View {
        Text(price + (usd != nil && !fresh ? " · stale" : ""))
            .fleetFont(.caption2)
            .foregroundStyle(FleetTheme.panelSecondary)
    }

    private func brandMark(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .fleetFont(.caption, weight: .semibold)
            .foregroundStyle(color)
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }

    private struct LoadIdentity: Equatable {
        let enabled: Bool
        let demo: Bool
        let phase: ScenePhase
    }
}

struct FleetCoinSelectionView: View {
    @Bindable var preferences: FleetPreferences
    let automaticCoins: [MiningPoolCoin]

    var body: some View {
        FleetSettingsForm {
            FleetSettingsSection(footer: "Show only actively mined coins, one row per coin. If active readings are unavailable, use configured coins. Miners on the same coin are combined.") {
                FleetSettingsRow {
                Toggle("Automatic selection", isOn: Binding(
                    get: { preferences.dashboardCoins == nil },
                    set: { preferences.dashboardCoins = $0 ? nil : Set(automaticCoins) }))
                    .accessibilityIdentifier("coinSelection.automatic")
                }
            }
            if preferences.dashboardCoins != nil {
                FleetSettingsSection("Choose visible coins") {
                    ForEach(FleetCoinVisibility.order, id: \.self) { coin in
                        FleetSettingsRow {
                        Toggle(coin.ticker, isOn: Binding(
                            get: { preferences.dashboardCoins?.contains(coin) == true },
                            set: { enabled in
                                var selected = preferences.dashboardCoins ?? []
                                if enabled { selected.insert(coin) } else { selected.remove(coin) }
                                preferences.dashboardCoins = selected
                            }))
                            .accessibilityIdentifier("coinSelection.\(coin.ticker)")
                            .fleetTourTarget("guide.coin.\(coin.ticker)")
                        }
                    }
                    FleetSettingsRow {
                    Button("Select all") { preferences.dashboardCoins = Set(FleetCoinVisibility.order) }
                        .accessibilityIdentifier("coinSelection.all")
                    }
                    FleetSettingsRow(showsSeparator: false) {
                    Button("Clear selection") { preferences.dashboardCoins = [] }
                        .accessibilityIdentifier("coinSelection.none")
                    }
                }
            }
            FleetSettingsSection(footer: FleetDeviceCopy.current.coinSelectionFooter) {
            }
        }
        .fleetAppNavigation { $0.navigationTitle("Coins to show") }
        .navigationBarTitleDisplayMode(.inline)
    }
}
