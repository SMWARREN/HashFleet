import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Mock-driven evaluation of large dashboard, history, endpoint, custom JSON, and tip-jar surfaces.
/// Fixtures are plain in-memory values. Stores use ephemeral sessions, no request is sent,
/// and no socket is opened. Every view is hosted off-screen so its body and branches execute.
@Suite("Mocked dashboard and endpoint evaluation", .serialized)
@MainActor
struct MockedDashboardAndEndpointEvaluationTests {
    private func makeStore(demo: Bool) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.mockeddash.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        if demo { store.loadDemo() }
        return (store, defaults, suite)
    }

    private func evaluate<V: View>(_ view: V, width: CGFloat = 1100, height: CGFloat = 1400) {
        let host = NSHostingView(rootView: NavigationStack { view })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    private func fields(family: String = "bitaxe") -> [String: JSONValue] {
        [
            "hostname": .string("Rig"), "firmwareFamily": .string(family),
            "ASICModel": .string("BM1370"), "deviceModel": .string("Gamma"),
            "version": .string("2.12.0"), "macAddr": .string("aa:bb:cc:dd:ee:ff"),
            "frequency": .number(525), "coreVoltage": .number(1060),
            "temp": .number(62), "vrTemp": .number(55), "power": .number(14),
            "fanspeed": .number(60), "manualFanSpeed": .number(60), "minFanSpeed": .number(20),
            "autofanspeed": .bool(false), "temptarget": .number(65),
            "hashRate": .number(900), "expectedHashrate": .number(950),
            "sharesAccepted": .integer(120), "sharesRejected": .integer(2),
            "uptimeSeconds": .integer(3600), "wifiRSSI": .integer(-55)
        ]
    }

    private func snapshot(_ raw: [String: JSONValue]) -> MinerSnapshot {
        MinerSnapshot(
            info: MinerInfo(raw: raw), previousInfo: nil, error: nil, updatedAt: Date(),
            completeSnapshotAt: Date(), powerObservedAt: Date(),
            history: [], isCached: false, isReconnecting: false
        )
    }

    /// Two miners with mock snapshots, so the dashboard renders populated fleet cards and history.
    private func populatedStore() -> (FleetStore, [MinerDevice], UserDefaults, String) {
        let (store, defaults, suite) = makeStore(demo: false)
        let first = MinerDevice(name: "Rig A", address: "192.168.1.10", kind: .espMiner, firmwareFamily: "bitaxe")
        let second = MinerDevice(name: "Rig B", address: "192.168.1.11", kind: .espMiner, firmwareFamily: "nerdqaxe")
        store.devices = [first, second]
        store.snapshots[first.id] = snapshot(fields(family: "bitaxe"))
        store.snapshots[second.id] = snapshot(fields(family: "nerdqaxe"))
        return (store, [first, second], defaults, suite)
    }

    // MARK: - Dashboard branches with mock fleet data

    @Test func evaluateDashboardWithMockFleet() {
        let (store, _, defaults, suite) = populatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        evaluate(DashboardView(store: store, startupReady: true))
        evaluate(DashboardView(store: store, startupReady: false))
        evaluate(DashboardView(store: store, startupReady: true), width: 420, height: 900)
        evaluate(DashboardView(store: store, startupReady: true, onToggleSidebar: {}), width: 1400, height: 900)
    }

    @Test func evaluateDashboardDemoFleet() {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        evaluate(DashboardView(store: store, startupReady: true))
    }

    // MARK: - FleetHistoryCard: fleet and per-miner modes

    @Test func evaluateFleetHistoryCardModes() {
        let (store, devices, defaults, suite) = populatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshots = store.snapshots
        for mode in FleetPreferences.DashboardMode.allCases {
            evaluate(FleetHistoryCard(
                devices: devices, snapshots: snapshots, isDemo: false, database: nil,
                isMinerDetail: false, isCompactDashboard: false, dashboardMode: mode,
                numberFirst: true, prefersHistoryPopover: false
            ))
            evaluate(FleetHistoryCard(
                devices: devices, snapshots: snapshots, isDemo: false,
                initialDisplay: .miners, initialRecentRange: .day, database: nil,
                isMinerDetail: true, isCompactDashboard: true, dashboardMode: mode,
                numberFirst: false, prefersHistoryPopover: true
            ), width: 420, height: 900)
        }
        evaluate(FleetHistoryCard(
            devices: [], snapshots: [:], isDemo: true, database: nil,
            isMinerDetail: false, isCompactDashboard: false, dashboardMode: .full,
            numberFirst: true, prefersHistoryPopover: false
        ))
    }

    // MARK: - MinerEndpointView across endpoint families (mock response data only)

    @Test func evaluateEndpointViewsAcrossCatalog() {
        let (store, devices, defaults, suite) = populatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = devices[0]
        let insights = MiningInsightsStore()
        for endpoint in MinerEndpoint.catalog {
            evaluate(MinerEndpointView(
                device: device, store: store, endpoint: endpoint, insights: insights, onWriteCompleted: nil
            ))
        }
    }

    @Test func evaluateEndpointViewWriteCompletionCallback() {
        let (store, devices, defaults, suite) = populatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        var completed = false
        evaluate(MinerEndpointView(
            device: devices[0], store: store, endpoint: .settings, onWriteCompleted: { completed = true }
        ))
        #expect(!completed)
    }

    @Test func evaluateMinerCompletionAlertInit() {
        let defaultAlert = MinerCompletionAlert(title: "Saved", message: "Settings written.")
        #expect(!defaultAlert.didWrite)
        let writeAlert = MinerCompletionAlert(title: "Saved", message: "Pool updated.", didWrite: true)
        #expect(writeAlert.didWrite)
        #expect(writeAlert.title == "Saved")
    }

    // MARK: - MinerCustomJSONView states (offline, staged callback only)

    @Test func evaluateCustomJSONViewStates() {
        let (_, devices, defaults, suite) = populatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = devices[0]
        evaluate(MinerCustomJSONView(device: device, isDemo: false, isOffline: false, onStaged: { _ in }))
        evaluate(MinerCustomJSONView(device: device, isDemo: true, isOffline: false, onStaged: { _ in }))
        evaluate(MinerCustomJSONView(device: device, isDemo: false, isOffline: true, onStaged: { _ in }))
        evaluate(MinerCustomJSONView(
            device: device, isDemo: false, isOffline: false,
            initialJSON: "{\"frequency\": 550}", onStaged: { _ in }
        ), width: 420, height: 1200)
    }

    // MARK: - DeveloperTipJarService states driven by public test hooks (no StoreKit)

    @Test func evaluateTipJarServiceLoadingAndErrorStates() {
        let service = DeveloperTipJarService(startUpdatesListener: false)
        service.setTestState(loading: true, error: nil, attempted: false)
        #expect(service.isLoadingProducts)
        #expect(!service.hasAttemptedLoad)
        service.setTestState(loading: false, error: "Store unavailable.", attempted: true)
        #expect(service.loadError == "Store unavailable.")
        #expect(service.hasAttemptedLoad)
        service.setTestState(loading: false, error: nil, attempted: true)
        #expect(service.loadError == nil)
    }

    @Test func evaluateTipProductsAllBranches() {
        for product in DeveloperTipProduct.allCases {
            #expect(!product.defaultTitle.isEmpty)
            #expect(!product.defaultDescription.isEmpty)
            #expect(DeveloperTipProduct(rawValue: product.id) == product)
        }
        #expect(DeveloperTipProduct.allCases.count == 6)
    }

    @Test func evaluateTipPurchaseStateEquality() {
        let states: [DeveloperTipPurchaseState] = [
            .idle, .purchasing("small"), .success("small"), .pending("medium"), .cancelled, .failed("declined")
        ]
        #expect(states.count == 6)
        #expect(DeveloperTipPurchaseState.idle == .idle)
        #expect(DeveloperTipPurchaseState.failed("a") != .failed("b"))
        #expect(DeveloperTipPurchaseState.cancelled != .idle)
    }
}
