import SwiftUI
import HashFleetCore

/// Per-miner card assembly on the dashboard: card shell, control cluster, and settings routing.
extension DashboardView {
    /// Keep the large miner-card generic tree behind a stable type-erasure boundary.
    ///
    /// On iOS 26.6 physical devices, resolving the nested `ForEach` and layout generic metadata
    /// from inside `minersSection` can recurse through Swift's metadata demangler and overflow
    /// the main-thread stack during the first dashboard render. The simulator and earlier iOS
    /// runtimes do not reproduce it. The erasure is limited to the grid container, so individual
    /// cards and their identity remain unchanged.
    internal func minerCardsContainer(
        columns: Int,
        gridItems: [GridItem],
        devices: [MinerDevice]
    ) -> AnyView {
        if usesNumberFirstOverview {
            #if os(macOS)
            if columns > 1 && devices.count > 1 {
                return AnyView(
                    HStack(alignment: .top, spacing: 15) {
                        ForEach(0..<columns, id: \.self) { col in
                            let colDevices = devices.enumerated().filter { $0.offset % columns == col }.map(\.element)
                            if !colDevices.isEmpty {
                                numberFirstMinerList(devices: colDevices)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                    }
                    .id(columns)
                )
            }
            #endif
            return AnyView(numberFirstMinerList(devices: devices))
        }

        #if os(macOS)
        return AnyView(
            FleetMinerDetailGrid(
                maximumColumns: columns,
                minimumColumnWidth: 320,
                spacing: 12,
                balancesFourItems: false
            ) {
                dashboardMinerCards(devices: devices)
            }
        )
        #else
        return AnyView(
            LazyVGrid(columns: gridItems, spacing: FleetLayout.cardGridSpacing) {
                dashboardMinerCards(devices: devices)
            }
        )
        #endif
    }

    @ViewBuilder private func numberFirstMinerList(devices: [MinerDevice]) -> some View {
        if !devices.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(devices) { device in
                    let expanded = minerExpansion[device.id] ?? !numberFirstCompactCards
                    if device.id != devices.first?.id {
                        Rectangle().fill(FleetTheme.separator)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        minerCardLink(device, expanded: expanded)
                        minerCardControls(device, expanded: expanded)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 12)
            .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func dashboardMinerCards(devices: [MinerDevice]) -> some View {
        ForEach(devices) { device in
            minerCard(device)
                .fleetMinerCardScrollTransition(reduceMotion: reduceMotion)
        }
    }

    @ViewBuilder
    private func minerCard(_ device: MinerDevice) -> some View {
        let isEssentials = store.preferences.dashboardMode == .essentials
        let expanded = minerExpansion[device.id] ?? (isEssentials ? !numberFirstCompactCards : !store.preferences.compactCards)
        if isEssentials {
            VStack(alignment: .leading, spacing: 0) {
                minerCardLink(device, expanded: expanded)
                minerCardControls(device, expanded: expanded)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .transition(
                reduceMotion
                    ? .identity
                    : .opacity.combined(with: .move(edge: .bottom))
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                minerCardLink(device, expanded: expanded)
                Rectangle()
                    .fill(FleetTheme.separator)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                minerCardControls(device, expanded: expanded)
            }
            .frame(maxWidth: .infinity, maxHeight: FleetLayout.isMac ? .infinity : nil, alignment: .topLeading)
            .padding(.horizontal, FleetLayout.cardPadding)
            .padding(.top, FleetLayout.cardPadding)
            .padding(.bottom, 4)
            .fleetCard(padding: 0, fill: FleetTheme.raised, border: FleetTheme.separator, cornerRadius: 24)
            .transition(
                reduceMotion
                    ? .identity
                    : .opacity.combined(with: .move(edge: .bottom))
            )
        }
    }

    private func minerCardLink(_ device: MinerDevice, expanded: Bool) -> some View {
        minerCardNavigation(device, expanded: expanded)
        .buttonStyle(.plain)
        .fleetPointerHover()
        .accessibilityIdentifier("dashboard.miner.\(device.id.uuidString)")
        .fleetTourTarget("guide.miner.\(device.id.uuidString)")
        .contextMenu {
            Button("Remove miner", systemImage: "trash", role: .destructive) { minerToRemove = device }
        }
        .accessibilityAction(named: "Remove miner") { minerToRemove = device }
    }

    @ViewBuilder
    private func minerCardNavigation(_ device: MinerDevice, expanded: Bool) -> some View {
        #if os(macOS)
        if let onSelectSidebarDestination {
            Button {
                FleetHaptics.selection()
                onSelectSidebarDestination(.miner(device.id))
            } label: {
                minerCardNavigationLabel(device, expanded: expanded)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: FleetMinerRoute(deviceID: device.id)) {
                minerCardNavigationLabel(device, expanded: expanded)
            }
            .simultaneousGesture(TapGesture().onEnded {
                FleetHaptics.selection()
            })
        }
        #else
        if usesCompactHorizontalLayout {
            NavigationLink {
                MinerDetailView(
                    device: device,
                    store: store,
                    insights: insights,
                    liveConnectionError: store.liveConnectionErrors[device.id],
                    isLive: store.liveConnectedDeviceIDs.contains(device.id)
                )
                .environment(\.dynamicTypeSize, dynamicTypeSize)
                .fleetMinerNavigationTransition(sourceID: device.id, in: minerTransitionNamespace, enabled: !reduceMotion)
            } label: {
                minerCardNavigationLabel(device, expanded: expanded)
                    .fleetMinerTransitionSource(id: device.id, in: minerTransitionNamespace, enabled: !reduceMotion)
            }
            .simultaneousGesture(TapGesture().onEnded {
                FleetHaptics.selection()
            })
        } else {
            // The split workspace owns this value in fleetPath. A view-based link
            // keeps its own push, which clearing the sidebar's path cannot pop.
            NavigationLink(value: FleetMinerRoute(deviceID: device.id)) {
                minerCardNavigationLabel(device, expanded: expanded)
            }
            .simultaneousGesture(TapGesture().onEnded {
                FleetHaptics.selection()
            })
        }
        #endif
    }

    private func minerCardNavigationLabel(_ device: MinerDevice, expanded: Bool) -> some View {
        FleetObservedMinerOverviewCard(
            store: store,
            insights: insights,
            device: device,
            compact: !expanded,
            numberFirst: usesNumberFirstOverview || store.preferences.dashboardMode == .essentials
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private func minerCardControls(_ device: MinerDevice, expanded: Bool) -> some View {
        let stacksActions = overviewTypeSize >= .xxxLarge
        let layout = stacksActions
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        // Keep each button's identity while the readings load or the type size changes.
        return layout {
            minerCardExpandButton(device, expanded: expanded)
            if !stacksActions { Spacer(minLength: 4) }
            minerCardSettingsButton(device)
        }
    }

    private func minerCardSettingsButton(_ device: MinerDevice) -> some View {
        Menu {
            if device.kind == .xmrig {
                Section("XMRig") {
                    Button("XMRig control", systemImage: "cpu") {
                        minerXMRigControlDevice = device
                    }
                    .accessibilityIdentifier("dashboard.card.xmrigControl")
                }
            } else {
                Section("Changes require review and confirmation") {
                    Button("Frequency & voltage", systemImage: "waveform.path.ecg.rectangle") {
                        minerTuningSessionDevice = device
                    }
                    .accessibilityIdentifier("dashboard.card.tuningSession")
                    minerSettingsButton("Cooling", symbol: "fan", category: .cooling, device: device)
                    minerSettingsButton("Edit pools", symbol: "network", category: .pools, device: device)
                }
            }
        } label: {
            minerCardActionLabel("Controls", symbol: "slider.horizontal.3")
        }
        .buttonStyle(.plain)
        .fleetDesignedMenu()
        .accessibilityLabel("Controls for \(device.name)")
        .accessibilityHint("Open miner controls. Nothing is sent without review and confirmation.")
        .accessibilityIdentifier("dashboard.card.settings.\(device.id.uuidString)")
    }

    private func minerCardExpandButton(_ device: MinerDevice, expanded: Bool) -> some View {
        Button {
            FleetHaptics.light()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                minerExpansion[device.id] = !expanded
            }
        } label: {
            minerCardActionLabel(expanded ? "Fewer readings" : "More readings",
                                 symbol: expanded ? "chevron.up" : "chevron.down")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(device.name) card")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint(usesNumberFirstOverview ? "Hashrate, status, temperature and power stay visible."
                                                   : "Hashrate, status and power stay visible.")
        .accessibilityIdentifier("dashboard.card.expand.\(device.id.uuidString)")
    }

    private func minerCardActionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .fleetFont(usesNumberFirstOverview ? .caption : .footnote, weight: .semibold)
            .foregroundStyle(FleetTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.vertical, usesNumberFirstOverview ? 2 : 8)
            .frame(
                minWidth: usesNumberFirstOverview ? 36 : 48,
                minHeight: usesNumberFirstOverview ? 28 : 48,
                alignment: .leading
            )
            .contentShape(Rectangle())
    }

    private func minerSettingsButton(
        _ title: String,
        symbol: String,
        category: MinerSettingsCategory,
        device: MinerDevice
    ) -> some View {
        Button(title, systemImage: symbol) {
            minerSettingsRoute = DashboardMinerSettingsRoute(device: device, category: category)
        }
        .accessibilityIdentifier("dashboard.card.settingsRoute.\(category.rawValue)")
    }
}

/// Keep the shared store as the authority, but read a miner's observation cell inside a
/// real child body. Reading the dictionary while constructing the dashboard makes every
/// card depend on every snapshot. Stable device identity and model references also let
/// SwiftUI retain this subtree when fleet-wide totals rebuild their parent.
///
/// Fleet summaries and charts still legitimately observe the fleet. Connection-state and
/// market changes can also update this card. This boundary does not promise that exactly
/// one view or one layout pass runs for an incoming network frame.
struct FleetObservedMinerOverviewCard: View {
    let store: FleetStore
    let insights: MiningInsightsStore
    let device: MinerDevice
    let compact: Bool
    var numberFirst = false

    var body: some View {
        MinerOverviewCard(
            device: device,
            snapshot: store.snapshot(for: device.id),
            isDemo: store.isDemo,
            compact: compact,
            isLive: store.liveConnectedDeviceIDs.contains(device.id),
            liveConnectionError: store.liveConnectionErrors[device.id],
            marketData: insights.coinMarkets,
            numberFirst: numberFirst
        )
    }
}
