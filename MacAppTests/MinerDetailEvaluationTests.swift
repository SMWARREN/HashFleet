import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Evaluation coverage for the per-miner detail workspace, the tuning session, the live console,
/// the cooling preview and the XMRig controller. Each test hosts a view in an off-screen window
/// and forces a layout pass, exercising the real SwiftUI body, `@ViewBuilder` branches and
/// state-dependent sections without opening a socket or contacting a miner.
@Suite("Miner detail and tuning views evaluation", .serialized)
@MainActor
struct MinerDetailEvaluationTests {
    private func makeStore(demo: Bool = true) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.minerdetail.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        if demo { store.loadDemo() }
        return (store, defaults, suite)
    }

    /// Mounts a view (wrapped in a navigation stack so value routes resolve) and forces layout.
    private func evaluate<V: View>(_ view: V, width: CGFloat = 800, height: CGFloat = 1400) {
        let host = NSHostingView(rootView: NavigationStack { view })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    /// A complete ESP-Miner Info payload covering cooling, tuning, pool and display fields so the
    /// availability checks, editors and collapsible sections take their populated branches.
    private func fullInfo(name: String = "Rig One", paused: Bool = false) -> MinerInfo {
        MinerInfo(raw: [
            "hostname": .string(name), "macAddr": .string("A1:B2:C3:D4:E5:F6"),
            "version": .string("v2.15.2"), "ASICModel": .string("BM1370"),
            "hashRate": .number(1180), "power": .number(19.4), "voltage": .number(5200),
            "temp": .number(54), "vrTemp": .number(61), "temp2": .number(52),
            "fanspeed": .number(68), "fanrpm": .number(4200),
            "frequency": .number(575), "coreVoltage": .number(1150),
            "actualFrequency": .number(572), "coreVoltageActual": .number(1140),
            "sharesAccepted": .number(12486), "sharesRejected": .number(3),
            "uptimeSeconds": .number(245820), "wifiRSSI": .number(-48),
            "bestDiff": .string("18.4G"), "bestSessionDiff": .string("9.2M"),
            "statsFrequency": .integer(30), "miningPaused": .bool(paused),
            "autofanspeed": .integer(1), "temptarget": .integer(55),
            "manualFanSpeed": .integer(60), "minFanSpeed": .integer(25),
            "rotation": .integer(0), "invertscreen": .integer(0), "displayTimeout": .integer(5),
            "stratumURL": .string("solo.ckpool.org"),
            "fallbackStratumURL": .string("bch.solofury.com"),
            "stratumPort": .integer(3333), "fallbackStratumPort": .integer(3333),
            "primaryPoolIndex": .integer(0), "secondaryPoolIndex": .integer(1),
            "pools": .array([
                poolRecord(id: 0, server: "solo.ckpool.org"),
                poolRecord(id: 1, server: "bch.solofury.com")
            ])
        ])
    }

    private func poolRecord(id: Int64, server: String) -> JSONValue {
        .object([
            "id": .integer(id), "stratumURL": .string(server), "stratumPort": .integer(3333),
            "stratumUser": .string("worker.\(id)"), "stratumPassword": .string("x")
        ])
    }

    private func snapshot(_ info: MinerInfo?, error: String? = nil, reconnecting: Bool = false) -> MinerSnapshot {
        MinerSnapshot(
            info: info, previousInfo: nil, error: error, updatedAt: Date(),
            completeSnapshotAt: info == nil ? nil : Date(), powerObservedAt: info == nil ? nil : Date(),
            history: [], isCached: false, isReconnecting: reconnecting
        )
    }

    /// A non-demo store with one real device and a fresh writable snapshot, taking the live
    /// write-eligible branches in tuning, cooling and quick actions.
    private func makeLiveStore(
        kind: MinerDevice.Kind = .espMiner, paused: Bool = false
    ) throws -> (FleetStore, MinerDevice, UserDefaults, String) {
        let (store, defaults, suite) = makeStore(demo: false)
        let device = MinerDevice(name: "Rig One", address: "192.168.1.50", kind: kind)
        store.devices = [device]
        store.snapshots[device.id] = snapshot(fullInfo(paused: paused))
        return (store, device, defaults, suite)
    }

    // MARK: - MinerDetailView body and telemetry sections

    @Test func evaluateDetailAcrossDashboardModesDemo() throws {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = try #require(store.devices.first)
        let insights = MiningInsightsStore()

        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            evaluate(MinerDetailView(device: device, store: store, insights: insights))
            evaluate(MinerDetailView(device: device, store: store, insights: insights), width: 1280, height: 1100)
            evaluate(MinerDetailView(device: device, store: store, insights: insights, isLive: true), width: 420, height: 1800)
        }
    }

    @Test func evaluateDetailLiveReconnectingAndUnavailable() throws {
        let (store, device, defaults, suite) = try makeLiveStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = MiningInsightsStore()

        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            store.snapshots[device.id] = snapshot(fullInfo())
            evaluate(MinerDetailView(device: device, store: store, insights: insights))
            evaluate(MinerDetailView(device: device, store: store, insights: insights, liveConnectionError: "Live monitoring unavailable"))

            // Reconnecting: loading skeleton path.
            store.snapshots[device.id] = snapshot(nil, error: "Timed out", reconnecting: true)
            evaluate(MinerDetailView(device: device, store: store, insights: insights))

            // Hard error, not reconnecting: telemetry-unavailable path.
            store.snapshots[device.id] = snapshot(nil, error: "Host is down")
            evaluate(MinerDetailView(device: device, store: store, insights: insights))
        }
    }

    @Test func evaluateDetailTelemetrySectionsAndSubcards() throws {
        let (store, device, defaults, suite) = try makeLiveStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let info = fullInfo()
        let insights = MiningInsightsStore()
        let diagnostics = MinerDiagnosticsModel(info: info)

        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            let detail = MinerDetailView(device: device, store: store, insights: insights)
            evaluate(detail.telemetrySections(info))
            evaluate(detail.metrics(info, diagnostics: diagnostics))
            evaluate(detail.coolingCard(info))
            evaluate(detail.tuningCard(info))
            evaluate(detail.identity(info))
            evaluate(detail.poolsSection)
            evaluate(detail.hashrateHero(info))
            evaluate(detail.hashrateHero(info, compact: true))
            evaluate(detail.heroConditions(info))
            evaluate(detail.bestShares(info))
            evaluate(detail.quickControls)
            evaluate(detail.quickActions)
            evaluate(detail.controls)
            evaluate(detail.controlMinerCard)
            evaluate(detail.fleetManagementControls)
            evaluate(detail.essentialsAPITools)
            evaluate(detail.advancedTools)
        }
    }

    @Test func evaluateDetailFirmwareNoticeAndQuickActions() throws {
        let (store, device, defaults, suite) = try makeLiveStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let info = fullInfo()
        let detail = MinerDetailView(device: device, store: store, insights: MiningInsightsStore())

        evaluate(detail.firmwareUpdateSection(NumberFirstPreview.minerFirmwareNotice))
        for action in MinerDetailQuickAction.allCases {
            evaluate(detail.quickAction(action))
            evaluate(detail.quickAction(action, compact: true))
            evaluate(detail.previewQuickAction(action))
            evaluate(MinerQuickActionPreviewResult(action: action))
            _ = action.endpoint
            _ = action.symbol
            _ = action.identifier
            _ = action.previewResult
        }
        evaluate(MinerInlineActionFeedback(state: MinerInlineActionState()))
        #expect(MinerInlineActionState.identity(from: info) != nil)
        #expect(MinerInlineActionState.identity(from: MinerInfo(raw: ["hostname": .string("x")])) == nil)
    }

    // MARK: - MinerDetailView+NumberFirst

    @Test func evaluateNumberFirstTelemetry() throws {
        let (store, device, defaults, suite) = try makeLiveStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let info = fullInfo()
        let insights = MiningInsightsStore()
        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            let detail = MinerDetailView(device: device, store: store, insights: insights)
            evaluate(detail.numberFirstTelemetry(info))
        }

        let availability = NumberFirstPreview.minerAvailability(info)
        _ = availability.rawAPI
        _ = availability.canEditSettings
        _ = availability.cooling
        _ = availability.tuning
        _ = availability.quickActions
        _ = availability.settingsCategories(usesEssentialsPools: false)
        _ = availability.settingsCategories(usesEssentialsPools: true)
        _ = availability.showsSettingsHub(in: .full)
        _ = availability.firmwareUpdate(NumberFirstPreview.minerFirmwareNotice)
        _ = availability.firmwareUpdate(nil)

        let sparse = MinerNumberFirstAvailability(
            info: MinerInfo(raw: ["hostname": .string("Sparse"), "hashRate": .number(10)]),
            infoStatus: .supported, settingsStatus: .notChecked, firmwareStatus: .notChecked
        )
        #expect(!sparse.canEditSettings)
        #expect(sparse.settingsCategories().isEmpty)
        #expect(sparse.quickActions.isEmpty)
    }

    // MARK: - MinerTuningSessionView

    @Test func evaluateTuningSessionDemoAndLive() throws {
        let (demoStore, demoDefaults, demoSuite) = makeStore(demo: true)
        defer { demoDefaults.removePersistentDomain(forName: demoSuite) }
        let demoDevice = try #require(demoStore.devices.first)
        for mode in FleetPreferences.DashboardMode.allCases {
            demoStore.preferences.dashboardMode = mode
            evaluate(MinerTuningSessionView(device: demoDevice, store: demoStore), height: 2000)
        }

        let (liveStore, liveDevice, liveDefaults, liveSuite) = try makeLiveStore()
        defer { liveDefaults.removePersistentDomain(forName: liveSuite) }
        var tuningView = MinerTuningSessionView(device: liveDevice, store: liveStore)
        evaluate(tuningView, height: 2000)
        tuningView.restoreDraft()
        tuningView.applyStagedChange()
        evaluate(MinerTuningPreviewRoute(device: liveDevice, store: liveStore, insights: nil), height: 2000)

        // Offline live store: read-only tuning path.
        liveStore.snapshots[liveDevice.id] = snapshot(nil, error: "Host is down")
        evaluate(MinerTuningSessionView(device: liveDevice, store: liveStore), height: 2000)
    }

    @Test func evaluateTuningSessionAdvancedAndInline() throws {
        let (store, device, defaults, suite) = try makeLiveStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        // reviewPresentation forces the advanced control mode on init.
        var presentsReview = false
        let reviewBinding = Binding(get: { presentsReview }, set: { presentsReview = $0 })
        evaluate(MinerTuningSessionView(device: device, store: store, reviewPresentation: reviewBinding), height: 2200)

        // Inline advanced embeds the dials into a parent surface.
        var expanded = true
        var busy = false
        let inline = MinerTuningSessionView.InlineAdvanced(
            isExpanded: Binding(get: { expanded }, set: { expanded = $0 }),
            isBusy: Binding(get: { busy }, set: { busy = $0 }),
            jumpToReview: {}
        )
        evaluate(MinerTuningSessionView(device: device, store: store, inlineAdvanced: inline), height: 2200)
    }

    // MARK: - MinerTuningSession cards and advanced readings

    @Test func evaluateTuningSessionCards() {
        for controlMode in [MinerTuningControlMode.easy, .advanced] {
            evaluate(MinerTuningSessionHeader(
                deviceName: "Rig", isDemo: false, isOffline: false,
                chipCount: 1, chipCountWasReported: true, controlMode: controlMode
            ))
        }
        evaluate(MinerTuningSessionHeader(
            deviceName: "Rig", isDemo: true, isOffline: true,
            chipCount: 6, chipCountWasReported: false, controlMode: .advanced
        ))

        var on = false
        evaluate(MinerTuningAdvancedSwitch(isOn: Binding(get: { on }, set: { on = $0 })))

        var acknowledged = false
        let ackBinding = Binding(get: { acknowledged }, set: { acknowledged = $0 })
        evaluate(MinerTuningSafetyCard(
            riskAcknowledged: ackBinding, isBeyondReference: true, hasReference: true,
            voltageRestriction: "Limited to 1150 mV on this board"
        ))
        evaluate(MinerTuningSafetyCard(
            riskAcknowledged: ackBinding, isBeyondReference: false, hasReference: true,
            voltageRestriction: nil, compact: true
        ))

        evaluate(MinerTuningReferenceCard(reference: nil, isDemo: true))
        evaluate(MinerTuningReferenceCard(reference: nil, isDemo: false))

        evaluate(MinerTuningLiveContextCard(
            configuredFrequency: "575 MHz", measuredFrequency: "572 MHz",
            configuredVoltage: "1150 mV", measuredVoltage: "1140 mV",
            asicErrors: "0.01%", isChecking: true
        ))

        evaluate(MinerTuningJournalCard(journal: []))
        let entry = MinerTuningJournalEntry(id: UUID(), date: Date(), title: "Tuning applied", detail: "575 MHz")
        evaluate(MinerTuningJournalCard(journal: [entry]))
    }

    @Test func evaluateTuningAdvancedReadings() throws {
        let (store, device, defaults, suite) = try makeLiveStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = MinerTuningSessionView(device: device, store: store)
        _ = session.info
        _ = session.navigationIdentity
        _ = session.chipCount
        _ = session.chipCountWasReported
        _ = session.configuredFrequency
        _ = session.configuredVoltage
        _ = session.referenceMaximum
        _ = session.voltageReferenceMaximum
        _ = session.isBeyondReference
        _ = session.isVoltageBeyondReference
        _ = session.isAnyBeyondReference
        evaluate(session.advancedControlsSection, height: 1600)
        evaluate(session.liveContextCard)

        let card = MinerTuningASICCard(
            number: 1,
            coreReading: MinerTuningCoreReading(number: 1, temperatureCelsius: 54, voltageMillivolts: 1140),
            frequency: 575, stagedVoltage: 1150, referenceMaximum: 650,
            isBeyondReference: false, accessibilityPrefix: "tuningSession.asic.1"
        )
        evaluate(card)
    }

    // MARK: - MinerLiveView

    @Test func evaluateLiveConsoleDemoAndLive() throws {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = try #require(store.devices.first)

        for endpoint in [MinerEndpoint.liveWebSocket, .logWebSocket] {
            evaluate(MinerLiveView(device: device, isDemo: true, initialEndpoint: endpoint))
        }

        // Non-demo keeps the socket closed in an off-screen host (no scene becomes active).
        let realDevice = MinerDevice(name: "Rig", address: "192.168.1.60")
        evaluate(MinerLiveView(device: realDevice, isDemo: false, navigationIdentity: nil))

        // Drive the model's deterministic demo and disconnect branches directly.
        let model = MinerLiveModel()
        model.connect(device: realDevice, endpoint: .liveWebSocket, isDemo: true)
        #expect(!model.isConnected)
        model.recordReceived(Data(#"{"data":{"hashRate":1180}}"#.utf8), endpoint: .liveWebSocket)
        #expect(model.frames.count == 1)
        #expect(model.latestFields["hashRate"] != nil)
        #expect(model.status.contains("Receiving"))
        model.recordReceived(Data("log line".utf8), endpoint: .logWebSocket)
        #expect(model.frames.count == 2)
        model.clear()
        #expect(model.frames.isEmpty)
        model.disconnect()
        #expect(model.status == "Disconnected")

        let populatedModel = MinerLiveModel()
        populatedModel.recordReceived(Data(#"{"data":{"hashRate":1180,"voltage":5200,"temp":54}}"#.utf8), endpoint: .liveWebSocket)
        let liveViewWithFrames = MinerLiveView(device: realDevice, isDemo: false, model: populatedModel)
        evaluate(liveViewWithFrames)
        evaluate(liveViewWithFrames.telemetry)
    }

    @Test func evaluateTuningPreviewReviewAndDraft() {
        let info = fullInfo()
        var draft = MinerTuningPreviewDraft(info: info)
        draft.edit(.frequency, "600")
        draft.edit(.coreVoltage, "1200")
        if let review = draft.review {
            evaluate(MinerTuningPreviewReview(request: review, canConfirm: true, isLive: true, attemptMessage: nil, confirm: {}))
            evaluate(MinerTuningPreviewReview(request: review, canConfirm: false, isLive: false, attemptMessage: "Applying...", confirm: {}))
        }
        draft.reset()
        _ = draft.next(.frequency, direction: 1)
        _ = draft.next(.coreVoltage, direction: -1)
        for field in MinerTuningPreviewDraft.Field.allCases {
            _ = field.id
            _ = field.title
            _ = field.unit
            _ = field.formatted(100)
            _ = field.formatted(nil)
        }
    }

    // MARK: - MinerCoolingPreview

    @Test func evaluateCoolingPreviewVariants() {
        let info = fullInfo()
        for mode in FleetPreferences.DashboardMode.allCases {
            evaluate(MinerCoolingPreview(mode: mode, info: info, canEdit: true))
            evaluate(MinerCoolingPreview(mode: mode, info: info, canEdit: false))
        }
        evaluate(MinerCoolingPreview(mode: .full, info: nil, canEdit: true))
        evaluate(MinerCoolingPreview(mode: .full, info: MinerInfo(raw: ["hostname": .string("Bare")]), canEdit: false))

        let manualInfo = MinerInfo(raw: [
            "hostname": .string("Manual"), "hashRate": .number(100),
            "autofanspeed": .integer(0), "manualFanSpeed": .integer(55),
            "temp": .number(50), "fanspeed": .number(55), "fanrpm": .number(3800)
        ])
        evaluate(MinerCoolingPreview(mode: .essentials, info: manualInfo, canEdit: true))

        let live = MinerCoolingPreview.LiveDestination(target: "192.168.1.50", save: { _, draft in draft })
        let cooling = MinerCoolingPreview(mode: .full, info: info, canEdit: true, live: live)
        evaluate(cooling)
        evaluate(cooling.actions)
        evaluate(MinerCoolingPreview(mode: .full, info: info, canEdit: false, live: live))

        let review = MinerCoolingPreview.Review(changes: ["temptarget": .integer(60)], json: "{\"temptarget\": 60}")
        evaluate(cooling.reviewSheet(review))
    }

    @Test func evaluateCoolingPreviewDraftLogic() throws {
        let info = fullInfo()
        var draft = MinerCoolingPreviewDraft(info: info)
        #expect(draft.automatic == true)
        #expect(draft.supportsMode(automatic: true))
        #expect(draft.supportsMode(automatic: false))
        #expect(draft.activeFields.contains(.target))

        let originalTarget = try #require(draft[.target])
        draft.adjust(.target, increasing: true)
        #expect(draft[.target] == originalTarget + 1)
        let changes = draft.changes(from: MinerCoolingPreviewDraft(info: info))
        #expect(changes["temptarget"] != nil)

        draft.select(automatic: false)
        #expect(draft.automatic == false)
        #expect(draft.activeFields == [.manual])

        let applied = MinerCoolingPreviewDraft(info: info)
            .applying(["autofanspeed": .integer(0), "manualFanSpeed": .integer(70)])
        #expect(applied.automatic == false)

        var liveDraft = MinerCoolingPreviewDraft(info: info)
        liveDraft.adjust(.target, increasing: false)
        let liveChanges = try liveDraft.liveChanges(from: MinerCoolingPreviewDraft(info: info))
        #expect(liveChanges["temptarget"] != nil)
    }

    // MARK: - XMRigControlView

    @Test func evaluateXMRigControllerStates() throws {
        let (store, device, defaults, suite) = try makeLiveStore(kind: .xmrig, paused: false)
        defer { defaults.removePersistentDomain(forName: suite) }
        evaluate(XMRigControlView(device: device, store: store))

        store.snapshots[device.id] = snapshot(fullInfo(paused: true))
        evaluate(XMRigControlView(device: device, store: store))

        // Offline: read-only notice path.
        store.snapshots[device.id] = snapshot(nil, error: "Host is down")
        evaluate(XMRigControlView(device: device, store: store))

        // Demo store with a CPU device renders the disabled, read-only controller.
        let (demoStore, demoDefaults, demoSuite) = makeStore(demo: true)
        defer { demoDefaults.removePersistentDomain(forName: demoSuite) }
        let cpu = MinerDevice(name: "Sample CPU", address: "cpu-demo.invalid", kind: .xmrig)
        demoStore.devices.append(cpu)
        demoStore.snapshots[cpu.id] = snapshot(fullInfo(paused: false))
        evaluate(XMRigControlView(device: cpu, store: demoStore))

        #expect(XMRigControlView.stateLabel(snapshot: snapshot(fullInfo(paused: true)), now: Date()) == "Paused")
        #expect(XMRigControlView.stateLabel(snapshot: snapshot(fullInfo(paused: false)), now: Date()) == "Mining")
        #expect(XMRigControlView.stateLabel(snapshot: snapshot(nil, error: "down"), now: Date())
            == "Offline or stale · last known state")
        for action in [XMRigControlView.Action.pause, .resume] {
            #expect(!action.title.isEmpty)
            #expect(!action.symbol.isEmpty)
            #expect(!action.explanation.isEmpty)
        }
    }
}
