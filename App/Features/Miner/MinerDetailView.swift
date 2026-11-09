import SwiftUI
import HashFleetCore

/// The per-device workspace. Opening this screen never changes miner settings.
///
/// Layout intent: the readings a person opened the miner for come first and stay within the initial
/// viewport on a phone. Explanations, identifiers and every existing tool are still present, moved
/// into collapsed sections rather than deleted, so nothing that was reachable before became
/// unreachable and no safety wording was dropped.
struct MinerDetailView: View {
    @Environment(\.fleetGuidedDemo) private var guidedDemo
    let device: MinerDevice
    @Bindable var store: FleetStore
    // No @Environment(\.dismiss) here. Its value changes whenever this page's stack pushes or pops a
    // child, so reading it in this large body re-rendered the whole detail page in a loop with the
    // pushed child (Raw API froze the Mac app at 100% CPU, 2026-11-06). Removal reads it in
    // MinerRemoveFromFleetButton only.
    /// Shared public-data store, passed through to settings. Optional so existing call sites keep
    /// working and so this screen never creates its own network-capable store.
    var insights: MiningInsightsStore?
    /// Non-fatal live-stream failure while the last HTTP snapshot remains usable.
    var liveConnectionError: String?
    /// True when this detail view is backed by the miner's foreground WebSocket stream.
    var isLive: Bool = false
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    var usesCompactHorizontalLayout: Bool {
        #if os(macOS)
        false
        #else
        horizontalSizeClass == .compact
        #endif
    }
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ScaledMetric(relativeTo: .caption) var coolingComparisonLabelWidth: CGFloat = 96
    @ScaledMetric(relativeTo: .title3) var detailIconColumnWidth: CGFloat = 30
    @State var showsCooling = true
    @State var showsTuning = true
    @State var showsAdvancedTools = false
    @State var showsIdentity = false
    @State var showsPools = false
    @State var isNoticeSilenced = false
    @State var showsRemoveConfirmation = false
    @State var showsRenamePrompt = false
    @State var renameDraft = ""
    @State var renameError: String?
    #if !os(macOS)
    @State var tuningSessionRoute: MinerDevice?
    #endif
    @AppStorage("detail.responsiveColumnLimit") var macDetailColumns = 0
    /// Measured content width. Drives the adaptive arrangement on iPad and Mac windows.
    @State var contentWidth: CGFloat = 0

    /// Observes only this miner, so other miners' live frames do not rebuild this page.
    var snapshot: MinerSnapshot? { store.snapshot(for: device.id) }
    var info: MinerInfo? { snapshot?.info }
    var currentDevice: MinerDevice { store.devices.first(where: { $0.id == device.id }) ?? device }
    var isXMRig: Bool { currentDevice.kind == .xmrig }

    var miningCoin: MiningPoolCoin? {
        MinerMiningContext.resolve(info: info).pool?.coin
    }

    var miningMarket: CoinGeckoMarket? {
        miningCoin.flatMap { insights?.coinMarkets[$0] }
    }

    var navigationIdentity: MinerNavigationIdentity {
        // One pool resolution per body pass (previously three: here, miningCoin, miningMarket).
        let context = MinerMiningContext.resolve(info: info)
        let coin = context.pool?.coin
        return MinerNavigationIdentity(
            deviceName: currentDevice.name,
            poolName: context.pool == nil ? nil : context.providerLabel,
            coin: coin,
            market: coin.flatMap { insights?.coinMarkets[$0] }
        )
    }

    var body: some View {
        if FleetReleaseFeatures.includes(currentDevice.kind) {
            releasedContent
        } else {
            ContentUnavailableView(
                "Miner unavailable in this release",
                systemImage: "cpu",
                description: Text("Your saved configuration is retained for a future release.")
            )
        }
    }

    /// Retained implementation is testable independently of the shipping release gate.
    var releasedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusStrip
                    .fleetStaggeredEntrance(index: 0, reduceMotion: reduceMotion)
                if FleetLayout.isMac, !dynamicTypeSize.isAccessibilitySize {
                    detailColumnControl
                }
                if !store.isDemo, snapshot?.info != nil || snapshot?.error != nil,
                   !MinerWriteAvailability.allows(snapshot) {
                    MinerOfflineSettingsNotice(snapshot: snapshot)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
                        .fleetStaggeredEntrance(index: 1, reduceMotion: reduceMotion)
                }
                if store.isPoolIconDemo {
                    MinerDetailSection { poolIconDemoControls }
                        .fleetStaggeredEntrance(index: 1, reduceMotion: reduceMotion)
                }
                if let notice = store.firmwareUpdates.notice(for: device.id),
                   store.firmwareUpdates.shouldShow(notice, for: device.id) {
                    firmwareUpdateSection(notice)
                        .fleetStaggeredEntrance(index: 2, reduceMotion: reduceMotion)
                }
                if let error = snapshot?.error, snapshot?.isReconnecting != true {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
                        .accessibilityIdentifier("detail.telemetryError")
                        .fleetStaggeredEntrance(index: 2, reduceMotion: reduceMotion)
                }
                if snapshot?.isReconnecting != true, snapshot?.error == nil, liveConnectionError != nil {
                    Label("Live monitoring unavailable · using HTTP refresh", systemImage: "wifi.exclamationmark")
                        .fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fleetCard(padding: FleetSurfaceSpacing.cardInset, fill: FleetTheme.warning.opacity(0.10))
                        .accessibilityIdentifier("detail.liveError")
                        .fleetStaggeredEntrance(index: 2, reduceMotion: reduceMotion)
                }
                if snapshot?.isReconnecting != true, let info, let alerts = MinerReportedAlerts(info: info), !alerts.isEmpty {
                    faultBanner(alerts)
                        .fleetStaggeredEntrance(index: 3, reduceMotion: reduceMotion)
                }
                if let info {
                    MinerDetailSection { telemetrySections(info) }
                        .fleetStaggeredEntrance(index: 3, reduceMotion: reduceMotion)
                } else {
                    if snapshot?.isReconnecting == true || MinerLoadingPolicy.shouldShowSkeleton(info: nil, error: snapshot?.error, isDemo: store.isDemo) {
                        VStack(alignment: .leading, spacing: 16) {
                            BitsySays(
                                mood: .thinking,
                                message: "Hold tight. I'm fetching this miner's readings.",
                                size: 64
                            )
                            .accessibilityIdentifier("detail.bitsyLoading")
                            Text("Loading miner readings…")
                                .fleetFont(.caption).foregroundStyle(FleetTheme.hashrateSecondary)
                            FleetLoadingSkeleton(width: 150, height: 44, label: "Loading hashrate",
                                                 tint: FleetTheme.hashrateSkeleton)
                            FleetLoadingSkeleton(height: 16, label: "Loading shares and uptime",
                                                 tint: FleetTheme.hashrateSkeleton)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fleetCard(padding: 16, fill: FleetTheme.hashrateSurface)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("detail.loading")
                        .fleetStaggeredEntrance(index: 3, reduceMotion: reduceMotion)
                    } else {
                        VStack(spacing: 12) {
                            BitsySays(
                                mood: .worried,
                                message: "I can't reach this miner right now. Pull to refresh and I'll try again.",
                                size: 64
                            )
                            .accessibilityIdentifier("detail.bitsyUnavailable")
                            ContentUnavailableView(
                                "Telemetry unavailable",
                                systemImage: "antenna.radiowaves.left.and.right",
                                description: Text("Pull to refresh. Read operations never change miner settings.")
                            )
                        }
                        .fleetStaggeredEntrance(index: 3, reduceMotion: reduceMotion)
                    }
                    if isXMRig {
                        xmrigControlLink
                            .fleetStaggeredEntrance(index: 4, reduceMotion: reduceMotion)
                    } else {
                        quickControls
                            .fleetStaggeredEntrance(index: 4, reduceMotion: reduceMotion)
                        poolsSection
                            .fleetStaggeredEntrance(index: 5, reduceMotion: reduceMotion)
                    }
                }
                if !embedsControlsInWideTelemetry {
                    controls
                        .fleetStaggeredEntrance(index: 6, reduceMotion: reduceMotion)
                }
                Text(isXMRig
                    ? "XMRig control is limited to reviewed pause and resume commands. Hash Fleet never stops the process or rewrites its configuration."
                    : "Every write requires explicit review. Endpoint availability depends on the installed firmware, not this app.")
                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                    .fleetStaggeredEntrance(index: 7, reduceMotion: reduceMotion)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fleetPageContainer(
                compactMaxWidth: usesWideDetail ? FleetLayout.wideDetailWidth : FleetLayout.compactDetailWidth
            )
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured in
            // Only a width that changes the column arrangement may re-render this page. Writing
            // every point of width forced the whole detail tree (charts included) to rebuild
            // repeatedly inside one AppKit layout pass, which hung the native window.
            let settled = MinerDetailWidthPolicy.settledWidth(
                previous: contentWidth, measured: measured, isMac: FleetLayout.isMac
            )
            #if os(macOS)
            FleetMacNavigationTrace.record(
                "detail.width", "previous=\(contentWidth) measured=\(measured) settled=\(settled)"
            )
            #endif
            if settled != contentWidth { contentWidth = settled }
        }
        .background(FleetTheme.canvas)
        .fleetAppNavigation { $0.navigationTitle(currentDevice.name) }
        .fleetPerformanceScreen("Miner")
        .navigationBarTitleDisplayMode(.inline)
        .tint(FleetTheme.accent)
        .fleetAppNavigation { base in
        base.navigationDestination(for: MinerEndpoint.self) { endpoint in
            MinerEndpointView(device: device, store: store, endpoint: endpoint, insights: insights)
        }
        }
        #if !os(macOS)
        .navigationDestination(item: $tuningSessionRoute) { route in
            MinerTuningSessionView(device: route, store: store, insights: insights)
        }
        #endif
        .refreshable { await store.refresh() }
        .task(id: FirmwareCheckIdentity(deviceID: device.id, updatedAt: snapshot?.updatedAt)) {
            guard !store.isDemo, device.kind == .espMiner else { return }
            await store.firmwareUpdates.checkIfNeeded(device: device, info: snapshot?.info)
        }
        .onAppear {
            isNoticeSilenced = MinerNoticeSnoozeStore.isSnoozed(for: device.id, defaults: store.defaults)
            if store.isPoolIconDemo { showsPools = true }
        }
        .task(id: isNoticeSilenced) {
            isNoticeSilenced = MinerNoticeSnoozeStore.isSnoozed(for: device.id, defaults: store.defaults)
            while !Task.isCancelled {
                guard let until = MinerNoticeSnoozeStore.snoozedUntil(for: device.id, defaults: store.defaults) else {
                    isNoticeSilenced = false
                    return
                }
                let remaining = until.timeIntervalSinceNow
                guard remaining > 0 else {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2)) {
                        isNoticeSilenced = false
                    }
                    return
                }
                let sleepNanoseconds = UInt64(min(remaining, 60) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
                if !MinerNoticeSnoozeStore.isSnoozed(for: device.id, defaults: store.defaults) {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2)) {
                        isNoticeSilenced = false
                    }
                    return
                }
            }
        }
        .toolbar {
            if !guidedDemo {
            #if !os(macOS)
            ToolbarItem(placement: .principal) {
                minerTitle
            }
            #endif
            ToolbarItem(placement: FleetToolbarLocation.trailing) {
                Button("Refresh", systemImage: "arrow.triangle.2.circlepath") { Task { await store.refresh() } }
                    .fleetToolbarButton()
                    .accessibilityIdentifier("detail.refresh")
            }
            .fleetUnadornedToolbarBackground()
            ToolbarItem(placement: FleetToolbarLocation.trailing) {
                Menu("Manage miner", systemImage: "ellipsis") {
                    Button("Rename in app", systemImage: "pencil") {
                        renameDraft = currentDevice.name
                        renameError = nil
                        showsRenamePrompt = true
                    }
                    Button("Remove from fleet", systemImage: "trash", role: .destructive) {
                        showsRemoveConfirmation = true
                    }
                }
                .fleetToolbarMenu()
                .disabled(store.isDemo)
                .accessibilityIdentifier("detail.manageMiner")
            }
            .fleetUnadornedToolbarBackground()
            }
        }
        .environment(\.minerNavigationIdentity, navigationIdentity)
    }

    var minerTitle: some View {
        MinerNavigationTitle(pageTitle: nil, identifier: "detail.minerTitle")
    }

    var detailColumnControl: some View {
        let availableWidth = max(0, contentWidth - (FleetLayout.pagePadding * 2))
        return HStack {
            Spacer(minLength: 0)
            Menu {
                Button {
                    macDetailColumns = 0
                } label: {
                    Label("Automatic", systemImage: macDetailColumns == 0 ? "checkmark" : "arrow.left.and.right")
                }
                Divider()
                Button {
                    macDetailColumns = 1
                } label: {
                    Label("One column", systemImage: macDetailColumns == 1 ? "checkmark" : "rectangle")
                }
                Button {
                    macDetailColumns = 2
                } label: {
                    Label("Two columns", systemImage: macDetailColumns == 2
                        ? "checkmark" : "rectangle.split.2x1")
                }
                .disabled(!FleetLayout.canUseTwoMacDetailColumns(availableWidth: availableWidth))
                Button {
                    macDetailColumns = 3
                } label: {
                    Label("Three columns", systemImage: macDetailColumns == 3
                        ? "checkmark" : "rectangle.split.3x1")
                }
                .disabled(!FleetLayout.canUseThreeMacDetailColumns(availableWidth: availableWidth))
            } label: {
                Label("\(detailColumnCount) columns", systemImage: "rectangle.grid.2x2")
                    .fleetFont(.caption, weight: .semibold)
                    .foregroundStyle(FleetTheme.ink)
                    .fleetPillPadding()
                    .background(FleetTheme.surface, in: Capsule())
            }
            .fleetDesignedMenu()
            .accessibilityLabel("Miner workspace columns")
            .accessibilityValue("\(detailColumnCount) columns")
            .accessibilityIdentifier("detail.macColumns")
            .help("Automatically fit three, two or one columns, or choose a column limit")
        }
    }

    var detailColumnCount: Int {
        if FleetLayout.isMac {
            let availableWidth = max(0, contentWidth - (FleetLayout.pagePadding * 2))
            return FleetLayout.macDetailColumns(for: availableWidth, preferred: macDetailColumns)
        }
        return FleetLayout.usesTwoColumns(width: contentWidth) ? 2 : 1
    }

    var usesWideDetail: Bool {
        detailColumnCount >= 2 && !dynamicTypeSize.isAccessibilitySize
    }

    var embedsControlsInWideTelemetry: Bool {
        usesWideDetail && info != nil && !isXMRig
    }

    /// Supplies actual sample time and snapshot provenance so retained/error states never append history.
    func firmwareTelemetryView(_ info: MinerInfo) -> some View {
        let observedAt = snapshot?.completeSnapshotAt ?? snapshot?.updatedAt
        return FirmwareTelemetryView(
            info: info,
            observedAt: observedAt,
            minerIdentity: currentDevice.id.uuidString,
            isCached: snapshot?.isCached ?? true,
            error: snapshot?.error,
            isReconnecting: snapshot?.isReconnecting ?? true,
            freshness: MinerSnapshotFreshness(updatedAt: observedAt)
        )
    }

    /// Builds the detail telemetry sections from the same current MinerInfo sample.
    @ViewBuilder
    func telemetrySections(_ info: MinerInfo) -> some View {
        if isXMRig {
            hashrateHero(info)
            minerHistoryCard
            bestShares(info)
            xmrigControlLink
            identity(info)
        } else {
        let diagnostics = MinerDiagnosticsModel(info: info)
        if FleetLayout.isMac && usesWideDetail {
            desktopTelemetrySections(info, diagnostics: diagnostics)
        } else if usesWideDetail {
            // Wide windows: readings on the left, controls and secondary cards on the right, so
            // the whole miner fits without long scrolling. Order within each column is unchanged.
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    hashrateHero(info)
                    minerHistoryCard
                    firmwareTelemetryView(info)
                    heroConditions(info)
                    bestShares(info)
                    MinerDetailSection { metrics(info, diagnostics: diagnostics) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 14) {
                    controlMinerCard
                    identity(info)
                    poolsSection
                    MinerDiagnosticsView(model: diagnostics)
                    // Keep the shorter side useful instead of leaving a tall empty desktop column.
                    // On compact layouts these links retain their original position below telemetry.
                    controls
                        .fleetStaggeredEntrance(index: 6, reduceMotion: reduceMotion)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            hashrateHero(info)
            minerHistoryCard
            firmwareTelemetryView(info)
            heroConditions(info)
            bestShares(info)
            controlMinerCard
            identity(info)
            MinerDetailSection { metrics(info, diagnostics: diagnostics) }
            poolsSection
            MinerDiagnosticsView(model: diagnostics)
        }
        }
    }

    /// True when the latest snapshot reads as connected or live. Drives the one-shot
    /// badge pulse when the miner crosses a connection boundary.
    var isDetailOnline: Bool {
        snapshot?.isReconnecting != true && snapshot?.error == nil && info != nil
    }

    /// One line instead of the previous four-line masthead. The navigation bar already shows the
    /// device name, so repeating it as a large title only pushed the readings off-screen. The address
    /// stays selectable here and is repeated in full inside Identity.
    var statusStrip: some View {
        HStack(spacing: 10) {
            Image("HashFleetHeader")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: FleetLayout.isMac ? 64 : 48, height: FleetLayout.isMac ? 64 : 48)
                .clipShape(RoundedRectangle(cornerRadius: FleetLayout.isMac ? 16 : 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                let connectedTitle = isLive ? "LIVE" : "CONNECTED"
                FleetStatusBadge(
                    title: store.isDemo
                        ? "DEMO · READ ONLY"
                        : (snapshot?.isReconnecting == true ? "RECONNECTING…"
                            : (snapshot?.error == nil && info != nil ? connectedTitle : "UNAVAILABLE")),
                    color: store.isDemo
                        ? FleetTheme.accent
                        : (snapshot?.isReconnecting == true ? FleetTheme.secondary
                            : (snapshot?.error == nil && info != nil ? FleetTheme.positive : FleetTheme.warning))
                )
                // One gentle pulse only when the connection state itself changes; telemetry
                // refreshes that keep the same state never re-run it.
                .fleetStatusTransitionPulse(
                    isOnline: isDetailOnline,
                    color: FleetTheme.positive,
                    reduceMotion: reduceMotion
                )
                // Honest data age: the badge says connected, this says how old the readings are,
                // so a stale or dead miner can never look freshly live.
                TimelineView(.periodic(from: .now, by: MinerSnapshotFreshness.refreshInterval)) { context in
                    if let freshness = MinerSnapshotFreshness(updatedAt: snapshot?.updatedAt, now: context.date) {
                        Label(freshness.summary, systemImage: freshness.isStale ? "clock.exclamationmark" : "clock")
                            .fleetFont(.caption2)
                            .foregroundStyle(freshness.isStale ? FleetTheme.warning : FleetTheme.secondary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(freshness.accessibilityLabel)
                            .accessibilityIdentifier("detail.snapshotFreshness")
                    }
                }
            }
            Spacer(minLength: 8)
            BrowserLink(
                label: device.address,
                rawValue: device.address,
                identifier: "detail.address",
                font: FleetTheme.mono(12),
                defaultScheme: "http",
                alignment: .trailing
            )
                .frame(maxWidth: 220, alignment: .trailing)
        }
        .foregroundStyle(FleetTheme.ink)
    }

    var expansionAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.18)
    }

    var expansionTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top))
    }
}

#Preview("Miner detail · demo") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.miner-detail-preview")!)
    store.loadDemo()
    return NavigationStack {
        MinerDetailView(device: store.devices[0], store: store)
    }
}

/// Quantizes measured detail width to the thresholds that change its arrangement, with
/// hysteresis so a width hovering at a boundary cannot flip the column count back and forth.
enum MinerDetailWidthPolicy {
    static let hysteresis: CGFloat = 16

    static func thresholds(isMac: Bool) -> [CGFloat] {
        let padding = FleetLayout.pagePadding * 2
        return isMac
            ? [FleetLayout.macDetailTwoColumnThreshold + padding, FleetLayout.macDetailThreeColumnThreshold + padding]
            : [FleetLayout.twoColumnThreshold]
    }

    static func settledWidth(previous: CGFloat, measured: CGFloat, isMac: Bool) -> CGFloat {
        guard measured.isFinite, measured >= 0 else { return previous }
        guard previous > 0 else { return measured }
        let limits = thresholds(isMac: isMac)
        func level(_ width: CGFloat) -> Int { limits.filter { width >= $0 }.count }
        let current = level(previous)
        let target = level(measured)
        if target == current { return previous }
        let cleared = target > current ? level(measured - hysteresis) : level(measured + hysteresis)
        return (target > current ? cleared > current : cleared < current) ? measured : previous
    }
}
