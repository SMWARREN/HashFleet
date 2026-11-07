import SwiftUI
import AppKit
import HashFleetCore

/// The Mac product is a macOS executable. Its workspace and status item share this one store
/// and process. No UIKit application, wrapper, helper executable, or LaunchAgent is involved.
@main
struct HashFleetApp: App {
    @NSApplicationDelegateAdaptor(FleetMacAppDelegate.self) private var appDelegate
    @State var store: FleetStore
    @State var glanceCoordinator: FleetGlanceCoordinator
    @State private var runtime: FleetMacRuntime
    @State var insights = MiningInsightsStore()
    @State var selectedTab = 0
    @AppStorage("sidebarSelectionID") var restoredSidebarSelectionID: String?
    @State var navigation = FleetMacNavigationState()
    var fleetPath: NavigationPath {
        get { navigation.fleetPath }
        nonmutating set { navigation.fleetPath = newValue }
    }
    @State var showsStartup = false
    @State var celebrations = FleetCelebrationQueue()
    var celebration: FleetCelebration? { celebrations.current }
    var sidebarSelection: FleetSidebarDestination? {
        get { navigation.sidebarSelection }
        nonmutating set { navigation.sidebarSelection = newValue }
    }
    @State var presentationResetID = UUID()
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let isTesting: Bool

    init() {
        let runtime = FleetMacRuntime()
        self.isTesting = runtime.isTesting
        _runtime = State(initialValue: runtime)
        _store = State(initialValue: runtime.store)
        _glanceCoordinator = State(initialValue: runtime.glanceCoordinator)
    }

    var body: some Scene {
        Window("Hash Fleet", id: "fleet") {
            ZStack {
                mainTabs
                    .fleetFont(.body)
                    .labeledContentStyle(FleetSettingsValueStyle())
                    .tint(FleetTheme.accent)
                    .accentColor(FleetTheme.accent)
                    .foregroundStyle(FleetTheme.ink)
                    .background(FleetTheme.canvas.ignoresSafeArea())
                    .fleetWindowToolbarChrome()
                notificationLayer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(store.preferences.appearance.colorScheme)
            .environment(\.fleetPresentationResetID, presentationResetID)
            .background(FleetMacWindowAccessor { window, openWindow in
                appDelegate.mainWindow = window
                FleetMacChrome.configure(window)
                appDelegate.openWorkspace = { openWindow(id: "fleet") }
            })
            .onAppear {
                restoreSceneStateIfPossible()
                insights.setDemo(store.isDemo)
                appDelegate.configure(runtime: runtime, openDestination: select)
                runtime.presentInAppNotification = presentInAppNotification
                runtime.start()
                presentUITestCelebrationIfRequested()
                presentUITestInAppAlertIfRequested()
            }
            .onChange(of: store.isDemo) { _, demo in insights.setDemo(demo) }
            .onChange(of: store.preferences.externalDataEnabled) { _, enabled in
                if !enabled { insights.clearPublicData() }
            }
            .onChange(of: sidebarSelection) { _, destination in
                if !isTesting { restoredSidebarSelectionID = destination?.id }
            }
            .onOpenURL { url in
                guard ["hashfleet", "hashfleet"].contains(url.scheme ?? ""), url.host == "fleet" else { return }
                select(.overview)
            }
            .onReceive(NotificationCenter.default.publisher(for: FleetSystemNavigation.requested)) { _ in
                FleetMacNavigationTrace.record("systemNavigation.received")
                openPendingFleetDestination()
                FleetMacNavigationTrace.record("systemNavigation.showMainWindow")
                appDelegate.showMainWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: FleetNotificationRoute.requested)) { _ in
                openPendingMinerRoute()
                appDelegate.showMainWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: FleetCelebrationPreview.requested)) { note in
                if let kind = FleetCelebrationPreview.kind(from: note) { presentPreviewCelebration(kind) }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                openPendingFleetDestination()
                openPendingMinerRoute()
                if !isTesting {
                    FleetLocalNotifications.clearBadge()
                    FleetNotificationDelivery.replayUndeliveredSystemNotifications(
                        from: store, isActive: true, presentInApp: presentInAppNotification)
                }
            }
            .alert("Local storage", isPresented: Binding(
                get: { store.persistenceError != nil },
                set: { if !$0 { store.persistenceError = nil } }
            )) {
                Button("OK") { store.persistenceError = nil }
            } message: { Text(store.persistenceError ?? "") }
        }
        .defaultSize(width: 1280, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Show Hash Fleet") { appDelegate.showMainWindow() }
                    .keyboardShortcut("0", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { select(.monitoring) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Hash Fleet") { select(.about) }
                Button("Support Hash Fleet…") { select(.support) }
            }
            CommandMenu("Fleet") {
                Button("Refresh Fleet Data") { Task { await store.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Delete All Miners…") {
                    appDelegate.showMainWindow()
                    confirmDeleteAllFromMenu()
                }
                .disabled(store.isDemo || store.devices.isEmpty)
                Divider()
                Button("Fleet Overview") { select(.overview) }.keyboardShortcut("1", modifiers: .command)
                Button("Fleet Reports") { select(.reports) }.keyboardShortcut("2", modifiers: .command)
                Button("Mining Insights") { select(.network) }.keyboardShortcut("3", modifiers: .command)
                Button("Fleet Energy") { select(.energy) }.keyboardShortcut("4", modifiers: .command)
                Button("Fleet Achievements") { select(.achievements) }.keyboardShortcut("5", modifiers: .command)
            }
        }
    }

    private func confirmDeleteAllFromMenu() {
        let count = store.devices.count
        let alert = NSAlert()
        alert.messageText = "Delete all \(count) miners?"
        alert.informativeText = "This removes every miner and its saved history from Hash Fleet. The miners themselves are not changed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All Miners").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        navigation.select(.overview)
        store.removeAllMiners()
    }

    private func select(_ destination: FleetSidebarDestination) {
        navigation.select(destination)
        selectedTab = 0
        appDelegate.showMainWindow()
    }
}

@MainActor
final class FleetMacAppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?
    var openWorkspace: (@MainActor () -> Void)?
    private var runtime: FleetMacRuntime?
    private var statusController: FleetMacStatusItemController?

    func configure(runtime: FleetMacRuntime, openDestination: @escaping @MainActor (FleetSidebarDestination) -> Void) {
        guard self.runtime == nil else { return }
        self.runtime = runtime
        statusController = FleetMacStatusItemController(runtime: runtime, openDestination: openDestination)
    }

    func showMainWindow() {
        // Closing a SwiftUI Window retires its scene. Reopen that scene instead of
        // ordering a cached AppKit window whose SwiftUI content has been detached.
        if let openWorkspace {
            openWorkspace()
        } else {
            mainWindow?.makeKeyAndOrderFront(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        runtime?.stop()
        statusController?.stop()
        guard runtime?.isTesting == false else { return .terminateNow }
        Task { @MainActor in
            await MinerTelemetryDatabase.shared.flushReadings()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct FleetMacWindowAccessor: NSViewRepresentable {
    @Environment(\.openWindow) private var openWindow
    let onWindow: @MainActor (NSWindow, OpenWindowAction) -> Void

    func makeNSView(context: Context) -> WindowReader {
        let reader = WindowReader()
        reader.onWindow = { window in onWindow(window, openWindow) }
        return reader
    }

    func updateNSView(_ nsView: WindowReader, context: Context) {
        nsView.onWindow = { window in onWindow(window, openWindow) }
        if let window = nsView.window { onWindow(window, openWindow) }
    }

    final class WindowReader: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isReleasedWhenClosed = false
            onWindow?(window)
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            if let window { onWindow?(window) }
        }
    }
}
