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
        availableWidth: CGFloat,
        columns: Int,
        gridItems: [GridItem],
        devices: [MinerDevice]
    ) -> AnyView {
        if FleetLayout.isMac {
            return AnyView(
                FleetMinerDetailGrid(
                    maximumColumns: dynamicTypeSize.isAccessibilitySize ? 1 : columns,
                    minimumColumnWidth: 320, spacing: FleetLayout.cardGridSpacing,
                    balancesFourItems: false
                ) {
                    dashboardMinerCards(availableWidth: availableWidth, devices: devices)
                }
            )
        }

        return AnyView(
            LazyVGrid(columns: gridItems, spacing: FleetLayout.cardGridSpacing) {
                dashboardMinerCards(availableWidth: availableWidth, devices: devices)
            }
        )
    }

    internal func dashboardMinerCards(availableWidth: CGFloat, devices: [MinerDevice]) -> some View {
        ForEach(devices) { device in
            minerCard(device, availableWidth: availableWidth)
                .fleetMinerCardScrollTransition(reduceMotion: reduceMotion)
        }
    }

    internal func minerCard(_ device: MinerDevice, availableWidth: CGFloat) -> some View {
        let expanded = minerExpansion[device.id] ?? !store.preferences.compactCards
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        // Keep one link and one Menu. Alternate ViewThatFits branches can replace the
        // presenting Menu when changing live-error content changes the card's ideal width.
        return layout {
            minerCardLink(device, expanded: expanded)
            VStack(alignment: .trailing, spacing: 4) {
                minerCardExpandButton(device, expanded: expanded)
                minerCardSettingsButton(device)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, maxHeight: FleetLayout.isMac ? .infinity : nil, alignment: .topLeading)
        .fleetCard(padding: FleetLayout.cardPadding, fill: FleetTheme.raised)
        .transition(
            reduceMotion
                ? .identity
                : .opacity.combined(with: .move(edge: .bottom))
        )
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
        if usesCompactHorizontalLayout {
            NavigationLink {
                MinerDetailView(
                    device: device,
                    store: store,
                    insights: insights,
                    liveConnectionError: store.liveConnectionErrors[device.id],
                    isLive: store.liveConnectedDeviceIDs.contains(device.id)
                )
                .fleetMinerNavigationTransition(sourceID: device.id, in: minerTransitionNamespace, enabled: !reduceMotion)
            } label: {
                minerCardNavigationLabel(device, expanded: expanded)
                    .fleetMinerTransitionSource(id: device.id, in: minerTransitionNamespace, enabled: !reduceMotion)
            }
        } else {
            // The split workspace owns this value in fleetPath. A view-based link
            // keeps its own push, which clearing the sidebar's path cannot pop.
            NavigationLink(value: FleetMinerRoute(deviceID: device.id)) {
                minerCardNavigationLabel(device, expanded: expanded)
            }
        }
    }

    private func minerCardNavigationLabel(_ device: MinerDevice, expanded: Bool) -> some View {
        MinerOverviewCard(
            device: device,
            snapshot: store.snapshots[device.id],
            isDemo: store.isDemo,
            compact: !expanded,
            isLive: store.liveConnectedDeviceIDs.contains(device.id),
            liveConnectionError: store.liveConnectionErrors[device.id],
            marketData: insights.coinMarkets
        )
        .frame(maxWidth: .infinity, maxHeight: FleetLayout.isMac ? .infinity : nil, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    internal func minerCardControls(_ device: MinerDevice, expanded: Bool, horizontal: Bool = false) -> some View {
        let layout = horizontal
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 4))
        return layout {
            if horizontal {
                minerCardSettingsButton(device)
                minerCardExpandButton(device, expanded: expanded)
            } else {
                minerCardExpandButton(device, expanded: expanded)
                minerCardSettingsButton(device)
            }
        }
        .foregroundStyle(FleetTheme.accent)
        .frame(maxWidth: horizontal ? .infinity : nil, alignment: .trailing)
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
            Image(systemName: "slider.horizontal.3")
                .fleetFont(.caption2, weight: .semibold)
                .frame(width: 34, height: 34)
                .background(FleetTheme.accent.opacity(0.10), in: Capsule())
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .fleetDesignedMenu()
        .accessibilityLabel("Controls for \(device.name)")
        .accessibilityHint("Open miner controls. Nothing is sent without review and confirmation.")
        .accessibilityIdentifier("dashboard.card.settings.\(device.id.uuidString)")
    }

    private func minerCardExpandButton(_ device: MinerDevice, expanded: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                minerExpansion[device.id] = !expanded
            }
        } label: {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .fleetFont(.subheadline, weight: .semibold)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(device.name) card")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Hashrate, status and power stay visible.")
        .accessibilityIdentifier("dashboard.card.expand.\(device.id.uuidString)")
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
