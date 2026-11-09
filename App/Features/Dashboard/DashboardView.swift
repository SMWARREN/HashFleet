import SwiftUI
import HashFleetCore
import LucideSwift

enum DashboardPageDestination: Equatable {
    case overview
    case miner(UUID)
    case settings
    case about
    case support
    case featureTour
    case energy
    case network
    case reports
    case backup
    case achievements
}

struct DashboardView: View {
    @Environment(\.fleetGuidedDemo) private var guidedDemo
    let store: FleetStore
    let insights: MiningInsightsStore
    var coordinator: FleetGlanceCoordinator?
    var startupReady: Bool
    var onToggleSidebar: (() -> Void)?
    @State var showingAddMiner = false
    @State var showingSettings = false
    @State var showingAbout = false
    @State var showingSupport = false
    @State var showingFeatureTour = false
    @State var showingSideMenu = false
    @State var showingEnergy = false
    @State var showingNetwork = false
    @State var showingReports = false
    @State var showingBackup = false
    @State var selectedMinerRoute: MinerDevice?
    @State var minerToRemove: MinerDevice?
    @State var searchText = ""
    @State var showsSearch = false
    @FocusState var searchIsFocused: Bool
    @State var showingAchievements = false
    @State var minerExpansion: [UUID: Bool] = [:]
    @AppStorage("dashboard.responsiveColumnLimit") var macMinerColumns = 0
    @State var minerSettingsRoute: DashboardMinerSettingsRoute?
    @State var minerTuningSessionDevice: MinerDevice?
    @State var minerXMRigControlDevice: MinerDevice?
    @State private var pendingPageDestination: DashboardPageDestination?
    @State private var appearanceToggle = 0
    @State var confirmingDeleteAll = false
    /// Tour previews finish their lesson before showing a celebration. Settings previews and
    /// real notification celebrations preserve the current screen under the app-wide window.
    @State private var pendingCelebrationPreview: FleetCelebration.Kind?
    @Namespace var minerTransitionNamespace
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOver
    @Environment(\.scenePhase) private var scenePhase

    init(
        store: FleetStore,
        insights: MiningInsightsStore = MiningInsightsStore(),
        coordinator: FleetGlanceCoordinator? = nil,
        startupReady: Bool = true,
        onToggleSidebar: (() -> Void)? = nil
    ) {
        self.store = store
        self.insights = insights
        self.coordinator = coordinator
        self.startupReady = startupReady
        self.onToggleSidebar = onToggleSidebar
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                dashboardContent(viewport: viewport)
            }
            .coordinateSpace(name: "dashboardScroll")
            .background(FleetTheme.canvas)
            .foregroundStyle(FleetTheme.ink)
            .fleetAppNavigation { $0.navigationTitle(FleetLayout.isMac ? "Overview" : "Hash Fleet") }
            .fleetPerformanceScreen("Fleet")
            .confirmationDialog(
                "Delete all \(store.devices.count) miners?",
                isPresented: $confirmingDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete all miners", role: .destructive) { store.removeAllMiners() }
                    .accessibilityIdentifier("dashboard.confirmDeleteAllMiners")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every miner and its saved history from Hash Fleet. The miners themselves are not changed.")
            }
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityAction(named: Text("Find a miner")) {
                showsSearch = true
                searchIsFocused = true
            }
            #if os(macOS)
            .fleetWindowToolbarChrome()
            #else
            .toolbarBackground(FleetTheme.canvas, for: FleetToolbarLocation.bar)
            #endif
            .toolbar { if !guidedDemo { dashboardToolbar } }
            .tint(FleetTheme.accent)
            .fleetDismissPresentationsOnNavigation {
                pendingCelebrationPreview = nil
                showingAddMiner = false
                showingSettings = false
                showingAbout = false
                showingSupport = false
                showingFeatureTour = false
                showingSideMenu = false
                showingEnergy = false
                showingNetwork = false
                showingReports = false
                showingBackup = false
                showingAchievements = false
                selectedMinerRoute = nil
                minerSettingsRoute = nil
                minerTuningSessionDevice = nil
                minerXMRigControlDevice = nil
                minerToRemove = nil
                pendingPageDestination = nil
            }
            .refreshable { await refreshDashboard() }
            // All alert presentation and feedback is app-wide, including while sheets are open.
            .fleetPagePresentation(isPresented: $showingAddMiner) {
                AddMinerView(store: store, onBulkAddSuccess: { showingAddMiner = false })
                    .fleetPageSheet()
            }
            .fleetPagePresentation(isPresented: $showingAchievements) {
                FleetPageNavigationStack {
                    MiningAchievementsView(devices: FleetReleaseFeatures.visibleDevices(store.isDemo ? store.savedDevices : store.devices))
                }
                .fleetPageSheet()
            }
            .fleetPagePresentation(isPresented: $showingSettings, content: {
                if let coordinator {
                    FleetPageNavigationStack {
                        MonitoringSettingsView(
                            store: store,
                            coordinator: coordinator,
                            onPreviewCelebration: { kind in
                                // The notification window sits above sheets. Keep Settings and
                                // its current scroll position underneath the illustrated popup.
                                FleetCelebrationPreview.request(kind: kind)
                            }
                        )
                    }
                    .fleetPageSheet()
                }
            })
            .onChange(of: startupReady, initial: true) { _, ready in
                let arguments = ProcessInfo.processInfo.arguments
                let isTesting = arguments.contains("--ui-testing") ||
                    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                guard !guidedDemo, ready, !isTesting || arguments.contains("--show-feature-tour"),
                      store.preferences.shouldShowFeatureTour else { return }
                showingFeatureTour = true
            }
            .fleetPagePresentation(isPresented: $showingFeatureTour, onDismiss: {
                store.preferences.hasSeenFeatureTour = true
                flushPendingCelebrationPreview()
            }, content: {
                FleetPageNavigationStack {
                    FleetTourView(
                        dontShowAgain: Binding(
                            get: { store.preferences.suppressFeatureTour },
                            set: { store.preferences.suppressFeatureTour = $0 }
                        ),
                        onPreviewCelebration: { kind in
                            // Finish this tour lesson before requesting its celebration preview.
                            // Unlike Settings previews, this intentionally closes the tour.
                            pendingCelebrationPreview = kind
                            showingFeatureTour = false
                        }
                    )
                }
                .fleetPageSheet()
            })
            .fleetPagePresentation(isPresented: $showingAbout) {
                FleetPageNavigationStack {
                    AboutView(store: store)
                }
                .fleetPageSheet()
            }
            .fleetPagePresentation(isPresented: $showingSupport) {
                FleetPageNavigationStack { DeveloperSupportView() }
                    .fleetPageSheet()
            }
            .fleetPagePresentation(isPresented: $showingSideMenu) {
                FleetPageNavigationStack {
                    FleetSidebarView(
                        selection: Binding(
                            get: { nil },
                            set: { dest in
                                guard let dest else { return }
                                switch dest {
                                case .overview:
                                    routeToDashboardPage(.overview)
                                case .miner(let id):
                                    routeToDashboardPage(.miner(id))
                                case .network:
                                    routeToDashboardPage(.network)
                                case .energy:
                                    routeToDashboardPage(.energy)
                                case .achievements:
                                    routeToDashboardPage(.achievements)
                                case .reports:
                                    routeToDashboardPage(.reports)
                                case .backup:
                                    routeToDashboardPage(.backup)
                                case .monitoring, .preferences:
                                    routeToDashboardPage(.settings)
                                case .about:
                                    routeToDashboardPage(.about)
                                case .support:
                                    routeToDashboardPage(.support)
                                }
                            }
                        ),
                        store: store,
                        insights: insights,
                        showingAddMiner: $showingAddMiner,
                        onRefresh: {
                            Task { await refreshDashboard() }
                        }
                    )
                    .navigationTitle("Fleet Menu")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingSideMenu = false }
                        }
                    }
                }
                .fleetPageSheet()
            }
            .fleetPagePresentation(isPresented: $showingEnergy) {
                FleetPageNavigationStack {
                    FleetEnergyView(store: store)
                }
                .fleetPageSheet()
            }
            .fleetPagePresentation(isPresented: $showingNetwork) {
                FleetPageNavigationStack {
                    NetworkInsightsView(fleet: store, insights: insights)
                }
                .fleetPageSheet()
            }
            .fleetPagePresentation(isPresented: $showingReports) {
                FleetPageNavigationStack {
                    FleetReportView(store: store)
                }
                .fleetPageSheet()
            }
            .fleetPagePresentation(isPresented: $showingBackup) {
                FleetPageNavigationStack {
                    FleetBackupView(store: store)
                }
                .fleetPageSheet()
            }
            .fleetAppNavigation { base in
                base.navigationDestination(item: $selectedMinerRoute) { device in
                    MinerDetailView(
                        device: device,
                        store: store,
                        insights: insights,
                        liveConnectionError: store.liveConnectionErrors[device.id],
                        isLive: store.liveConnectedDeviceIDs.contains(device.id)
                    )
                }
                .navigationDestination(item: $minerTuningSessionDevice) { device in
                    MinerTuningSessionView(device: device, store: store, insights: insights)
                }
                .navigationDestination(item: $minerXMRigControlDevice) { device in
                    XMRigControlView(device: device, store: store)
                }
                .navigationDestination(item: $minerSettingsRoute) { route in
                    // Keep the physical iOS 26 route metadata shallow. The dashboard already erases
                    // its nested miner-card layout for the same runtime, and Pools is the largest
                    // settings destination reached directly from that layout.
                    AnyView(
                        MinerSettingsView(
                            device: route.device,
                            store: store,
                            insights: insights,
                            initialCategory: route.category
                        )
                    )
                }
            }
            .onChange(of: store.preferences.compactCards) { _, _ in
                // An explicit app preference change becomes the new baseline, never a side effect of a card tap.
                minerExpansion.removeAll()
            }
            .alert("Remove miner?", isPresented: removeMinerAlertPresented) {
                Button("Cancel", role: .cancel) { minerToRemove = nil }
                Button("Remove", role: .destructive) {
                    if let minerToRemove { store.remove(minerToRemove) }
                    minerToRemove = nil
                }
            } message: {
                Text(
                    "This removes \(minerToRemove?.name ?? "the miner") from Hash Fleet. " +
                        "Your hardware and its settings are not changed."
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .principal) {
            if showsSearch {
                minerSearch
            } else {
                FleetMacToolbarBrand()
            }
        }
        .fleetUnadornedToolbarBackground()
        .fleetPersistentToolbarItem()
        #else
        ToolbarItem(placement: .principal) {
            if showsSearch {
                minerSearch
            } else {
                FleetHeaderTitle()
                    .accessibilityIdentifier("dashboard.title")
            }
        }
        .fleetUnadornedToolbarBackground()
        #endif
        brandToolbarItem
        if !showsSearch {
            ToolbarItem(placement: FleetToolbarLocation.trailing) {
                Menu {
                    Button {
                        routeToDashboardPage(.settings)
                    } label: {
                        Label("App settings", systemImage: "gearshape")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    .accessibilityIdentifier("dashboard.openSettings")
                    Button {
                        Task { await refreshDashboard() }
                    } label: {
                        Label("Refresh fleet", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    Button {
                        routeToDashboardPage(.about)
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("dashboard.openAbout")
                    Button {
                        routeToDashboardPage(.support)
                    } label: {
                        Label("Support Hash Fleet", systemImage: "heart")
                    }
                    .accessibilityIdentifier("dashboard.openSupport")
                    if !store.isDemo, !store.devices.isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            confirmingDeleteAll = true
                        } label: {
                            Label("Delete all miners…", systemImage: "trash")
                        }
                        .accessibilityIdentifier("dashboard.deleteAllMiners")
                    }
                    Divider()
                    Button {
                        store.preferences.appearance = colorScheme == .dark ? .light : .dark
                        appearanceToggle += 1
                    } label: {
                        Label(
                            colorScheme == .dark ? "Switch to light mode" : "Switch to dark mode",
                            systemImage: colorScheme == .dark ? "sun.max" : "moon"
                        )
                    }
                } label: {
                    settingsToolbarIcon
                        .foregroundStyle(FleetTheme.ink)
                        #if !os(macOS)
                        .frame(minWidth: 44, minHeight: 44)
                        #endif
                }
                .fleetToolbarMenu()
                .accessibilityLabel("App settings and preferences")
                .accessibilityValue(
                    store.preferences.appearance == .system
                        ? "System · \(colorScheme == .dark ? "Dark" : "Light")"
                        : store.preferences.appearance.title
                )
                .accessibilityIdentifier("dashboard.settingsMenu")
            }
            .fleetUnadornedToolbarBackground()
        }
        ToolbarItem(placement: FleetToolbarLocation.trailing) {
            Button {
                showingAddMiner = true
            } label: {
                Image(systemName: "plus")
                    .fleetFont(.body, weight: .semibold)
                    #if !os(macOS)
                    .frame(minWidth: 44, minHeight: 44)
                    #endif
            }
            .fleetToolbarButton()
            .accessibilityLabel("Add a miner")
            .accessibilityIdentifier("dashboard.addMiner")
            .keyboardShortcut("n", modifiers: .command)
        }
        .fleetUnadornedToolbarBackground()
    }

}

extension DashboardView {
    @ViewBuilder
    private var settingsToolbarIcon: some View {
        #if os(macOS)
        // AppKit menu labels need an image, rather than the mobile vector-view label.
        Image(systemName: "gearshape")
            .font(.system(size: 14, weight: .medium))
        #else
        LucideIcon(FleetIcon.settings, size: FleetLayout.iconSize(22))
        #endif
    }

    /// Settings previews return to the underlying workspace before presenting the app-wide
    /// celebration. Real monitoring events do not need to dismiss the user's current sheet.
    private func flushPendingCelebrationPreview() {
        guard let kind = pendingCelebrationPreview else { return }
        pendingCelebrationPreview = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            FleetCelebrationPreview.request(kind: kind)
        }
    }

    private var removeMinerAlertPresented: Binding<Bool> {
        Binding(
            get: { minerToRemove != nil },
            set: { isPresented in
                if !isPresented { minerToRemove = nil }
            }
        )
    }

    /// Menu actions use one route at a time. Clear every presentation binding first, then wait
    /// for SwiftUI to finish dismissal before opening the requested page. This prevents a stale
    /// sheet from reopening over the new destination on iPad and macOS.
    func routeToDashboardPage(_ destination: DashboardPageDestination) {
        let needsDismissal = showingAddMiner || showingSettings || showingAbout || showingSupport || showingFeatureTour
            || showingSideMenu || showingEnergy || showingNetwork || showingReports || showingBackup
            || showingAchievements || selectedMinerRoute != nil || minerSettingsRoute != nil
            || minerTuningSessionDevice != nil || minerToRemove != nil

        pendingPageDestination = destination
        clearDashboardPresentations()
        guard needsDismissal else {
            pendingPageDestination = nil
            presentDashboardPage(destination)
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 300))
            guard pendingPageDestination == destination else { return }
            pendingPageDestination = nil
            presentDashboardPage(destination)
        }
    }

    private func clearDashboardPresentations() {
        pendingCelebrationPreview = nil
        showingAddMiner = false
        showingSettings = false
        showingAbout = false
        showingSupport = false
        showingFeatureTour = false
        showingSideMenu = false
        showingEnergy = false
        showingNetwork = false
        showingReports = false
        showingBackup = false
        showingAchievements = false
        selectedMinerRoute = nil
        minerSettingsRoute = nil
        minerTuningSessionDevice = nil
        minerToRemove = nil
    }

    private func presentDashboardPage(_ destination: DashboardPageDestination) {
        switch destination {
        case .overview:
            break
        case .miner(let id):
            selectedMinerRoute = store.visibleDevices.first(where: { $0.id == id })
        case .settings:
            showingSettings = true
        case .about:
            showingAbout = true
        case .support:
            showingSupport = true
        case .featureTour:
            showingFeatureTour = true
        case .energy:
            showingEnergy = true
        case .network:
            showingNetwork = true
        case .reports:
            showingReports = true
        case .backup:
            showingBackup = true
        case .achievements:
            showingAchievements = true
        }
    }

    private func refreshDashboard() async {
        insights.setDemo(store.isDemo)
        if store.preferences.externalDataEnabled {
            async let minerRefresh: Void = store.refresh()
            async let insightsRefresh: Void = insights.refresh(force: true)
            _ = await (minerRefresh, insightsRefresh)
        } else {
            insights.clearPublicData()
            await store.refresh()
        }
    }
}

#Preview("Fleet · demo") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.preview")!)
    store.loadDemo()
    return NavigationStack { DashboardView(store: store) }
}
