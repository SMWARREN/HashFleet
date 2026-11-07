import SwiftUI
import HashFleetCore

#if os(macOS)
/// The workspace owns this route, not a Settings view also rendered in the tour sandbox.
struct FleetTourRoute: Hashable {}
#endif

struct MinerDetailDestinationView: View {
    let deviceID: UUID
    @Bindable var store: FleetStore
    let insights: MiningInsightsStore

    var body: some View {
        if let device = store.visibleDevices.first(where: { $0.id == deviceID }) {
            MinerDetailView(
                device: device,
                store: store,
                insights: insights,
                liveConnectionError: store.liveConnectionErrors[device.id],
                isLive: store.liveConnectedDeviceIDs.contains(device.id)
            )
        } else {
            ContentUnavailableView(
                "Miner unavailable",
                systemImage: "questionmark.circle",
                description: Text("This miner is removed or unavailable in this release.")
            )
        }
    }
}

/// A desktop-first split navigation container for macOS and wide iPad displays.
struct FleetSplitView: View {
    @Environment(\.fleetPresentationResetID) private var externalPresentationResetID
    @Bindable var store: FleetStore
    var insights: MiningInsightsStore
    var coordinator: FleetGlanceCoordinator?
    var startupReady: Bool
    @Binding var fleetPath: NavigationPath
    @Binding var sidebarSelection: FleetSidebarDestination?
    var onPreviewCelebration: ((FleetCelebration.Kind) -> Void)?

    @State private var showingAddMiner = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var detailPresentationResetID = UUID()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FleetSidebarView(
                selection: $sidebarSelection,
                store: store,
                insights: insights,
                showingAddMiner: $showingAddMiner,
                onRefresh: { Task { await refreshFleet() } },
                onSelect: activateSidebarDestination
            )
            // Both platforms: without a width the Mac restores a collapsed column that truncates
            // every sidebar label ("Mine…", "Network in…").
            .navigationSplitViewColumnWidth(
                min: FleetLayout.sidebarMinimumWidth,
                ideal: FleetLayout.sidebarIdealWidth,
                max: FleetLayout.sidebarMaximumWidth
            )
            .navigationTitle("Hash Fleet")
            .fleetWindowToolbarChrome()
        } detail: {
            NavigationStack(path: $fleetPath) {
                detailContent
                    .navigationDestination(for: FleetMinerRoute.self) { route in
                        MinerDetailDestinationView(deviceID: route.deviceID, store: store, insights: insights)
                            .fleetDesktopBranding(sidebarVisible: columnVisibility != .detailOnly)
                    }
                    .navigationDestination(for: FleetSupportRoute.self) { _ in
                        DeveloperSupportView()
                            .environment(\.fleetStandalonePage, FleetLayout.isMac)
                            .fleetDesktopBranding(sidebarVisible: columnVisibility != .detailOnly)
                    }
                    #if os(macOS)
                    .navigationDestination(for: FleetTourRoute.self) { _ in
                        FleetTourView(dontShowAgain: Binding(
                            get: { store.preferences.suppressFeatureTour },
                            set: { store.preferences.suppressFeatureTour = $0 }
                        ), onPreviewCelebration: onPreviewCelebration)
                        .environment(\.fleetFullWindowPresentation, true)
                        .environment(\.fleetStandalonePage, false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onDisappear { store.preferences.hasSeenFeatureTour = true }
                    }
                    .navigationDestination(for: FleetMinerSettingsRoute.self) { route in
                        if let device = store.visibleDevices.first(where: { $0.id == route.deviceID }) {
                            Group {
                                if route.category == .tuning {
                                    MinerTuningSessionView(device: device, store: store, insights: insights)
                                } else {
                                    MinerSettingsView(device: device, store: store, insights: insights,
                                                      initialCategory: route.category)
                                }
                            }
                            .fleetDesktopBranding(
                                sidebarVisible: columnVisibility != .detailOnly,
                                includesPrincipalBrand: route.category != .tuning
                            )
                        }
                    }
                    #endif
                    .fleetPagePresentation(isPresented: $showingAddMiner) {
                        AddMinerView(store: store, onBulkAddSuccess: completeBulkAdd)
                            .fleetPageSheet()
                    }
            }
            .id(sidebarSelection)
            .environment(\.fleetPresentationResetID, detailPresentationResetID)
            .onChange(of: sidebarSelection) { _, _ in
                #if os(macOS)
                FleetMacNavigationTrace.record("owner.selectionChanged", "pathCount=\(fleetPath.count)")
                #endif
                fleetPath = NavigationPath()
            }
        }
        // The split container owns navigation state beyond fleetPath, including
        // direct destination links. Reset that owner on activation, not merely its
        // detail stack, which can retain the previous screen on same-root clicks.
        .id(detailPresentationResetID)
        .navigationSplitViewStyle(.balanced)
        #if os(macOS)
        .toolbar {
            if #available(macOS 26.0, *) {
                // Restyle the system-owned item rather than adding a second toggle.
                DefaultToolbarItem(kind: .sidebarToggle)
                    .sharedBackgroundVisibility(.hidden)
            }
        }
        #endif
        .fleetWindowToolbarChrome()
        .fleetMacScreenSizing()
        .fleetDismissPresentationsOnNavigation { showingAddMiner = false }
        .onChange(of: externalPresentationResetID) { _, requestID in
            #if os(macOS)
            FleetMacNavigationTrace.record("owner.externalReset")
            #endif
            detailPresentationResetID = requestID
        }
    }

    /// Selecting a destination also returns to its root, including reselecting
    /// Overview after opening a miner card in the detail NavigationStack.
    private func activateSidebarDestination(_ destination: FleetSidebarDestination) {
        #if os(macOS)
        FleetMacNavigationTrace.record("owner.sidebarActivation", "destination=\(destination)")
        #endif
        // Activation is an event, not a selection-value change. Binding propagation
        // may coalesce a repeated value before a custom setter observes it.
        detailPresentationResetID = UUID()
        showingAddMiner = false
        fleetPath = NavigationPath()
        sidebarSelection = destination
    }

    /// The existing workspace owns all three bindings. Do not also dismiss from the
    /// child or broadcast an external Open Fleet intent, which reopens this window.
    private func completeBulkAdd() {
        showingAddMiner = false
        if !fleetPath.isEmpty { fleetPath = NavigationPath() }
        if sidebarSelection != .overview { sidebarSelection = .overview }
    }

    private func refreshFleet() async {
        insights.setDemo(store.isDemo)
        if store.preferences.externalDataEnabled {
            async let minerRefresh: Void = store.refresh()
            async let insightsRefresh: Void = insights.refresh(force: true)
            _ = await (minerRefresh, insightsRefresh)
        } else {
            await store.refresh()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch sidebarSelection ?? .overview {
        case .overview:
            DashboardView(
                store: store,
                insights: insights,
                coordinator: coordinator,
                startupReady: startupReady,
                onToggleSidebar: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        columnVisibility = columnVisibility == .all ? .detailOnly : .all
                    }
                }
            )
            .fleetDesktopBranding(
                sidebarVisible: columnVisibility != .detailOnly,
                includesPrincipalBrand: false
            )
        case .miner(let deviceID):
            MinerDetailDestinationView(deviceID: deviceID, store: store, insights: insights)
                .fleetDesktopBranding(sidebarVisible: columnVisibility != .detailOnly)
        case .network:
            NetworkInsightsView(fleet: store, insights: insights)
                .fleetDesktopBranding(sidebarVisible: columnVisibility != .detailOnly)
        case .energy:
            FleetEnergyView(store: store)
                .fleetDesktopBranding(sidebarVisible: columnVisibility != .detailOnly)
        case .achievements:
            MiningAchievementsView(devices: FleetReleaseFeatures.visibleDevices(store.isDemo ? store.savedDevices : store.devices))
                .fleetDesktopBranding(sidebarVisible: columnVisibility != .detailOnly)
        case .reports:
            FleetReportView(store: store)
                .fleetDesktopBranding(sidebarVisible: columnVisibility != .detailOnly)
        case .backup:
            FleetBackupView(store: store)
                .fleetDesktopBranding(sidebarVisible: columnVisibility != .detailOnly)
        case .monitoring:
            if let coordinator {
                MonitoringSettingsView(
                    store: store,
                    coordinator: coordinator,
                    usesWorkspacePath: true,
                    onPreviewCelebration: onPreviewCelebration
                )
                .fleetDesktopBranding(sidebarVisible: columnVisibility != .detailOnly)
            } else {
                ContentUnavailableView(
                    "Monitoring Unavailable",
                    systemImage: "bell.slash",
                    description: Text("Glance coordinator is not configured.")
                )
            }
        case .preferences:
            FleetPreferencesView(
                preferences: store.preferences,
                store: store,
                onPreviewCelebration: onPreviewCelebration
            )
            .fleetDesktopBranding(sidebarVisible: columnVisibility != .detailOnly)
        case .about:
            AboutView(store: store)
                .fleetDesktopBranding(sidebarVisible: columnVisibility != .detailOnly)
        case .support:
            DeveloperSupportView()
                .fleetDesktopBranding(sidebarVisible: columnVisibility != .detailOnly)
        }
    }
}
