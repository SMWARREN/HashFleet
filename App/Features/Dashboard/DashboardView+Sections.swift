import SwiftUI
import HashFleetCore

/// Dashboard content sections and rows: header, search, hero context, miner cards, and footer.
extension DashboardView {
    internal func dashboardContent(viewport: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: usesNumberFirstOverview ? 0 : 8) {
            if store.isDemo { demoNotice }
            if store.isPoolIconDemo { poolIconDemoGallery }
            if store.visibleDevices.isEmpty {
                // Leave a visible gap before the first card, separate from that card's inner padding.
                heading
                    .padding(.bottom, usesCompactHorizontalLayout ? 28 : 0)
                FleetOnboardingView(
                    addMiner: { showingAddMiner = true },
                    exploreDemo: { store.loadDemo() }
                )
                Button {
                    showingFeatureTour = true
                } label: {
                    Label("New here? Start the feature tour", systemImage: "sparkles")
                        .fleetFont(.subheadline, weight: .semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("dashboard.onboardingTour")
            } else {
                populatedContent(viewport: viewport)
            }
        }
        .fleetPageContainer(
            compactMaxWidth: FleetLayout.dashboardContentWidth
        )
        .onGeometryChange(for: Int.self) { geometry in
            let offset = -geometry.frame(in: .named("dashboardScroll")).minY
            return offset < -35 ? -1 : (offset > 90 ? 1 : 0)
        } action: { position in
            if position == -1 { showsSearch = true }
            if position == 1 && searchText.isEmpty && !searchIsFocused { showsSearch = false }
        }
    }

    private func populatedContent(viewport: GeometryProxy) -> some View {
        let headlineKind = FleetHistoryKind.available(in: store.visibleDevices).first ?? .sha256
        let headline = headlineKind.totals(devices: store.visibleDevices, snapshots: store.snapshots)
        let compactDashboard = viewport.size.width < FleetLayout.tier1Threshold
        let sectionSpacing: CGFloat = usesNumberFirstOverview ? 8 : (compactDashboard ? 10 : 14)
        return VStack(alignment: .leading, spacing: sectionSpacing) {
                // Keep the normal dashboard free of a scrolling strip. Large text and
                // VoiceOver still need complete per-miner summaries before the charts
                // and lazy card grid. These environments select the existing static,
                // fully wrapping presentation, with no clock or pause control.
                if dashboardMode == .full && !FleetLayout.isMac
                    && (voiceOver || (!usesNumberFirstOverview && dynamicTypeSize.isAccessibilitySize)) {
                    FleetStatusTicker(fleet: store)
                        .fleetCard(padding: FleetLayout.cardPadding, fill: FleetTheme.raised)
                }
                if !store.isDemo && (store.isReconnecting || populatedFleetHasErrors) {
                    fleetOverviewNotice
                        .accessibilityIdentifier("dashboard.bitsy")
                        .fleetStaggeredEntrance(index: 0, reduceMotion: reduceMotion)
                }
                FleetHeroCard(
                    hashrate: headline.hashrate,
                    power: store.powerReading,
                    onlineCount: store.onlineCount,
                    deviceCount: store.visibleDevices.count,
                    isDemo: store.isDemo,
                    isRefreshing: store.isRefreshing,
                    isInitialLoading: !store.isDemo
                        && headlineKind.devices(in: store.visibleDevices).allSatisfy { device in
                            let snapshot = store.snapshots[device.id]
                            return snapshot?.isReconnecting == true || MinerLoadingPolicy.shouldShowSkeleton(
                                info: snapshot?.info,
                                error: snapshot?.error,
                                isDemo: store.isDemo
                            )
                        },
                    realtimeMonitoring: store.preferences.realtimeMonitoring,
                    liveConnectionCount: store.liveConnectedDeviceIDs.count,
                    liveFallbackCount: store.liveConnectionErrors.count,
                    sourceTitle: headlineKind.title,
                    compact: compactDashboard,
                    numberFirst: usesNumberFirstOverview
                )
                .fleetTourTarget("guide.hero")
                .fleetStaggeredEntrance(index: 1, reduceMotion: reduceMotion)
                if dashboardMode == .full {
                    fleetErrorSummary.fleetStaggeredEntrance(index: 2, reduceMotion: reduceMotion)
                    cpuHashrate
                    .fleetStaggeredEntrance(index: 3, reduceMotion: reduceMotion)
                } else {
                    reportedFleetAlerts
                }
                FleetHistoryCard(
                    devices: store.visibleDevices,
                    snapshots: store.snapshots,
                    isDemo: store.isDemo,
                    initialRecentRange: .oneMinute,
                    isCompactDashboard: compactDashboard,
                    dashboardMode: dashboardMode,
                    numberFirst: usesNumberFirstOverview,
                    prefersHistoryPopover: usesNumberFirstOverview && dynamicTypeSize.isAccessibilitySize
                )
                    .accessibilityIdentifier("dashboard.history")
                    .fleetTourTarget("guide.history")
                    .fleetStaggeredEntrance(index: 4, reduceMotion: reduceMotion)
                if dashboardMode == .full && headlineKind == .sha256 { fleetHashrateComparison }
                FleetChainCard(fleet: store, insights: insights, compact: compactDashboard)
                    .fleetTourTarget("guide.chain")
                    .fleetStaggeredEntrance(index: 5, reduceMotion: reduceMotion)
                if dashboardMode == .essentials {
                    fleetErrorSummary
                }
                minersSection(viewport: viewport)
                    .id("fleet-miners")
                    .fleetStaggeredEntrance(index: 6, reduceMotion: reduceMotion)
                if dashboardMode == .full {
                    AnyView(secondaryOverview(wide: isWideDashboard(viewport)))
                } else {
                    AnyView(essentialsFleetDetails(compact: compactDashboard, wide: isWideDashboard(viewport)))
                }
                footer
                    .fleetStaggeredEntrance(index: 11, reduceMotion: reduceMotion)
            }
    }

    @ViewBuilder
    private var fleetHashrateComparison: some View {
        let slices = FleetHashrateShare.slices(devices: store.visibleDevices, snapshots: store.snapshots)
        if slices.count >= 2 {
            FleetHashrateShareStrip(slices: slices)
                .fleetCard(padding: FleetSurfaceSpacing.cardInset, fill: FleetTheme.charcoal)
        }
    }

    private func essentialsFleetDetails(compact: Bool, wide: Bool) -> some View {
        DisclosureGroup(isExpanded: $showsFleetDetails) {
            VStack(alignment: .leading, spacing: 12) {
                cpuHashrate
                secondaryOverview(wide: wide)
            }
            .padding(.top, 8)
        } label: {
            Text("More fleet details")
                .fleetFont(.headline)
                .foregroundStyle(FleetTheme.ink)
                .frame(minHeight: 44)
        }
        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
    }

    @ViewBuilder
    private var cpuHashrate: some View {
        if FleetHistoryKind.available(in: store.visibleDevices).count > 1 {
            let cpu = FleetHistoryKind.cpu.totals(devices: store.visibleDevices, snapshots: store.snapshots).hashrate
            FleetMetricCard(
                title: "CPU · XMRig",
                value: cpu.hasReading ? FleetFormat.hashrate(cpu.value) : "—",
                unit: cpu.hasReading ? FleetFormat.hashrateUnit(cpu.value) : "",
                symbol: "cpu",
                caption: "Separate from SHA-256. " + (FleetReadingCaption.hashrate(cpu) ?? "Reported CPU rate."),
                identifier: "dashboard.cpuHashrate",
                accessibleValue: cpu.hasReading ? FleetFormat.hashrateWithUnit(cpu.value) : "Not reported"
            )
        }
    }

    @ViewBuilder
    private func secondaryOverview(wide: Bool) -> some View {
        if !FleetLayout.isMac {
            fleetToolsSection.fleetStaggeredEntrance(index: 7, reduceMotion: reduceMotion)
        }
        dashboardPair(wide: wide) {
            FleetBestShareCard(
                devices: store.visibleDevices, snapshots: store.snapshots,
                bestShareObservations: store.bestShareObservations, isDemo: store.isDemo, isCompact: true
            )
            .fleetStaggeredEntrance(index: 8, reduceMotion: reduceMotion)
        } trailing: {
            FleetMilestonesCard(
                devices: store.visibleDevices, snapshots: store.snapshots,
                blockObservations: store.blockObservations, latestBlockEvent: store.latestBlockFoundEvent,
                isDemo: store.isDemo, openAchievements: { routeToDashboardPage(.achievements) }
            )
            .fleetStaggeredEntrance(index: 9, reduceMotion: reduceMotion)
        }
        summaryMetrics(wide: wide).fleetStaggeredEntrance(index: 10, reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private var reportedFleetAlerts: some View {
        let reports = store.visibleDevices.compactMap { miner -> (MinerDevice, MinerReportedAlerts)? in
            guard let snapshot = store.snapshots[miner.id], !snapshot.isCached, !snapshot.isReconnecting,
                  snapshot.error == nil, let info = snapshot.info, let alerts = MinerReportedAlerts(info: info)
            else { return nil }
            return (miner, alerts)
        }
        if !reports.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(store.isDemo ? "Sample miner alerts" : "Miner alerts", systemImage: "exclamationmark.triangle")
                    .fleetFont(.headline).accessibilityAddTraits(.isHeader)
                ForEach(reports, id: \.0.id) { miner, alerts in
                    ForEach(Array(alerts.messages.enumerated()), id: \.offset) { _, message in
                        Text("\(miner.name): \(message)")
                            .fleetFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .foregroundStyle(FleetTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fleetCard(padding: FleetSurfaceSpacing.cardInset, fill: FleetTheme.warning.opacity(0.10))
        }
    }

    private var populatedFleetHasErrors: Bool {
        attentionSummary.hasUnreachable
    }

    private var fleetOverviewNoticeText: String {
        if store.isReconnecting {
            return "Updating miner readings"
        }
        if populatedFleetHasErrors {
            return "Some miner readings need attention"
        }
        return "Latest miner readings"
    }

    private var fleetOverviewNoticeSymbol: String {
        if store.isReconnecting { return "arrow.triangle.2.circlepath" }
        return populatedFleetHasErrors ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var fleetOverviewNotice: some View {
        Label(fleetOverviewNoticeText, systemImage: fleetOverviewNoticeSymbol)
            .fleetFont(.footnote, weight: .semibold)
            .foregroundStyle(FleetTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FleetTheme.accent.opacity(0.28), lineWidth: 1)
            }
    }

    @ToolbarContentBuilder
    internal var brandToolbarItem: some ToolbarContent {
        if !FleetLayout.isMac {
            ToolbarItem(placement: FleetToolbarLocation.leading) {
                Button {
                    if let onToggleSidebar {
                        onToggleSidebar()
                    } else {
                        showingSideMenu = true
                    }
                } label: {
                    FleetHeaderArtwork()
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(onToggleSidebar == nil ? "Fleet tools" : "Toggle fleet sidebar")
                .accessibilityHint(
                    onToggleSidebar == nil
                        ? "Opens miners, insights, reports, backup, and settings."
                        : "Shows or hides the fleet navigation sidebar."
                )
                .accessibilityIdentifier("dashboard.headerLogoButton")
                .help(onToggleSidebar == nil ? "Fleet tools" : "Toggle fleet sidebar")
            }
        }
    }

    internal var minerSearch: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField("Find a miner", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchIsFocused)
                .onSubmit { searchIsFocused = false }
                .accessibilityIdentifier("dashboard.search")
            if !searchText.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { searchText = "" }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .fleetFont(.subheadline)
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("YOUR MINING COMPANION")
                .fleetFont(.caption, weight: .medium, design: .monospaced)
                .tracking(1.6)
                .foregroundStyle(FleetTheme.secondary)
                .accessibilityHidden(true)
            Text("Fleet overview")
                .fleetFont(.largeTitle, weight: .bold)
                .tracking(-1.2)
            Text("Good things start with a single miner.")
                .fleetFont(.subheadline)
                .foregroundStyle(FleetTheme.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("dashboard.firstMinerHeading")
    }

    func summaryMetrics(wide: Bool) -> some View {
        let layout: AnyLayout
        if FleetLayout.isMac {
            layout = AnyLayout(FleetMinerDetailGrid(
                maximumColumns: dynamicTypeSize.isAccessibilitySize || !wide ? 1 : 2,
                minimumColumnWidth: 320, spacing: 12
            ))
        } else {
            layout = dynamicTypeSize.isAccessibilitySize || !wide
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        }
        let power = store.powerReading
        let efficiency = FleetHistoryKind.sha256.totals(devices: store.visibleDevices, snapshots: store.snapshots).efficiency
        return layout {
            FleetMetricCard(
                title: "Total power",
                value: power.hasReading ? FleetFormat.number(power.value) : "—",
                unit: power.hasReading ? "W" : "",
                symbol: "bolt.fill",
                caption: FleetReadingCaption.power(power),
                identifier: "dashboard.totalPower",
                accessibleValue: power.hasReading ? "\(FleetFormat.number(power.value)) watts" : "Not reported"
            )
            FleetMetricCard(
                title: "Efficiency",
                value: efficiency.value.map { FleetFormat.number($0, decimals: 1) } ?? "—",
                unit: efficiency.hasReading ? "J/TH" : "",
                symbol: "leaf.fill",
                caption: FleetReadingCaption.efficiency(efficiency),
                identifier: "dashboard.efficiency",
                accessibleValue: efficiency.value.map { "\(FleetFormat.number($0, decimals: 1)) joules per terahash" }
                    ?? "Not reported"
            )
        }
    }

    @ViewBuilder
    private func minersSection(viewport: GeometryProxy) -> some View {
        let listSummary = dashboardListSummary
        let availableWidth = max(0, viewport.size.width - (FleetLayout.pagePadding * 2))
        let preferredColumns = FleetLayout.isMac
            ? FleetLayout.macDashboardCardColumns(for: availableWidth, preferred: macMinerColumns)
            : FleetLayout.dashboardCardColumns(for: viewport.size.width, regularSizeClass: !usesCompactHorizontalLayout)
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : preferredColumns
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: FleetLayout.cardGridSpacing), count: columns)
        VStack(alignment: .leading, spacing: usesNumberFirstOverview ? 4 : 10) {
            minerSectionHeader(listSummary: listSummary, availableWidth: availableWidth)
            if filteredDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "plus.circle"
                        : "magnifyingglass")
                        .fleetFont(.title3, weight: .semibold)
                        .foregroundStyle(FleetTheme.accent)
                        .accessibilityHidden(true)
                    Text(FleetDashboardListSummary.emptySearchTitle(for: searchText))
                        .fleetFont(.headline)
                    Text(FleetDashboardListSummary.emptySearchMessage(for: searchText))
                        .fleetFont(.subheadline)
                        .foregroundStyle(FleetTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fleetCard(padding: 18, fill: FleetTheme.surface)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("dashboard.minerSearchEmpty")
            }
            minerCardsContainer(
                columns: columns,
                gridItems: gridItems,
                devices: filteredDevices
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.24),
                value: filteredDevices.map { $0.id }
            )
        }
    }

    @ViewBuilder
    private func minerSectionHeader(
        listSummary: FleetDashboardListSummary,
        availableWidth: CGFloat
    ) -> some View {
        let sampleCount = usesNumberFirstOverview && store.isDemo && searchText.isEmpty
            ? "\(store.visibleDevices.count) sample miners" : nil
        let layout =
            overviewTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: usesNumberFirstOverview ? .center : .top,
                                    spacing: usesNumberFirstOverview ? 8 : 12))
        layout {
            VStack(alignment: .leading, spacing: usesNumberFirstOverview ? 2 : 4) {
                Text("Your miners")
                    .fleetFont(usesNumberFirstOverview ? .headline : .title3, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(sampleCount ?? listSummary.subtitle)
                    .fleetFont(usesNumberFirstOverview ? .footnote : .subheadline)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(sampleCount ?? listSummary.accessibilityLabel)
            }
            if !overviewTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            if dashboardMode == .essentials && !store.isDemo {
                Button {
                    showingAddMiner = true
                } label: {
                    Label("Add miner", systemImage: "plus")
                        .fleetFont(.subheadline, weight: .semibold)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(FleetTheme.accent)
                .accessibilityIdentifier("dashboard.essentialsAddMiner")
            }
            minerSectionControls(availableWidth: availableWidth)
        }
    }

    /// Keep the control menus behind a stable type-erasure boundary on physical iOS 26.6.
    ///
    /// The nested menu labels and state-dependent branches otherwise become part of the
    /// already-large generic type produced by `minersSection`. On the affected device,
    /// Swift metadata resolution recurses through that type tree until the main-thread
    /// stack guard is hit during the first dashboard render.
    private func minerSectionControls(availableWidth: CGFloat) -> AnyView {
        AnyView(HStack(alignment: .center, spacing: 8) {
            minerDisplayMenu
            if FleetLayout.isMac {
                Menu {
                    Button {
                        macMinerColumns = 0
                    } label: {
                        Label("Automatic", systemImage: macMinerColumns == 0 ? "checkmark" : "arrow.left.and.right")
                    }
                    Divider()
                    Button {
                        macMinerColumns = 1
                    } label: {
                        Label("One column", systemImage: macMinerColumns == 1 ? "checkmark" : "rectangle")
                    }
                    Button {
                        macMinerColumns = 2
                    } label: {
                        Label("Two columns", systemImage: macMinerColumns == 2
                            ? "checkmark" : "rectangle.split.2x1")
                    }
                    .disabled(!FleetLayout.canUseTwoMacDashboardColumns(availableWidth: availableWidth))
                    Button {
                        macMinerColumns = 3
                    } label: {
                        Label("Three columns", systemImage: macMinerColumns == 3
                            ? "checkmark" : "rectangle.split.3x1")
                    }
                    .disabled(!FleetLayout.canUseThreeMacDashboardColumns(availableWidth: availableWidth))
                } label: {
                    Image(systemName: "rectangle.grid.2x2")
                        .fleetFont(.caption, weight: .semibold)
                        .foregroundStyle(FleetTheme.ink)
                        .fleetPillPadding()
                        .background(FleetTheme.raised, in: Capsule())
                        .frame(minWidth: 48, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .fleetDesignedMenu()
                .accessibilityLabel("Miner card columns")
                .accessibilityValue(
                    "\(FleetLayout.macDashboardCardColumns(for: availableWidth, preferred: macMinerColumns)) columns"
                )
                .accessibilityIdentifier("dashboard.macColumns")
                .help("Automatically fit three, two or one columns, or choose a column limit")
            }

            // Expand/Collapse ALL button
            if !store.visibleDevices.isEmpty {
                Menu {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            for device in store.visibleDevices {
                                minerExpansion[device.id] = true
                            }
                        }
                    } label: {
                        Label("Expand all", systemImage: "chevron.down.circle")
                    }
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            for device in store.visibleDevices {
                                minerExpansion[device.id] = false
                            }
                        }
                    } label: {
                        Label("Collapse all", systemImage: "chevron.up.circle")
                    }
                    if !store.isDemo {
                        Divider()
                        Button(role: .destructive) {
                            confirmingDeleteAll = true
                        } label: {
                            Label("Delete all miners…", systemImage: "trash")
                        }
                        .accessibilityIdentifier("dashboard.minersDeleteAll")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .fleetFont(.caption, weight: .semibold)
                        .foregroundStyle(FleetTheme.ink)
                        .fleetPillPadding()
                        .background(FleetTheme.raised, in: Capsule())
                        .frame(minWidth: 48, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .fleetDesignedMenu()
                .accessibilityLabel("Miner actions")
            }
        })
    }

    @ViewBuilder
    var fleetErrorSummary: some View {
        let unreachable = attentionSummary.unreachable
        let liveFallbacks = attentionSummary.liveFallbacks
        if !unreachable.isEmpty || !liveFallbacks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Fleet attention", systemImage: "exclamationmark.triangle.fill")
                    .fleetFont(.headline)
                    .foregroundStyle(FleetTheme.warning)
                if !unreachable.isEmpty {
                    Text("\(unreachable.count) \(unreachable.count == 1 ? "miner is" : "miners are") unreachable.")
                        .fleetFont(.footnote, weight: .semibold)
                        .foregroundStyle(FleetTheme.warning)
                }
                ForEach(unreachable) { device in
                    if let error = store.snapshots[device.id]?.error {
                        Label("\(device.name): \(error)", systemImage: "wifi.exclamationmark")
                            .fleetFont(.footnote)
                            .foregroundStyle(FleetTheme.warning)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !liveFallbacks.isEmpty {
                    let minersWithUnavailableStream =
                        "\(liveFallbacks.count) \(liveFallbacks.count == 1 ? "miner has" : "miners have")"
                    Text(
                        "\(minersWithUnavailableStream) an unavailable live stream. " +
                            "HTTP refresh is still active."
                    )
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.warning)
                }
                Text("Open the affected miner card for details. Last-known readings are labeled.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fleetCard(padding: FleetSurfaceSpacing.cardInset, fill: FleetTheme.warning.opacity(0.10))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("dashboard.errorSummary")
        }
    }

}
