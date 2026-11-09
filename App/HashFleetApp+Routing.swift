import SwiftUI
import HashFleetCore

extension HashFleetApp {
    @ViewBuilder
    var notificationLayer: some View {
        ZStack(alignment: .top) {
            if let current = celebration {
                FleetCelebrationView(
                    celebration: current,
                    onViewMiner: { openMiner(current.deviceID, dismissCelebration: true, expectedCelebrationID: current.id) },
                    onDismiss: { dismissCelebration(expectedID: current.id) },
                    onDisableSessionBestAlerts: sessionBestOptOutAction,
                    onSupport: celebrationSupportAction,
                    pendingCount: previewCelebration == nil ? celebrations.pendingCount : 0,
                    onReviewLater: previewCelebration == nil ? { pauseCelebrations(expectedID: current.id) } : nil
                )
                .id(current.id)
                .transition(.opacity)
            } else {
                FleetInAppAlertOverlay(
                    center: FleetInAppAlertCenter.shared,
                    reconnectingDeviceIDs: store.reconnectingDeviceIDs
                ) { openMiner($0, dismissCelebration: false) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            celebrationQueueControls
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .onAppear {
            celebrations.submit(.refresh)
            reconcileCelebrationSessionPreference()
        }
        .onChange(of: store.preferences.sessionBestNotificationsEnabled) { _, _ in
            reconcileCelebrationSessionPreference()
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
        guard let route = FleetNotificationRoute.pending() else { return }
        if let routed = route.celebration,
           routed.kind != .bestShareSession || store.preferences.sessionBestNotificationsEnabled {
            celebrations.submit(.present(routed, sessionEnabled: store.preferences.sessionBestNotificationsEnabled)) { result in
                // A newer tap must not be consumed or redirected by this older write.
                guard FleetNotificationRoute.pending() == route else { return }
                if result.accepted { _ = FleetNotificationRoute.consume() } else { hiddenCelebrationID = celebrations.current?.id }
                openMiner(route.deviceID, dismissCelebration: false)
            }
            return
        }
        // A failed durable handoff leaves the original tap payload available for retry.
        _ = FleetNotificationRoute.consume()
        openMiner(route.deviceID, dismissCelebration: false)
    }

    func openMiner(_ deviceID: UUID, dismissCelebration shouldDismiss: Bool, expectedCelebrationID: UUID? = nil) {
        if let expectedCelebrationID, celebration?.id != expectedCelebrationID { return }
        if shouldDismiss, celebration != nil {
            // Old transitioning views cannot acknowledge a different, unseen queue head.
            if previewCelebration != nil {
                previewCelebration = nil
            } else {
                guard let id = celebrations.current?.id else { return }
                celebrations.submit(.acknowledgeAndPause(id)) { result in
                    guard !result.staleAction else { return }
                    hiddenCelebrationID = result.accepted ? nil : id
                    navigateToMiner(deviceID)
                }
                return
            }
        }
        navigateToMiner(deviceID)
    }

    private func navigateToMiner(_ deviceID: UUID) {
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
        guard celebrations.pendingCount == 0 else { return }
        dismissCelebration { navigateToSupport() }
    }

    private func navigateToSupport() {
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

    /// Legacy void callback for callers without durable handoff acknowledgement.
    /// App delivery uses acceptInAppNotification so failed storage remains retryable.
    /// Session records use the same persistent artwork as all-time records, never a toast.
    func presentInAppNotification(_ event: FleetNotificationEvent) {
        _ = acceptInAppNotification(event)
    }

    /// Record handoffs remain pending in the journal until the asynchronous pump commits them.
    /// Safety alerts are still immediate and do not wait behind a blocked SQLite transaction.
    func acceptInAppNotification(_ event: FleetNotificationEvent) -> Bool {
        if FleetCelebration(event) != nil { return false }
        FleetInAppAlertCenter.shared.present(FleetInAppAlert(event))
        return true
    }

    func commitInAppRecord(_ event: FleetNotificationEvent) async -> Bool {
        guard let next = FleetCelebration(event) else { return false }
        let result = await celebrations.submit(.present(next,
            sessionEnabled: store.preferences.sessionBestNotificationsEnabled)).value
        return result.accepted
    }

    func scheduleRecordAcceptance() {
        FleetNotificationDelivery.schedulePendingRecordAcceptances(from: store, accept: commitInAppRecord)
    }

    func pauseCelebrations(expectedID: UUID? = nil) {
        if let expectedID, celebration?.id != expectedID { return }
        guard let id = celebrations.current?.id else { return }
        celebrations.submit(.pause(id)) { result in
            guard !result.staleAction else { return }
            hiddenCelebrationID = result.accepted ? nil : id
        }
    }

    func resumeCelebrations() {
        celebrations.submit(.resume(sessionEnabled: store.preferences.sessionBestNotificationsEnabled)) { result in
            if result.accepted { hiddenCelebrationID = nil }
        }
    }

    @ViewBuilder
    private var celebrationQueueControls: some View {
        VStack(spacing: 8) {
            if (celebrations.isPaused || hiddenCelebrationID != nil) && celebrations.unacknowledgedCount > 0 {
                Button(action: resumeCelebrations) {
                    Label("Review records (\(celebrations.unacknowledgedCount) waiting)", systemImage: "trophy")
                        .fleetFont(.subheadline, weight: .semibold)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("celebration.queue.resume")
                .accessibilityValue("\(celebrations.unacknowledgedCount)")
                .accessibilityHint("Resumes the oldest unacknowledged record first.")
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: FleetNotificationHitRegions.self,
                            value: [geometry.frame(in: .named(FleetNotificationHitRegions.coordinateSpace))])
                    }
                }
            }
            if let error = celebrations.storageError {
                Text(error)
                    .fleetFont(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("celebration.queue.storageError")
            }
        }
    }

    func dismissCelebration(expectedID: UUID? = nil, completion: (() -> Void)? = nil) {
        if let expectedID, celebration?.id != expectedID { return }
        if previewCelebration != nil {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { previewCelebration = nil }
            completion?()
        } else if let id = celebrations.current?.id {
            celebrations.submit(.dismiss(id)) { result in
                guard !result.staleAction else { return }
                hiddenCelebrationID = result.accepted ? nil : id
                completion?()
            }
        }
    }

    func disableSessionBestAlerts() {
        // The preference expresses user intent even while presentation storage is unavailable.
        store.preferences.sessionBestNotificationsEnabled = false
        reconcileCelebrationSessionPreference()
        if previewCelebration?.kind == .bestShareSession { previewCelebration = nil }
    }

    func reconcileCelebrationSessionPreference() {
        guard !store.preferences.sessionBestNotificationsEnabled else { return }
        celebrations.submit(.removeSessionBests) { result in
            if !result.accepted { hiddenCelebrationID = celebrations.current?.id }
        }
    }

    private var celebrationSupportAction: (() -> Void)? {
        guard celebrations.pendingCount == 0 else { return nil }
        let shownID = celebration?.id
        return {
            guard celebration?.id == shownID else { return }
            openSupportFromCelebration()
        }
    }

    private var sessionBestOptOutAction: (() -> Void)? {
        guard store.preferences.sessionBestNotificationsEnabled else { return nil }
        let shownID = celebration?.id
        return {
            guard celebration?.id == shownID else { return }
            disableSessionBestAlerts()
        }
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
            previewCelebration = mutablePreview
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
