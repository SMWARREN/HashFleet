import SwiftUI
import HashFleetCore

extension HashFleetApp {
    @ViewBuilder
    var notificationLayer: some View {
        ZStack(alignment: .top) {
            if let current = celebration {
                FleetCelebrationView(
                    celebration: current,
                    onViewMiner: { openMiner(current.deviceID, dismissCelebration: true) },
                    onDismiss: dismissCelebration,
                    onDisableSessionBestAlerts: sessionBestOptOutAction,
                    onSupport: celebrationSupportAction
                )
                .id(current.id)
                .transition(.opacity)
            } else {
                FleetInAppAlertOverlay(
                    center: FleetInAppAlertCenter.shared,
                    reconnectingDeviceIDs: store.reconnectingDeviceIDs
                ) { openMiner($0, dismissCelebration: true) }
            }
        }
        .tint(FleetTheme.accent)
        .fleetMacScreenSizing()
    }

    func openPendingFleetDestination() {
        guard FleetSystemNavigation.consume() else { return }
        #if os(macOS)
        FleetMacNavigationTrace.record("systemNavigation.consumed", "pathCount=\(fleetPath.count)")
        #endif
        fleetPath = NavigationPath()
        selectedTab = 0
        sidebarSelection = .overview
    }

    func openPendingMinerRoute() {
        guard let route = FleetNotificationRoute.consume() else { return }
        openMiner(route.deviceID, dismissCelebration: false)
        if let routed = route.celebration {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { celebrations.present(routed) }
        }
    }

    func openMiner(_ deviceID: UUID, dismissCelebration shouldDismiss: Bool) {
        if shouldDismiss { dismissCelebration() }
        // Clear the owning SwiftUI bindings before changing a navigation stack beneath a sheet.
        // UIKit-only dismissal leaves those bindings true and can bring the sheet back.
        let requestID = UUID()
        presentationResetID = requestID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 350))
            guard presentationResetID == requestID else { return }
            selectedTab = 0
            sidebarSelection = .miner(deviceID)
            var path = NavigationPath()
            path.append(FleetMinerRoute(deviceID: deviceID))
            fleetPath = path
        }
    }

    /// Optional support never discards queued miner records or redirects straight to checkout.
    func openSupportFromCelebration() {
        guard celebrations.pending.isEmpty else { return }
        dismissCelebration()
        let requestID = UUID()
        presentationResetID = requestID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 350))
            guard !Task.isCancelled, presentationResetID == requestID else { return }
            selectedTab = 0
            #if os(macOS)
            fleetPath = NavigationPath()
            sidebarSelection = .support
            #else
            // Keep the regular-layout sidebar stable so its selection reset cannot erase
            // the new path. Both compact and regular stacks register this internal route.
            var path = NavigationPath()
            path.append(FleetSupportRoute.page)
            fleetPath = path
            #endif
        }
    }

    /// Delivery has already applied preferences and claimed the journal entry exactly once.
    /// Session records use the same persistent artwork as all-time records, never a toast.
    func presentInAppNotification(_ event: FleetNotificationEvent) {
        if let next = FleetCelebration(event) {
            // Delivery may have claimed an event just before the popup's opt-out was tapped.
            guard next.kind != .bestShareSession || store.preferences.sessionBestNotificationsEnabled else { return }
            celebrations.present(next)
        } else {
            FleetInAppAlertCenter.shared.present(FleetInAppAlert(event))
        }
    }

    func dismissCelebration() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { celebrations.dismiss() }
    }

    func disableSessionBestAlerts() {
        store.preferences.sessionBestNotificationsEnabled = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            celebrations.removeSessionBests()
        }
    }

    private var celebrationSupportAction: (() -> Void)? {
        guard celebrations.pending.isEmpty else { return nil }
        return { openSupportFromCelebration() }
    }

    private var sessionBestOptOutAction: (() -> Void)? {
        guard store.preferences.sessionBestNotificationsEnabled else { return nil }
        return { disableSessionBestAlerts() }
    }

    func restoreSceneStateIfPossible() {
        guard !isTesting,
              let restoredID = restoredSidebarSelectionID,
              let destination = FleetSidebarDestination(restorationID: restoredID) else { return }
        sidebarSelection = destination
    }

    func presentUITestCelebrationIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing") || arguments.contains("--demo"),
              let flag = arguments.first(where: { $0.hasPrefix("--ui-test-celebration=") }) else { return }
        Task { @MainActor in
            await waitForUITestNotificationDelay()
            let kind: FleetCelebration.Kind = flag.hasSuffix("block") ? .blockFound
                : flag.hasSuffix("session") ? .bestShareSession : .bestShareAllTime
            presentPreviewCelebration(kind)
        }
    }

    func presentUITestInAppAlertIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"), arguments.contains("--ui-test-in-app-alert"),
              let device = store.visibleDevices.first else { return }
        Task { @MainActor in
            await waitForUITestNotificationDelay()
            FleetInAppAlertCenter.shared.present(FleetInAppAlert(.stateChange(MinerStateChangeEvent(
                deviceID: device.id, minerName: device.name, kind: .offline,
                detail: "Sample outage for testing", occurredAt: .now))))
        }
    }

    private func waitForUITestNotificationDelay() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing") else { return }
        guard
              let flag = arguments.first(where: { $0.hasPrefix("--ui-test-notification-delay=") }),
              let seconds = Double(flag.split(separator: "=").last ?? ""),
              seconds.isFinite, seconds > 0 else {
            // Give the scene anchor one layout pass before an immediate synthetic alert.
            try? await Task.sleep(for: .milliseconds(500))
            return
        }
        try? await Task.sleep(for: .seconds(min(seconds, 30)))
    }

    func presentPreviewCelebration(_ kind: FleetCelebration.Kind) {
        let device = store.visibleDevices.first
        let isBlock = kind == .blockFound
        let name = device?.name ?? "Your miner"
        let bestKey = kind == .bestShareSession ? "bestSessionDiff" : "bestDiff"
        let bestValue = device.flatMap { store.snapshots[$0.id]?.info?.raw[bestKey]?.stringValue }
            ?? (kind == .bestShareSession ? "9.20M" : "392.00M")
        let preview = FleetCelebration(
            kind: kind,
            deviceID: device?.id ?? UUID(),
            minerName: name,
            value: isBlock ? "912,345" : bestValue,
            detail: isBlock ? "Preview: this is what a found block looks like"
                : kind == .bestShareSession ? "Preview: a new session best, not a solved block"
                : "Preview: this is what a new high score looks like"
        )
        var mutablePreview = preview
        mutablePreview.viewMinerAvailable = device != nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
            celebrations.present(mutablePreview)
        }
    }

    @ViewBuilder var mainTabs: some View {
        #if os(macOS)
        FleetSplitView(
            store: store,
            insights: insights,
            coordinator: glanceCoordinator,
            startupReady: !showsStartup,
            fleetPath: $navigation.fleetPath,
            sidebarSelection: $navigation.sidebarSelection,
            onPreviewCelebration: presentPreviewCelebration
        )
        #else
        FleetAdaptiveWorkspace {
            FleetSplitView(
                store: store,
                insights: insights,
                coordinator: glanceCoordinator,
                startupReady: !showsStartup,
                fleetPath: $fleetPath,
                sidebarSelection: $sidebarSelection,
                onPreviewCelebration: presentPreviewCelebration
            )
        } compact: {
            fleetNavigation
        }
        #endif
    }

    var fleetNavigation: some View {
        NavigationStack(path: fleetNavigationPathBinding) {
            DashboardView(store: store, insights: insights, coordinator: glanceCoordinator,
                          startupReady: !showsStartup)
                .navigationDestination(for: FleetMinerRoute.self) { route in
                    MinerDetailDestinationView(deviceID: route.deviceID, store: store, insights: insights)
                }
                .navigationDestination(for: FleetSupportRoute.self) { _ in
                    DeveloperSupportView()
                        .environment(\.fleetStandalonePage, false)
                }
        }
    }

    private var fleetNavigationPathBinding: Binding<NavigationPath> {
        #if os(macOS)
        $navigation.fleetPath
        #else
        $fleetPath
        #endif
    }

    var aboutNavigation: some View {
        NavigationStack { AboutView(store: store) }
    }
}

#if os(iOS)
/// Scene traits are supplied to views inside the window, not to the App value itself.
private struct FleetAdaptiveWorkspace<Regular: View, Compact: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let regular: Regular
    let compact: Compact

    init(@ViewBuilder regular: () -> Regular, @ViewBuilder compact: () -> Compact) {
        self.regular = regular()
        self.compact = compact()
    }

    var body: some View {
        if horizontalSizeClass == .regular || FleetLayout.isMac {
            regular
        } else {
            compact
        }
    }
}
#endif

struct MonitoringIdentity: Equatable {
    let phase: ScenePhase
    let deviceIDs: [UUID]
    let isDemo: Bool
    let realtimeMonitoring: Bool
}

struct GlancePublishingIdentity: Equatable {
    let phase: ScenePhase
    let glance: FleetGlance
    var menuBarSnapshot: FleetMenuBarSnapshot?
}

extension FleetSidebarDestination {
    init?(restorationID: String) {
        switch restorationID {
        case "overview": self = .overview
        case "network": self = .network
        case "energy": self = .energy
        case "achievements": self = .achievements
        case "reports": self = .reports
        case "backup": self = .backup
        case "monitoring": self = .monitoring
        case "preferences": self = .preferences
        case "about": self = .about
        case "support": self = .support
        default:
            if restorationID.hasPrefix("miner-"),
               let uuid = UUID(uuidString: String(restorationID.dropFirst(6))) {
                self = .miner(uuid)
            } else {
                return nil
            }
        }
    }
}
