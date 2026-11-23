import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Evaluation coverage for previously uncovered Dashboard and Miner views. Each test hosts the
/// view in an off-screen window and forces a layout pass, exercising the real SwiftUI body,
/// `@ViewBuilder` branches, and state-dependent sections without contacting a miner.
@Suite("Dashboard And Miner Views Evaluation", .serialized)
@MainActor
struct DashboardViewsEvaluationTests {
    private func makeStore(demo: Bool = true) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.dashviews.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let session = URLSession(configuration: .ephemeral)
        let store = FleetStore(defaults: defaults, session: session)
        if demo { store.loadDemo() }
        return (store, defaults, suite)
    }

    private func evaluate<V: View>(_ view: V, width: CGFloat = 800, height: CGFloat = 1200) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
    }

    /// A reasonably complete ESP-Miner Info payload. It satisfies the valid-info shape, carries a
    /// usable device identity, and includes cooling, tuning, pool, and display fields so the
    /// availability checks and editors can take their populated branches.
    private func fullInfo(name: String = "Rig One") -> MinerInfo {
        MinerInfo(raw: [
            "hostname": .string(name), "macAddr": .string("A1:B2:C3:D4:E5:F6"),
            "version": .string("v2.15.2"), "ASICModel": .string("BM1370"),
            "hashRate": .number(1180), "power": .number(19.4), "voltage": .number(5200),
            "temp": .number(54), "vrTemp": .number(61), "temp2": .number(52),
            "fanspeed": .number(68), "fanrpm": .number(4200),
            "frequency": .number(575), "coreVoltage": .number(1150),
            "sharesAccepted": .number(12486), "sharesRejected": .number(3),
            "uptimeSeconds": .number(245820), "wifiRSSI": .number(-48),
            "bestDiff": .string("18.4G"), "bestSessionDiff": .string("9.2M"),
            "statsFrequency": .integer(30),
            "autofanspeed": .integer(1), "temptarget": .integer(55),
            "manualFanSpeed": .integer(60), "minFanSpeed": .integer(25),
            "rotation": .integer(0), "invertscreen": .integer(0), "displayTimeout": .integer(5),
            "stratumURL": .string("solo.ckpool.org"),
            "fallbackStratumURL": .string("bch.solofury.com"),
            "stratumPort": .integer(3333), "fallbackStratumPort": .integer(3333),
            "stratumUser": .string("bc1qexampleworker.rig"),
            "fallbackStratumUser": .string("bitcoincash:qexample.rig"),
            "primaryPoolIndex": .integer(0), "secondaryPoolIndex": .integer(1),
            "pools": .array([
                modernPoolRecord(id: 0, server: "solo.ckpool.org"),
                modernPoolRecord(id: 1, server: "bch.solofury.com")
            ])
        ])
    }

    /// A modern pool record whose keys and value types satisfy `MinerEssentialsPoolBaseline`.
    private func modernPoolRecord(id: Int64, server: String) -> JSONValue {
        .object([
            "id": .integer(id), "stratumURL": .string(server), "stratumPort": .integer(3333),
            "stratumUser": .string("worker.\(id)"), "stratumPassword": .string("x"),
            "stratumProtocol": .string("SV1"), "stratumSuggestedDifficulty": .number(1000),
            "stratumExtranonceSubscribe": .bool(false), "stratumTLS": .integer(0),
            "stratumCert": .string(""), "stratumDecodeCoinbase": .bool(true),
            "stratumShareWarning": .bool(false), "stratumV2ChannelType": .string("standard"),
            "stratumV2AuthorityPubkey": .string(""), "stratumV2RequireAuth": .bool(false)
        ])
    }

    /// A non-demo store with one real device and a fresh, writable snapshot. This takes the live
    /// write-eligible branches in essentials pools and the cooling live destination.
    private func makeLiveStore() throws -> (FleetStore, MinerDevice, UserDefaults, String) {
        let (store, defaults, suite) = makeStore(demo: false)
        try store.add(name: "Rig One", address: "192.168.1.50")
        let device = try #require(store.devices.first)
        store.snapshots[device.id] = MinerSnapshot(
            info: fullInfo(),
            previousInfo: nil,
            error: nil,
            updatedAt: Date(),
            completeSnapshotAt: Date(),
            powerObservedAt: Date(),
            history: [],
            isCached: false,
            isReconnecting: false
        )
        return (store, device, defaults, suite)
    }

    // MARK: - DashboardView sections

    @Test func evaluateDashboardSectionsEmptyAndPopulated() throws {
        let (demoStore, demoDefaults, demoSuite) = makeStore(demo: true)
        defer { demoDefaults.removePersistentDomain(forName: demoSuite) }

        for mode in FleetPreferences.DashboardMode.allCases {
            demoStore.preferences.dashboardMode = mode
            evaluate(DashboardView(store: demoStore))
            evaluate(DashboardView(store: demoStore), width: 420, height: 1600)
            evaluate(DashboardView(store: demoStore), width: 1280, height: 1000)
        }

        let (emptyStore, emptyDefaults, emptySuite) = makeStore(demo: false)
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        for mode in FleetPreferences.DashboardMode.allCases {
            emptyStore.preferences.dashboardMode = mode
            evaluate(DashboardView(store: emptyStore))
            evaluate(DashboardView(store: emptyStore), width: 420, height: 1600)
        }
    }

    @Test func evaluateDashboardSectionRowsAndSearch() throws {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        // Internal section helpers are reachable from the extension and render the header,
        // search field, metric summaries, and heading independent of scroll geometry.
        let dashboard = DashboardView(store: store)
        evaluate(dashboard.minerSearch)
        evaluate(dashboard.summaryMetrics(wide: true))
        evaluate(dashboard.summaryMetrics(wide: false))

        // A populated non-demo fleet with an unreachable miner takes the attention and
        // reported-alert branches that the demo fleet never reaches.
        let (liveStore, device, liveDefaults, liveSuite) = try makeLiveStore()
        defer { liveDefaults.removePersistentDomain(forName: liveSuite) }
        liveStore.preferences.dashboardMode = .full
        evaluate(DashboardView(store: liveStore))
        liveStore.snapshots[device.id] = MinerSnapshot(
            info: nil, previousInfo: nil, error: "Connection timed out",
            updatedAt: Date(), completeSnapshotAt: nil, powerObservedAt: nil,
            history: [], isCached: false, isReconnecting: true
        )
        evaluate(DashboardView(store: liveStore))
        liveStore.preferences.dashboardMode = .essentials
        evaluate(DashboardView(store: liveStore))
    }

    // MARK: - AddMinerView and discovery

    @Test func evaluateAddMinerViewAndDiscoveryStates() {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        evaluate(AddMinerView(store: store))
        evaluate(AddMinerView(store: store, onBulkAddSuccess: {}))

        // Drive each discovery state through the coordinator and host the resulting content.
        let candidates = [
            MinerDiscoveryCandidate(address: "192.168.1.21", name: "Bitaxe Alpha", model: "BM1370"),
            MinerDiscoveryCandidate(address: "192.168.1.22", name: "Bitaxe Beta", model: "BM1368"),
            MinerDiscoveryCandidate(address: "192.168.1.23", name: "NerdAxe", model: nil)
        ]

        for state in discoveryScenarios(candidates: candidates) {
            let view = AddMinerView(store: store, discovery: state.coordinator)
            evaluate(view)
            evaluate(view.discoveryContent)
        }

        let empty = AddMinerView(store: store)
        evaluate(empty.discoveryEmptyState(title: "No compatible miners found", message: "Check Wi-Fi."))
        evaluate(empty.discoveryEmptyState(title: "Wi-Fi scan unavailable", message: "Turn on Wi-Fi."))
    }

    private struct DiscoveryScenario {
        let coordinator: MinerDiscoveryCoordinator
    }

    /// Builds coordinators pinned to each `MinerDiscoveryState`. Scanning uses a runner that
    /// reports progress then suspends, so the view observes the scanning state deterministically.
    private func discoveryScenarios(candidates: [MinerDiscoveryCandidate]) -> [DiscoveryScenario] {
        let plan = MinerDiscoveryScanPlan.plan(forIPv4Address: "192.168.1.9")

        // Results: runner returns candidates immediately so the coordinator settles on .results.
        let results = MinerDiscoveryCoordinator(
            planProvider: { plan },
            runner: { _, progress in
                progress(candidates, candidates.count)
                return candidates
            }
        )
        results.start()

        // No results: runner returns an empty list so the coordinator settles on .noResults.
        let noResults = MinerDiscoveryCoordinator(
            planProvider: { plan },
            runner: { _, _ in [] }
        )
        noResults.start()

        // Unavailable: no local plan is available.
        let unavailable = MinerDiscoveryCoordinator(planProvider: { nil }, runner: { _, _ in [] })
        unavailable.start()

        // Idle: a fresh coordinator that never started.
        let idle = MinerDiscoveryCoordinator(planProvider: { plan }, runner: { _, _ in [] })

        return [results, noResults, unavailable, idle].map(DiscoveryScenario.init)
    }

    // MARK: - MinerDetailView+NumberFirst

    @Test func evaluateNumberFirstTelemetryAcrossModes() throws {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        let device = try #require(store.devices.first)
        let info = try #require(store.snapshots[device.id]?.info)
        let insights = MiningInsightsStore()

        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            let detail = MinerDetailView(device: device, store: store, insights: insights)
            evaluate(detail.numberFirstTelemetry(info))
        }

        // Availability value branches: a complete sample reports settings, cooling, and tuning.
        let availability = NumberFirstPreview.minerAvailability(info)
        _ = availability.rawAPI
        _ = availability.canEditSettings
        _ = availability.cooling
        _ = availability.tuning
        _ = availability.quickActions
        _ = availability.settingsCategories(usesEssentialsPools: false)
        _ = availability.settingsCategories(usesEssentialsPools: true)
        _ = availability.showsSettingsHub(in: .full)
        _ = availability.showsSettingsHub(in: .essentials, usesEssentialsPools: true)
        _ = availability.firmwareUpdate(NumberFirstPreview.minerFirmwareNotice)
        _ = availability.firmwareUpdate(nil)

        // A minimal payload drops cooling, tuning, pools, and display categories.
        let sparse = MinerNumberFirstAvailability(
            info: MinerInfo(raw: ["hostname": .string("Sparse"), "hashRate": .number(10)]),
            infoStatus: .supported, settingsStatus: .notChecked, firmwareStatus: .notChecked
        )
        #expect(!sparse.canEditSettings)
        #expect(sparse.settingsCategories().isEmpty)
        #expect(sparse.quickActions.isEmpty)
    }

    @Test func evaluateNumberFirstTelemetryLiveDevice() throws {
        let (store, device, defaults, suite) = try makeLiveStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let info = try #require(store.snapshots[device.id]?.info)
        let insights = MiningInsightsStore()
        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            let detail = MinerDetailView(device: device, store: store, insights: insights)
            evaluate(detail.numberFirstTelemetry(info))
        }

        let availability = NumberFirstPreview.minerAvailability(info, device: device, store: store)
        _ = availability.rawAPI
        _ = availability.canEditSettings
        _ = availability.quickActions
    }

    // MARK: - MinerEssentialsPoolsView

    @Test func evaluateEssentialsPoolsDemoAndOffline() throws {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        let device = try #require(store.devices.first)
        evaluate(MinerEssentialsPoolsView(device: device, store: store))

        // Non-demo but offline (no fresh snapshot): read-only rows plus the offline notice.
        let (offlineStore, offlineDefaults, offlineSuite) = makeStore(demo: false)
        defer { offlineDefaults.removePersistentDomain(forName: offlineSuite) }
        try offlineStore.add(name: "Offline Rig", address: "192.168.1.70")
        let offlineDevice = try #require(offlineStore.devices.first)
        offlineStore.snapshots[offlineDevice.id] = MinerSnapshot(
            info: nil, previousInfo: nil, error: "Host is down",
            updatedAt: Date(), completeSnapshotAt: nil, powerObservedAt: nil,
            history: [], isCached: false, isReconnecting: false
        )
        evaluate(MinerEssentialsPoolsView(device: offlineDevice, store: offlineStore))
    }

    @Test func evaluateEssentialsPoolsEditableAndEditor() throws {
        let (store, device, defaults, suite) = try makeLiveStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Fresh writable snapshot takes the editable-row (button) branch.
        evaluate(MinerEssentialsPoolsView(device: device, store: store))

        let info = try #require(store.snapshots[device.id]?.info)
        let identity = try #require(MinerInlineActionState.identity(from: info))
        for role in MinerPoolRole.allCases {
            let baseline = try #require(MinerEssentialsPoolBaseline(role: role, raw: info.raw))
            evaluate(MinerEssentialsPoolEditor(device: device, store: store, initial: baseline, identity: identity))
        }
    }

    // MARK: - MinerCoolingPreview

    @Test func evaluateCoolingPreviewVariants() throws {
        let info = fullInfo()

        for mode in FleetPreferences.DashboardMode.allCases {
            evaluate(MinerCoolingPreview(mode: mode, info: info, canEdit: true))
            evaluate(MinerCoolingPreview(mode: mode, info: info, canEdit: false))
        }

        // Missing configuration hides the controls and shows the unavailable notice.
        evaluate(MinerCoolingPreview(mode: .full, info: nil, canEdit: true))
        evaluate(MinerCoolingPreview(mode: .full, info: MinerInfo(raw: ["hostname": .string("Bare")]), canEdit: false))

        // Manual-only configuration takes the manual branch.
        let manualInfo = MinerInfo(raw: [
            "hostname": .string("Manual"), "hashRate": .number(100),
            "autofanspeed": .integer(0), "manualFanSpeed": .integer(55),
            "temp": .number(50), "fanspeed": .number(55), "fanrpm": .number(3800)
        ])
        evaluate(MinerCoolingPreview(mode: .essentials, info: manualInfo, canEdit: true))

        // A live destination routes changes through the save closure instead of the demo path.
        let live = MinerCoolingPreview.LiveDestination(
            target: "192.168.1.50",
            save: { _, draft in draft }
        )
        evaluate(MinerCoolingPreview(mode: .full, info: info, canEdit: true, live: live))
        evaluate(MinerCoolingPreview(mode: .full, info: info, canEdit: false, live: live))
    }

    @Test func evaluateCoolingPreviewDraftLogic() throws {
        let info = fullInfo()
        var draft = MinerCoolingPreviewDraft(info: info)

        // Automatic mode exposes target and minimum fields and supports both modes.
        #expect(draft.automatic == true)
        #expect(draft.supportsMode(automatic: true))
        #expect(draft.supportsMode(automatic: false))
        #expect(draft.activeFields.contains(.target))

        // Adjusting a field within bounds mutates the stored value; the baseline diff reflects it.
        let originalTarget = try #require(draft[.target])
        draft.adjust(.target, increasing: true)
        #expect(draft[.target] == originalTarget + 1)
        let changes = draft.changes(from: MinerCoolingPreviewDraft(info: info))
        #expect(changes["temptarget"] != nil)

        // Switching to manual carries the reported manual setpoint.
        draft.select(automatic: false)
        #expect(draft.automatic == false)
        #expect(draft.activeFields == [.manual])

        // applying() and liveChanges() round-trip a validated change set.
        let applied = MinerCoolingPreviewDraft(info: info).applying(["autofanspeed": .integer(0), "manualFanSpeed": .integer(70)])
        #expect(applied.automatic == false)
        var liveDraft = MinerCoolingPreviewDraft(info: info)
        liveDraft.adjust(.target, increasing: false)
        let live = try liveDraft.liveChanges(from: MinerCoolingPreviewDraft(info: info))
        #expect(live["temptarget"] != nil)
    }
}
