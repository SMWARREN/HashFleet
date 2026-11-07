import SwiftUI
import HashFleetCore

/// Freshness is source-specific. A successful fetch of an old provider cache is still old data.
enum ChainObservation {
    static func freshFleetRateHPS(devices: [MinerDevice], snapshots: [UUID: MinerSnapshot], now: Date, isDemo: Bool) -> Double? {
        var total: Double = 0
        guard !devices.isEmpty else { return nil }
        for device in devices {
            guard let snapshot = snapshots[device.id], !snapshot.isCached,
                snapshot.error == nil, let updated = snapshot.updatedAt, let info = snapshot.info,
                isDemo || (-60...FleetGlance.freshnessInterval * 3).contains(now.timeIntervalSince(updated)),
                let gh = FleetFormat.sensor(info, keys: "hashRate", "hashrate"), gh.isFinite, gh >= 0
            else { return nil }
            total += gh * 1e9
        }
        return total.isFinite ? total : nil
    }

    static func networkProblem<Value>(
        _ result: MiningDataResult<Value>?, difficulty: Double?, now: Date
    ) -> String? {
        guard let result else { return "Loading network data" }
        if let error = result.error {
            if case .http(let code) = error { return "Network source unavailable (HTTP \(code))" }
            return "Network source unavailable"
        }
        guard result.value != nil, let difficulty, difficulty.isFinite, difficulty > 0 else {
            return "Network difficulty not reported"
        }
        guard isFresh(result, now: now) else { return "Network data is stale" }
        return nil
    }

    static func isFresh<Value>(_ result: MiningDataResult<Value>?, now: Date) -> Bool {
        guard let result, result.value != nil, result.error == nil else { return false }
        return [result.fetchedAt, result.sourceTimestamp].compactMap { $0 }.allSatisfy {
            let age = now.timeIntervalSince($0)
            return age >= -60 && age <= 300
        }
    }

    static func nextHeight(_ tip: Int?) -> Int? {
        guard let tip, tip >= 0, tip < Int.max else { return nil }
        return tip + 1
    }

    static func chance(
        hashrateHPS: Double?,
        difficulty: Double?,
        fresh: Bool,
        duration: TimeInterval = 30 * 86400
    ) -> String {
        guard fresh, let hashrateHPS, let difficulty,
            duration > 0, duration.isFinite,
            let estimate = SoloMiningMath.estimate(
                hashrateHPS: hashrateHPS,
                difficulty: difficulty,
                duration: duration
            )
        else {
            return "Needs fresh readings"
        }
        let probability = estimate.probabilityAtLeastOne
        let percent = (probability * 100).formatted(.number.precision(.significantDigits(3))) + "%"
        guard probability > 0 else { return percent }
        return percent + " · 1 in " + (1 / probability).formatted(.number.precision(.fractionLength(0)))
    }
}

enum SoloOddsWindow: String, CaseIterable, Identifiable {
    case day
    case month
    case year

    var id: Self { self }

    var duration: TimeInterval {
        switch self {
        case .day: 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        case .year: 365 * 24 * 60 * 60
        }
    }

    var shortLabel: String {
        switch self {
        case .day: "1d"
        case .month: "1mo"
        case .year: "1y"
        }
    }

    var title: String {
        switch self {
        case .day: "1-day"
        case .month: "30-day"
        case .year: "1-year"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .day: "1 day"
        case .month: "1 month"
        case .year: "1 year"
        }
    }
}

/// Groups only fresh, online miners whose active slot explicitly identifies a coin.
/// Missing rates make that group's estimate unavailable rather than silently undercounting it.
enum ActiveMiningCoins {
    struct Group: Identifiable, Equatable {
        var id: MiningPoolCoin { coin }
        let coin: MiningPoolCoin
        var miners: Int = 0
        var rateHPS: Double? = 0
    }

    static func groups(
        devices: [MinerDevice],
        snapshots: [UUID: MinerSnapshot],
        now: Date,
        isDemo: Bool
    ) -> [Group] {
        var groups: [MiningPoolCoin: Group] = [:]
        for device in devices {
            guard let snapshot = snapshots[device.id], snapshot.error == nil, !snapshot.isCached,
                let info = snapshot.info, let updated = snapshot.updatedAt
            else { continue }
            let age = now.timeIntervalSince(updated)
            guard isDemo || (age >= -60 && age <= FleetGlance.freshnessInterval * 3) else { continue }
            let active = ConfiguredMiningPool.resolve(info: info).filter { $0.isActive == true }
            guard active.count == 1, let coin = active.first?.coin else { continue }
            var group = groups[coin] ?? Group(coin: coin)
            group.miners += 1
            if let gh = FleetFormat.sensor(info, keys: "hashRate", "hashrate"),
                gh.isFinite, gh >= 0, let prior = group.rateHPS {
                let total = prior + gh * 1e9
                group.rateHPS = total.isFinite ? total : nil
            } else {
                group.rateHPS = nil
            }
            groups[coin] = group
        }
        return MiningPoolCoin.allCases.compactMap { groups[$0] }
    }
}

/// Active coins win. Configured coins are only a display fallback, never evidence of active mining.
enum FleetCoinVisibility {
    static let order: [MiningPoolCoin] = [.btc, .bch, .xec, .dgb, .bc2, .bch2]

    static func displayed(active: [MiningPoolCoin], configured: [MiningPoolCoin], custom: Set<MiningPoolCoin>?) -> [MiningPoolCoin] {
        let visible = custom ?? Set(active.isEmpty ? configured : active)
        return order.filter(visible.contains)
    }

    static func configured(devices: [MinerDevice], snapshots: [UUID: MinerSnapshot]) -> [MiningPoolCoin] {
        let coins = devices.flatMap { device in
            snapshots[device.id]?.info.map { ConfiguredMiningPool.resolve(info: $0).compactMap(\.coin) } ?? []
        }
        return displayed(active: [], configured: coins, custom: nil)
    }
}

enum FleetChainDataPolicy {
    /// Sample fixtures are local. Disabling public data must not erase the demo or enable
    /// any real fetch. Non-demo pages continue to require the explicit preference.
    static func canDisplay(isDemo: Bool, externalDataEnabled: Bool) -> Bool {
        isDemo || externalDataEnabled
    }
}

struct FleetChainCard: View {
    let fleet: FleetStore
    let insights: MiningInsightsStore
    var compact: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingAssumptions = false
    @State private var selectedOddsWindow: SoloOddsWindow = .month

    private var canLoad: Bool {
        FleetChainDataPolicy.canDisplay(isDemo: fleet.isDemo,
                                       externalDataEnabled: fleet.preferences.externalDataEnabled)
            && !fleet.devices.isEmpty && (fleet.isDemo || fleet.onlineCount > 0)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(alignment: .leading, spacing: compact ? 8 : 6) {
                HStack(alignment: .center) {
                    HStack(alignment: .center, spacing: 6) {
                        brandMark("light.beacon.max.fill", color: FleetTheme.panelAccent)
                        brandMark("cpu.fill", color: FleetTheme.panelPositive)
                        Text("Solo odds")
                    }
                    .fleetFont(.caption, weight: .semibold)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Solo odds")
                    Spacer()
                    coinSelectionLink(now: timeline.date)
                    NavigationLink {
                        NetworkInsightsView(fleet: fleet, insights: insights)
                            .foregroundStyle(FleetTheme.ink)
                            .tint(FleetTheme.accent)
                    } label: {
                        HStack(alignment: .center, spacing: 5) {
                            Image(systemName: "globe")
                                .fleetFont(.caption, weight: .semibold)
                                .frame(width: 20, height: 20)
                            Text("Network")
                                .lineLimit(1)
                        }
                        .fleetFont(.caption, weight: .semibold).frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("dashboard.networkDetails")
                    if insights.isLoading { ProgressView().controlSize(.mini) }
                }
                oddsWindowHeader
                if !FleetChainDataPolicy.canDisplay(isDemo: fleet.isDemo,
                                                   externalDataEnabled: fleet.preferences.externalDataEnabled) {
                    Text(
                        "External data is off. Enable it in Fleet preferences to see public chain and pool statistics."
                    )
                    .fleetFont(.caption).foregroundStyle(FleetTheme.panelSecondary)
                } else {
                    let groups = ActiveMiningCoins.groups(
                        devices: fleet.devices,
                        snapshots: fleet.snapshots,
                        now: timeline.date,
                        isDemo: fleet.isDemo
                    )
                    let activeByCoin = Dictionary(uniqueKeysWithValues: groups.map { ($0.coin, $0) })
                    let displayedCoins = FleetCoinVisibility.displayed(active: groups.map(\.coin),
                        configured: FleetCoinVisibility.configured(devices: fleet.devices, snapshots: fleet.snapshots),
                        custom: fleet.preferences.dashboardCoins)
                    if displayedCoins.isEmpty {
                        Text(fleet.preferences.dashboardCoins == nil
                            ? "No coin detected yet. Choose coins to show, or wait for a miner reading."
                            : "No coins selected. Choose coins to show above.")
                            .fleetFont(.caption).foregroundStyle(FleetTheme.panelSecondary)
                            .accessibilityIdentifier("dashboard.coinsEmpty")
                    } else if groups.isEmpty && fleet.preferences.dashboardCoins == nil {
                        Text("Active coin unavailable · showing configured coins")
                            .fleetFont(.caption2).foregroundStyle(FleetTheme.panelSecondary)
                    }

                    ForEach(displayedCoins, id: \.self) { coin in
                        chain(row: chainRow(coin: coin, group: activeByCoin[coin], now: timeline.date))
                        if coin != displayedCoins.last {
                            Divider().overlay(FleetTheme.panelSecondary.opacity(0.35))
                        }
                    }
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
            }
            .foregroundStyle(FleetTheme.panelInk)
            .fleetCard(
                padding: compact ? 12 : 14,
                fill: FleetTheme.soloSurface,
                border: FleetTheme.comparisonBorder.opacity(0.25),
                borderWidth: 0.5
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dashboard.chains")
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

    private func coinSelectionLink(now: Date) -> some View {
        NavigationLink {
            FleetCoinSelectionView(
                preferences: fleet.preferences,
                automaticCoins: automaticCoins(now: now)
            )
            .foregroundStyle(FleetTheme.ink)
            .tint(FleetTheme.accent)
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
        HStack(spacing: 2) {
            ForEach(SoloOddsWindow.allCases) { window in
                let selected = window == selectedOddsWindow
                Button {
                    selectedOddsWindow = window
                } label: {
                    Text(window.shortLabel)
                        .fleetFont(.caption2, weight: .semibold).monospacedDigit()
                        .foregroundStyle(selected ? FleetTheme.panelAccent : FleetTheme.panelSecondary)
                        .fleetPillPadding()
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            selected ? FleetTheme.panelAccent.opacity(0.16) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityLabel(window.accessibilityLabel)
                .accessibilityIdentifier("dashboard.soloOddsWindow.\(window.rawValue)")
            }
        }
        .padding(4)
        // Solo odds is intentionally a dark comparison panel in both appearances. Keep its
        // segmented control on a distinct dark surface instead of introducing a light slab
        // when the rest of the app switches to light mode.
        .background(FleetTheme.charcoal, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        var oddsOverride: String?
    }

    private func chain(row: ChainRow) -> some View {
        let coin = row.coin
        let ticker = coin.ticker
        let fresh = row.fresh
        let rate = row.rate
        let difficulty = row.difficulty
        let odds = row.oddsOverride
            ?? (rate == nil ? "Miner hashrate unavailable"
                : ChainObservation.chance(
                    hashrateHPS: rate,
                    difficulty: difficulty,
                    fresh: fresh,
                    duration: selectedOddsWindow.duration
                ))
        let price = row.usd
            .map { $0.formatted(.currency(code: "USD").precision(.significantDigits(3))) } ?? "Unavailable"
        let priceFresh = row.priceFresh
        let usd = row.usd
        let miners = row.miners
        let market = insights.coinMarkets[coin]
        let displayedTicker = market?.ticker ?? ticker
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                chainIdentity(coin: coin, ticker: displayedTicker, miners: miners)
                Text(odds).fleetFont(.caption).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                chainPrice(price, usd: usd, fresh: priceFresh)
            }
            VStack(alignment: .leading, spacing: compact ? 2 : 5) {
                chainIdentity(coin: coin, ticker: displayedTicker, miners: miners)
                Text(odds).fleetFont(.caption).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                chainPrice(price, usd: usd, fresh: priceFresh)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(displayedTicker), \(miners) active miners, hashrate \(InsightsFormat.hashrate(rate)), " +
                "Full-time \(selectedOddsWindow.title) scenario, rotation not applied. Chance \(odds). Price \(price)\(priceFresh ? "" : ", stale or unavailable"). " +
                "Difficulty \(difficulty.map(InsightsFormat.compact) ?? "unavailable"), " +
                "height \(row.height.map(FleetFormat.blockHeight) ?? "unavailable"). " +
                "\(row.source)\(fresh ? "" : ", stale or unavailable")."
        )
        .accessibilityIdentifier("dashboard.chain.\(ticker)")
        .fleetTourTarget("guide.chain.\(ticker)")
    }

    private func chainIdentity(coin: MiningPoolCoin, ticker: String, miners: Int) -> some View {
        HStack(spacing: 8) {
            CoinGeckoIcon(coin: coin, fallbackTicker: ticker).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(ticker).fleetFont(.caption, weight: .bold)
                Text(miners > 0 ? "\(miners) miner\(miners == 1 ? "" : "s")" : "Full fleet")
                    .fleetFont(.caption2)
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
