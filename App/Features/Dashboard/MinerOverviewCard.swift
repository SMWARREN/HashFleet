import Foundation
import SwiftUI
import HashFleetCore

struct MinerOverviewCard: View {
    let device: MinerDevice
    let snapshot: MinerSnapshot?
    let isDemo: Bool
    var compact = false
    var showsStatus = true
    var isLive = false
    var liveConnectionError: String?
    var marketData: [MiningPoolCoin: CoinGeckoMarket] = [:]
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var statusNoticeSilenced: Bool

    init(
        device: MinerDevice,
        snapshot: MinerSnapshot?,
        isDemo: Bool,
        compact: Bool = false,
        isLive: Bool = false,
        liveConnectionError: String? = nil,
        marketData: [MiningPoolCoin: CoinGeckoMarket] = [:]
    ) {
        self.device = device
        self.snapshot = snapshot
        self.isDemo = isDemo
        self.compact = compact
        self.isLive = isLive
        self.liveConnectionError = liveConnectionError
        self.marketData = marketData
        _statusNoticeSilenced = State(initialValue: MinerNoticeSnoozeStore.isSnoozed(for: device.id))
    }

    private var isInitialLoading: Bool {
        presentationState == .loading
    }

    var presentationState: FleetMinerPresentationState {
        Self.resolvePresentation(snapshot: snapshot, isDemo: isDemo, isLive: isLive)
    }

    static func resolvePresentation(snapshot: MinerSnapshot?, isDemo: Bool, isLive: Bool) -> FleetMinerPresentationState {
        if snapshot?.info == nil, snapshot?.isReconnecting == true { return .loading }
        if MinerLoadingPolicy.shouldShowSkeleton(info: snapshot?.info, error: snapshot?.error, isDemo: isDemo) { return .loading }
        return FleetMinerPresentationState.resolve(
            isDemo: isDemo,
            hasInfo: snapshot?.info != nil,
            hasError: snapshot?.error != nil,
            isLive: isLive,
            isReconnecting: snapshot?.isReconnecting == true
        )
    }

    var status: String {
        presentationState.title
    }

    var statusColor: Color {
        presentationState.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            hashrateRow
            if isInitialLoading {
                skeletonSecondaryRow
            } else if compact || bestShare != nil || bestSessionShare != nil {
                secondaryMetricsRow
            }
            if snapshot?.isReconnecting != true, snapshot?.error == nil, let info = snapshot?.info,
                let alerts = MinerReportedAlerts(info: info), !alerts.isEmpty,
                !statusNoticeSilenced {
                statusNoticeRow(info)
                    .transition(reduceMotion ? .identity :
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.85).combined(with: .opacity)
                        )
                    )
            }
            if !compact {
                if let info = snapshot?.info {
                    let layout =
                        dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(spacing: 18))
                    layout {
                        smallMetric(
                            "Temperature",
                            value: shortReading(FleetFormat.sensor(info, keys: "temp"), unit: "°C"),
                            symbol: "thermometer.medium"
                        )
                        smallMetric(
                            "Power",
                            value: shortReading(FleetFormat.sensor(info, keys: "power"), unit: "W", decimals: 1),
                            symbol: "bolt"
                        )
                        smallMetric(
                            "Fan",
                            value: shortReading(FleetFormat.sensor(info, keys: "fanspeed", "fanSpeed"), unit: "%"),
                            symbol: "fan"
                        )
                    }
                } else if isInitialLoading {
                    skeletonMetricsRow
                }
            }
            if let error = snapshot?.error, !isDemo, snapshot?.isReconnecting != true {
                Label("Connection error: \(error)", systemImage: "wifi.exclamationmark")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.warning)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("dashboard.miner.error.\(device.id.uuidString)")
            } else if liveConnectionError != nil, !isDemo, snapshot?.isReconnecting != true {
                Label("Live monitoring unavailable · using HTTP refresh", systemImage: "wifi.exclamationmark")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("dashboard.miner.liveError.\(device.id.uuidString)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open miner details and controls")
        .task(id: statusNoticeSilenced) {
            statusNoticeSilenced = MinerNoticeSnoozeStore.isSnoozed(for: device.id)
            while !Task.isCancelled {
                guard let until = MinerNoticeSnoozeStore.snoozedUntil(for: device.id) else { return }
                let remaining = until.timeIntervalSinceNow
                guard remaining > 0 else {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2)) {
                        statusNoticeSilenced = false
                    }
                    return
                }
                let sleepNanoseconds = UInt64(min(remaining, 60) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
                if !MinerNoticeSnoozeStore.isSnoozed(for: device.id) {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2)) {
                        statusNoticeSilenced = false
                    }
                    return
                }
            }
        }
    }

    private func statusNoticeRow(_ info: MinerInfo) -> some View {
        let title =
            info.raw["isUsingFallbackStratum"]?.boolValue == true
            ? "Mining fallback · see details"
            : (info.raw["miningPaused"]?.boolValue == true
                ? "Mining paused · see details" : "Miner status notice · see details")
        return Label(title, systemImage: "exclamationmark.triangle")
            .fleetFont(.caption)
            .foregroundStyle(FleetTheme.warning)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                identity
                Spacer(minLength: 8)
                if showsStatus {
                    statusCluster
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    identity
                    Spacer(minLength: 0)
                }
                if showsStatus {
                    statusCluster
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Status badge, plus a Hot pill when the chip is at or above the warning temperature.
    /// Offline is already shown by the badge and the connection error line, so no extra pill.
    private var statusCluster: some View {
        HStack(spacing: 6) {
            if let hot = MinerSidebarAttention.hotOnly(
                state: presentationState,
                temperature: snapshot?.info.flatMap { FleetFormat.sensor($0, keys: "temp") }
            ) {
                FleetStatusPill(text: hot.text, systemImage: hot.systemImage, tint: MinerSidebarAttention.hotTint)
                    .accessibilityLabel(hot.accessibilityLabel)
                    .accessibilityIdentifier("dashboard.card.hot.\(device.id.uuidString)")
            }
            statusBadge
                .accessibilityIdentifier("dashboard.card.status.\(device.id.uuidString)")
        }
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 7) {
                    Text(device.name)
                        .fleetFont(.headline)
                        .foregroundStyle(FleetTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let coin = MinerMiningContext.resolve(info: snapshot?.info).pool?.coin {
                        CoinGeckoIcon(
                            coin: coin,
                            fallbackTicker: marketData[coin]?.ticker ?? coin.ticker,
                            size: 22
                        )
                        .frame(width: 22, height: 22)
                        .accessibilityLabel("\(marketData[coin]?.ticker ?? coin.ticker) coin")
                        .accessibilityIdentifier("dashboard.miner.coin.\(device.id.uuidString)")
                    }
                }
                if !compact {
                    if isInitialLoading {
                        FleetLoadingSkeleton(width: 72, height: 12, cornerRadius: 3, label: "Loading ASIC model")
                    } else {
                        Text(snapshot?.info?.asicModel ?? "ASIC not reported")
                            .fleetFont(.caption2, design: .monospaced)
                            .foregroundStyle(FleetTheme.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    private var hashrateRow: some View {
        HStack(alignment: .firstTextBaseline) {
            reading
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.hashrateRow.\(device.id.uuidString)")
    }

    @ViewBuilder
    private var secondaryMetricsRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            if compact { powerSummary }
            bestSummary
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.bestRow.\(device.id.uuidString)")
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isInitialLoading {
                FleetLoadingSkeleton(width: 96, height: 26, cornerRadius: 4, label: "Loading hashrate")
                Text("Waiting for first reading")
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
            } else {
                let value =
                    snapshot?.info.flatMap { FleetFormat.sensor($0, keys: "hashRate", "hashrate") }.map {
                        FleetFormat.hashrate($0)
                    } ?? "Not reported"
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value)
                        .fleetFont(.title2, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(FleetTheme.ink)
                        .fleetHeadlineNumericUpdate(value, reduceMotion: reduceMotion)
                    if let rate = snapshot?.info.flatMap({ FleetFormat.sensor($0, keys: "hashRate", "hashrate") }) {
                        Text(FleetFormat.hashrateUnit(rate))
                            .fleetFont(.caption, design: .monospaced)
                            .foregroundStyle(FleetTheme.secondary)
                    }
                }
                if snapshot?.error != nil || snapshot?.isReconnecting == true, snapshot?.info != nil, !isDemo {
                    Label("Last known reading", systemImage: "clock.arrow.circlepath")
                        .fleetFont(.caption2, weight: .medium)
                        .foregroundStyle(FleetTheme.secondary)
                        .fleetPillPadding()
                        .background(FleetTheme.secondary.opacity(0.10), in: Capsule())
                        .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func shortReading(_ value: Double?, unit: String, decimals: Int = 0) -> String {
        value.map { "\(FleetFormat.number($0, decimals: decimals))\(unit)" } ?? "N/A"
    }
}

/// The small amount of mining context that belongs on a fleet card.
///
/// This intentionally uses only the miner-reported pool slots. It never displays a pool URL,
/// worker name, payout address, or a guessed coin when firmware did not identify one.
struct MinerMiningContext: Equatable, Hashable, Identifiable, Sendable {
    let pool: ConfiguredMiningPool?

    static func resolve(info: MinerInfo?) -> MinerMiningContext {
        guard let info else { return MinerMiningContext(pool: nil) }
        let pools = ConfiguredMiningPool.resolve(info: info)
        if info.raw["activePoolIndex"] != nil {
            return MinerMiningContext(pool: pools.first(where: { $0.isActive == true }))
        }
        let selected =
            pools.first(where: { $0.isActive == true })
            ?? pools.first(where: { $0.role.localizedCaseInsensitiveContains("primary") })
            ?? pools.first
        return MinerMiningContext(pool: selected)
    }

    var headline: String {
        guard pool != nil else { return "Pool not reported" }
        return "\(coinLabel) · \(providerLabel)"
    }

    var coinLabel: String {
        pool?.coin?.rawValue.uppercased() ?? "Coin unknown"
    }

    var providerLabel: String {
        if let name = pool?.providerName { return name }
        switch pool?.provider {
        case .ckpool: return "CKPool"
        case .soloFury: return "SoloFury"
        case .soloPool: return "SoloPool"
        case nil: return pool == nil ? "Pool not reported" : "Pool configured"
        }
    }

    /// Activity is shown only when the firmware gave us an explicit active/fallback flag.
    var routeLabel: String {
        guard let pool else { return "Awaiting miner reading" }
        let role: String
        if pool.role.localizedCaseInsensitiveContains("primary") {
            role = "Primary"
        } else if pool.role.localizedCaseInsensitiveContains("fallback") {
            role = "Fallback"
        } else {
            role = pool.role
        }
        switch pool.isActive {
        case .some(true): return "Active · \(role)"
        case .some(false): return "Standby · \(role)"
        case nil: return role
        }
    }

    var sourceLabel: String {
        pool == nil ? "Not reported" : "Miner reported"
    }

    var symbol: String {
        guard let pool else { return "questionmark.circle" }
        switch pool.provider {
        case .ckpool: return "server.rack"
        case .soloFury: return "flame.fill"
        case .soloPool: return "bitcoinsign.circle.fill"
        case nil:
            switch pool.coin {
            case .btc, .bch, .bc2, .bch2, .dgb: return "bitcoinsign.circle.fill"
            case .xec: return "circle.grid.2x2.fill"
            case nil: return "network"
            }
        }
    }

    var id: String {
        "\(headline)|\(routeLabel)"
    }
}

struct MinerMiningContextRow: View {
    let context: MinerMiningContext
    let isLastKnown: Bool
    let market: CoinGeckoMarket?
    let identifier: String?

    init(
        context: MinerMiningContext,
        isLastKnown: Bool = false,
        market: CoinGeckoMarket? = nil,
        identifier: String? = nil
    ) {
        self.context = context
        self.isLastKnown = isLastKnown
        self.market = market
        self.identifier = identifier
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(context.providerLabel)
                .fleetFont(.caption, weight: .semibold)
                .foregroundStyle(context.pool == nil ? FleetTheme.secondary : FleetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let coin = context.pool?.coin {
                CoinGeckoIcon(coin: coin, fallbackTicker: market?.ticker ?? coin.ticker, size: 24)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mining context, \(context.headline), \(context.routeLabel), \(sourceLabel)")
        .accessibilityIdentifier(identifier ?? "")
    }

    private var sourceLabel: String {
        isLastKnown ? "Last known" : context.sourceLabel
    }
}
