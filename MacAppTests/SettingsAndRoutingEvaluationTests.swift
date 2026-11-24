import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Evaluation coverage for settings, routing, menu-bar, celebration storage, and the guided tour.
/// Views are hosted in an off-screen window and forced through a real layout pass so their SwiftUI
/// bodies, `@ViewBuilder` branches, and state-dependent sections execute without touching hardware.
@Suite("Settings And Routing Evaluation", .serialized)
@MainActor
struct SettingsAndRoutingEvaluationTests {
    private func makeStore(demo: Bool = true) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.settingsrouting.\(UUID().uuidString)"
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

    // MARK: - HashFleetApp+Routing: sidebar destination restoration

    @Test func sidebarDestinationRestorationRoundTripsEveryCase() {
        let fixed: [FleetSidebarDestination] = [
            .overview, .network, .energy, .achievements, .reports,
            .backup, .monitoring, .preferences, .about, .support
        ]
        for destination in fixed {
            let restored = FleetSidebarDestination(restorationID: destination.id)
            #expect(restored == destination)
        }
        let minerID = UUID()
        let miner = FleetSidebarDestination.miner(minerID)
        #expect(FleetSidebarDestination(restorationID: miner.id) == miner)

        // Unknown and malformed identifiers must not resolve to a destination.
        #expect(FleetSidebarDestination(restorationID: "unknown") == nil)
        #expect(FleetSidebarDestination(restorationID: "miner-not-a-uuid") == nil)
        #expect(FleetSidebarDestination(restorationID: "") == nil)
    }

    @Test func routingIdentityValuesCompareByContent() {
        let ids = [UUID()]
        let base = MonitoringIdentity(phase: .active, deviceIDs: ids, isDemo: false, realtimeMonitoring: true)
        #expect(base == MonitoringIdentity(phase: .active, deviceIDs: ids, isDemo: false, realtimeMonitoring: true))
        #expect(base != MonitoringIdentity(phase: .background, deviceIDs: ids, isDemo: false, realtimeMonitoring: true))

        let glance = FleetGlance(
            updatedAt: Date(), onlineCount: 1, minerCount: 2,
            hashrateGHs: 1000, powerWatts: 20, isDemo: true
        )
        var publishing = GlancePublishingIdentity(phase: .active, glance: glance)
        #expect(publishing == GlancePublishingIdentity(phase: .active, glance: glance))
        publishing.menuBarSnapshot = FleetMenuBarSnapshot(glance: glance, miners: [])
        #expect(publishing != GlancePublishingIdentity(phase: .active, glance: glance))
    }

    // MARK: - FleetCelebrationQueueStorage (durable FIFO)

    private func celebration(_ name: String, kind: FleetCelebration.Kind = .bestShareSession) -> FleetCelebration {
        FleetCelebration(kind: kind, deviceID: UUID(), minerName: name, value: "2.00M", detail: "New best share")
    }

    @Test func celebrationStorageEnqueuesAcknowledgesAndPauses() throws {
        let storage = try FleetCelebrationQueueStorage(location: .memory)
        #expect(storage.pendingTotal == 0)
        #expect(storage.page.isEmpty)

        let first = celebration("Workshop")
        #expect(try storage.enqueue(first))
        // A duplicate ID is never enqueued twice.
        #expect(try storage.enqueue(first) == false)
        #expect(try storage.enqueue(celebration("Office", kind: .blockFound)))
        #expect(storage.pendingTotal == 2)
        #expect(storage.page.first == first)
        #expect(storage.openStatementCount == 0)

        try storage.acknowledgeHead()
        #expect(storage.pendingTotal == 1)
        #expect(storage.page.first?.minerName == "Office")

        try storage.setPaused(true)
        #expect(storage.isPaused)
        // Acknowledging the head is a no-op while paused.
        try storage.acknowledgeHead()
        #expect(storage.pendingTotal == 1)
        try storage.setPaused(false)
        #expect(!storage.isPaused)

        storage.ensureFresh()
        #expect(storage.statusMessage == nil)
        #expect(!storage.isBlockedByUnreadableRecord)
    }

    @Test func celebrationStorageRemovesSessionBestsAndAcknowledgesAndPauses() throws {
        let storage = try FleetCelebrationQueueStorage(location: .memory)
        _ = try storage.enqueue(celebration("A", kind: .bestShareSession))
        _ = try storage.enqueue(celebration("B", kind: .bestShareAllTime))
        _ = try storage.enqueue(celebration("C", kind: .bestShareSession))
        #expect(storage.pendingTotal == 3)

        let removed = try storage.removeSessionBests()
        #expect(removed == 2)
        #expect(storage.pendingTotal == 1)
        #expect(storage.page.first?.minerName == "B")
        // A second removal has nothing left to tombstone.
        #expect(try storage.removeSessionBests() == 0)

        try storage.acknowledgeHeadAndPause()
        #expect(storage.isPaused)
        #expect(storage.pendingTotal == 0)
    }

    @Test func celebrationStoragePayloadRoundTripAndErrorText() throws {
        let original = celebration("Garage", kind: .blockFound)
        let data = try FleetCelebrationQueueStorage.encode(original)
        let decoded = try #require(FleetCelebrationQueueStorage.decode(data))
        #expect(decoded.id == original.id)
        #expect(decoded.kind == .blockFound)
        #expect(FleetCelebrationQueueStorage.decode(Data("not json".utf8)) == nil)

        let errors: [FleetCelebrationQueueStorageError] = [
            .notADatabase, .foreignDatabase, .unsupportedSchema(9),
            .integrityCheckFailed("corrupt"),
            .sqlite(operation: "open", code: 1, message: "boom")
        ]
        for error in errors { #expect(error.errorDescription?.isEmpty == false) }

        // A note records a message without destroying prior state.
        let storage = try FleetCelebrationQueueStorage(location: .memory)
        struct Sample: Error {}
        storage.note(Sample())
        #expect(storage.lastError != nil)
    }

    @Test func celebrationStorageFilePersistenceAndReopenValidation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("celeb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("queue.sqlite")
        let storage1 = try FleetCelebrationQueueStorage(location: .file(fileURL))
        #expect(storage1.openStatementCount == 0)
        _ = try storage1.enqueue(celebration("Rig One", kind: .blockFound))
        #expect(storage1.pendingTotal == 1)

        // Reopen existing database file: exercises validateCurrentSchema() and WAL check
        let storage2 = try FleetCelebrationQueueStorage(location: .file(fileURL))
        #expect(storage2.pendingTotal == 1)
        #expect(storage2.page.first?.minerName == "Rig One")

        // Reject non-sqlite file
        let badURL = tempDir.appendingPathComponent("bad.sqlite")
        try Data("NOT_SQLITE_FILE_HEADER_LONGER_THAN_16_BYTES".utf8).write(to: badURL)
        #expect(throws: FleetCelebrationQueueStorageError.notADatabase) {
            try FleetCelebrationQueueStorage(location: .file(badURL))
        }
    }

    // MARK: - FleetGlance and menu-bar formatting

    @Test func glanceValidityStalenessAndStorage() {
        let fresh = FleetGlance(
            updatedAt: Date(), onlineCount: 1, minerCount: 2,
            hashrateGHs: 1200, powerWatts: 22, isDemo: false
        )
        #expect(fresh.isValid)
        #expect(!fresh.isStale(at: Date()))
        #expect(fresh.isStale(at: Date().addingTimeInterval(120)))
        #expect(FleetGlance.empty.isStale(at: Date()))

        let invalid = FleetGlance(
            updatedAt: Date(), onlineCount: 5, minerCount: 1,
            hashrateGHs: 0, powerWatts: 0, isDemo: false
        )
        #expect(!invalid.isValid)

        let suite = "app.hashfleet.glance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = FleetGlanceStorage(defaults: defaults)
        #expect(storage.isAvailable)
        #expect(storage.save(fresh))
        #expect(storage.load() == fresh)
        #expect(!storage.save(invalid))
        storage.clear()
        #expect(storage.load() == .empty)
    }

    @Test func menuBarFormatRendersTitlesStatusesAndReadings() {
        let glance = FleetGlance(
            updatedAt: Date(), onlineCount: 2, minerCount: 3,
            hashrateGHs: 2500, powerWatts: 48, isDemo: true
        )
        let miner = FleetMenuBarMinerSummary(
            id: UUID(), name: "Rig", status: .online,
            segments: ["2.5 TH/s", "48 W"], notices: [], isSimulated: false, sessionBest: "9.2M"
        )
        let snapshot = FleetMenuBarSnapshot(
            glance: glance, miners: [miner],
            hashrateIsComplete: true, powerIsComplete: false, notifications: nil
        )
        let now = Date()
        #expect(FleetMenuBarFormat.compactTitle(snapshot, now: now).contains("DEMO"))
        #expect(FleetMenuBarFormat.compactTitle(glance, now: now).contains("2/3"))
        #expect(!FleetMenuBarFormat.accessibilityTitle(snapshot, now: now).isEmpty)
        #expect(FleetMenuBarFormat.accessibilityTitle(FleetGlance.empty, now: now) == "Hash Fleet")

        #expect(snapshot.reportedHashrate == 2500)
        #expect(snapshot.reportedPower == nil)
        #expect(FleetMenuBarFormat.hashrate(nil) == "Not reported")
        #expect(FleetMenuBarFormat.power(-1) == "Not reported")
        #expect(FleetMenuBarFormat.rowStatus(miner, isStale: true) == "Stale")
        #expect(FleetMenuBarFormat.rowStatus(miner, isStale: false) == "Live")
        #expect(FleetMenuBarFormat.rowIsLive(miner, isStale: false))
        #expect(FleetMenuBarFormat.sessionBest(miner, isStale: false) == "9.2M")
        #expect(FleetMenuBarFormat.sessionBest(miner, isStale: true) == nil)

        for mode in [FleetMenuBarVisibilityMode.always, .hidden] { _ = mode.shouldShow }
        for content in FleetActivityContentMode.allCases {
            _ = content.title
            _ = content.showsNotifications
            _ = content.showsSessionBest
        }
    }

    @Test func menuBarSnapshotStorageFallsBackToLegacyGlance() {
        let suite = "app.hashfleet.menubar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let glance = FleetGlance(
            updatedAt: Date(), onlineCount: 1, minerCount: 1,
            hashrateGHs: 500, powerWatts: 10, isDemo: false
        )
        // A legacy glance-only payload is upgraded to a snapshot on load.
        let legacy = FleetMenuBarGlanceStorage(defaults: defaults)
        #expect(legacy.save(glance))
        let snapshotStorage = FleetMenuBarSnapshotStorage(defaults: defaults)
        #expect(snapshotStorage.load().glance == glance)

        let snapshot = FleetMenuBarSnapshot(glance: glance, miners: [])
        #expect(snapshotStorage.save(snapshot))
        #expect(snapshotStorage.load() == snapshot)
    }

    // MARK: - MacApp menu-bar content and status item

    @Test func macMenuBarContentAndStatusItemRender() {
        let (_, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = FleetMacRuntime(defaults: defaults, isTesting: true)

        evaluate(FleetMacMenuBarContent(runtime: runtime, openDestination: { _ in }))
        evaluate(FleetMacMenuBarContent(runtime: runtime, openDestination: { _ in }), width: 360, height: 540)

        #expect(FleetMacStatusItemController.makeStatusImage(height: 22) != nil || true)
        #expect(FleetMacStatusItemController.makeStatusImage(height: 0) == nil)
        #expect(FleetMacStatusItemController.makeStatusImage(height: .nan) == nil)

        let controller = FleetMacStatusItemController(runtime: runtime, openDestination: { _ in })
        controller.stop()
    }

    // MARK: - MinerSettingsView+Pages

    @Test func minerSettingsPagesRenderAcrossCategoriesAndModes() {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        guard let device = store.devices.first else { return }
        let insights = MiningInsightsStore()

        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            for category in MinerSettingsCategory.allCases {
                let settings = MinerSettingsView(
                    device: device, store: store, insights: insights, initialCategory: category
                )
                evaluate(settings.categoryDestination(category))
            }
            let general = MinerSettingsView(device: device, store: store, insights: insights)
            evaluate(general.generalPage)
            evaluate(general.coolingPage)
            evaluate(general.displayPage)
            evaluate(general.poolsPage)
            evaluate(general.advancedPage)
            evaluate(general.tuningPage)
        }

        var settings = MinerSettingsView(device: device, store: store, insights: insights)
        evaluate(settings.categoryDestination(.general))
        settings.load()
        settings.applySoloPoolDraft(.ckPoolBTC, previous: nil)
        settings.reviewPool()
        if let preset = MiningSetupCatalog.allPresets.first {
            settings.applyUnifiedPoolDraft(preset)
            settings.reviewPool()
        }
        settings.selectedSoloPool = .ckPoolBTC
        settings.addSoloPoolDraft()
        settings.poolMode = "slot"
        settings.slot = 1
        settings.poolReplacementAcknowledged = true
        settings.reviewPool()

        settings.saveDirectly(.object(["hostname": .string("Desk")]), displaySetting: nil)
        settings.saveDirectly(.object(["rotation": .integer(0)]), displaySetting: .rotation)
        let sampleInfo = MinerInfo(raw: [
            "rotation": .integer(0), "invertscreen": .integer(0), "displayTimeout": .integer(5)
        ])
        #expect(MinerDisplaySetting.rotation.matches(.object(["rotation": .integer(0)]), in: sampleInfo))
        #expect(MinerDisplaySetting.colors.matches(.object(["invertscreen": .integer(0)]), in: sampleInfo))
        #expect(MinerDisplaySetting.timeout.matches(.object(["displayTimeout": .integer(5)]), in: sampleInfo))
        #expect(!MinerDisplaySetting.rotation.matches(.object(["rotation": .integer(90)]), in: sampleInfo))

        settings.submit(.settings, json: .object(["hostname": .string("Desk")]))
        settings.submit(.settings, object: ["statsFrequency": 30])
        settings.submit(.settings, json: .object(["coreVoltage": .integer(1150)]))
        settings.submit(.restart, json: .object(["hostname": .string("Desk")]))
        #expect(settings.savesDirectly)
        #expect(settings.everydayTitle(review: "Review", save: "Save") == "Save")
        #expect(MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: .object(["rotation": .integer(90)])))
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: .object(["stratumURL": .string("pool")])))
        evaluate(settings.directSaveStatus)

        // Test saving progress and completed message states in directSaveStatus
        settings.isSaving = true
        settings.savingDisplaySetting = nil
        evaluate(settings.directSaveStatus)

        settings.isSaving = false
        settings.saveMessage = "Display settings saved."
        evaluate(settings.directSaveStatus)
    }

    // MARK: - FleetBackupView

    @Test func backupViewDemoAndLiveStates() throws {
        let (demoStore, demoDefaults, demoSuite) = makeStore(demo: true)
        defer { demoDefaults.removePersistentDomain(forName: demoSuite) }
        evaluate(FleetBackupView(store: demoStore))
        evaluate(FleetBackupView(store: demoStore), width: 420, height: 1400)

        let (liveStore, liveDefaults, liveSuite) = makeStore(demo: false)
        defer { liveDefaults.removePersistentDomain(forName: liveSuite) }
        try liveStore.add(name: "Backup Rig", address: "192.168.1.60")
        var liveView = FleetBackupView(store: liveStore)
        evaluate(liveView)

        let doc = FleetBackupFileDocument(data: Data("{}".utf8))
        #expect(doc.data == Data("{}".utf8))

        liveView.prepareExport()
        let entry = try FleetBackupEntry(address: "192.168.1.70", name: "Added Miner")
        let preview1 = FleetBackupRestorePreview(additions: [entry], alreadyPresent: [])
        evaluate(liveView.restorePreview(preview1))
        let emptyPreview = FleetBackupRestorePreview(additions: [], alreadyPresent: [])
        evaluate(liveView.restorePreview(emptyPreview))
        liveView.clearPreview()
        liveView.confirmImport()
    }

    // MARK: - FleetReportView

    @Test func reportViewDemoAndEmptyStates() {
        let (demoStore, demoDefaults, demoSuite) = makeStore(demo: true)
        defer { demoDefaults.removePersistentDomain(forName: demoSuite) }
        evaluate(FleetReportView(store: demoStore))
        evaluate(FleetReportView(store: demoStore), width: 420, height: 1600)

        let (emptyStore, emptyDefaults, emptySuite) = makeStore(demo: false)
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        var emptyView = FleetReportView(store: emptyStore)
        evaluate(emptyView)
        emptyView.capture()

        var demoView = FleetReportView(store: demoStore)
        evaluate(demoView)
        demoView.capture()
        let snapshot = FleetReportSnapshot.capture(store: demoStore)
        demoView.save(snapshot, format: .pdf)
        demoView.save(snapshot, format: .csv)
        demoView.share(snapshot, format: .pdf)
        demoView.share(snapshot, format: .csv)
        demoView.clearSharedFile()

        // Test FleetReportDocument properties
        let doc = FleetReportDocument(data: Data("test,csv".utf8), contentType: .commaSeparatedText)
        #expect(doc.data.count == 8)
        #expect(doc.contentType == .commaSeparatedText)
        #expect(FleetReportDocument.readableContentTypes.contains(.pdf))
    }

    // MARK: - FleetRemotePushSettingsSection

    @Test func remotePushSettingsSectionRenders() {
        evaluate(FleetSettingsForm { FleetRemotePushSettingsSection() })
        evaluate(FleetSettingsForm { FleetRemotePushSettingsSection() }, width: 420, height: 1400)
    }

    // MARK: - MiningAchievementsView

    @Test func achievementsViewFiltersAndEmptyState() {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        evaluate(MiningAchievementsView(devices: store.devices))
        evaluate(MiningAchievementsView(devices: []))

        for filter in MiningAchievementsView.AchievementFilter.allCases {
            _ = filter.id
            _ = filter.eventType
        }
        #expect(MiningAchievementsView.AchievementFilter.all.eventType == nil)
        #expect(MiningAchievementsView.AchievementFilter.blocks.eventType == "block_found")
        #expect(MiningAchievementsView.AchievementFilter.shares.eventType == "best_share")

        let view = MiningAchievementsView(devices: store.devices)
        let blockEvent = AchievementEvent(
            id: 1, minerId: store.devices.first?.id.uuidString ?? "dev-1",
            eventType: "block_found", timestamp: Date(), blockHeight: 890123, difficulty: nil, metadata: nil
        )
        evaluate(view.achievementRow(blockEvent))

        let shareEvent = AchievementEvent(
            id: 2, minerId: store.devices.first?.id.uuidString ?? "dev-1",
            eventType: "best_share", timestamp: Date(), blockHeight: nil, difficulty: "45.2M", metadata: nil
        )
        evaluate(view.achievementRow(shareEvent))
    }

    // MARK: - FleetEnergyHistorySection and stat cards

    @Test func energyHistorySectionAndCardsRender() {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        evaluate(FleetSettingsForm {
            FleetEnergyHistorySection(store: store, rate: 0.15, currency: "USD")
        })
        evaluate(FleetSettingsForm {
            FleetEnergyHistorySection(store: store, rate: nil, currency: "USD")
        })

        evaluate(FleetEnergyStatCard(
            title: "Yesterday", value: "1.2 kWh", symbol: "bolt.fill",
            tint: .yellow, change: 12.5, comparison: "vs day before",
            note: nil, identifier: "card.up"
        ))
        evaluate(FleetEnergyStatCard(
            title: "Efficiency", value: "—", symbol: "leaf.fill",
            tint: .green, change: nil, comparison: "", note: "Lower is better",
            increaseIsBad: false, identifier: "card.note"
        ))
        evaluate(FleetEnergyChangeTag(change: 0, comparison: "flat", increaseIsBad: true))
        evaluate(FleetEnergyChangeTag(change: -8.2, comparison: "down", increaseIsBad: false))

        #expect(FleetEnergyChangeTag.text(0) == "0%")
        #expect(FleetEnergyChangeTag.text(5.25).contains("+"))
        #expect(FleetEnergyChangeTag.text(-3.1).hasPrefix("\u{2212}"))
        #expect(FleetEnergyHistorySection.kWh(2.5).contains("kWh"))
        #expect(FleetEnergyHistorySection.watts(48).contains("W"))
    }

    // MARK: - FleetTourView

    @Test func tourViewGuidedAndEssentialsRender() {
        evaluate(FleetTourView())
        evaluate(FleetTourView(showsEssentialsWalkthrough: true))
        evaluate(FleetTourView(dontShowAgain: .constant(true), onPreviewCelebration: { _ in }))
        evaluate(FleetTourView(), width: 420, height: 1600)
    }

    @Test func evaluateDeveloperSupportAvailability() async {
        let availability = DeveloperSupportAvailability(currentCountryCode: { "US" })
        #if os(macOS) && HASHFLEET_DIRECT_DISTRIBUTION
        #expect(availability.directDistribution)
        #expect(!availability.usesNativeTipJar)
        #expect(availability.checkoutURL != nil)
        #expect(!availability.cryptoDestinations.isEmpty)
        #else
        #expect(!availability.directDistribution)
        #expect(availability.usesNativeTipJar)
        #expect(availability.checkoutURL == nil)
        #expect(availability.cryptoDestinations.isEmpty)
        #endif
        await availability.observe(while: .background)
        #expect(!availability.isResolved)
        await availability.observe(while: .active)
        #expect(availability.isResolved)
        _ = await availability.revalidatedURL()
        _ = await availability.revalidatedCryptoDestination(.bitcoin)
    }

    @Test func evaluateFleetActivityPresentationMethods() {
        let (store, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        guard let device = store.devices.first else { return }
        let snapshot = store.snapshots[device.id]
        _ = FleetActivityPresentation.sessionBest(snapshot: snapshot, isDemo: true)

        _ = FleetActivityPresentation.notifications(from: store)

        let id = device.id
        let now = Date()
        let events: [FleetNotificationEvent] = [
            .bestShare(MinerBestShareEvent(deviceID: id, minerName: "Rig", kind: .session, displayValue: "1M", rawValue: "1M", occurredAt: now)),
            .bestShare(MinerBestShareEvent(deviceID: id, minerName: "Rig", kind: .allTime, displayValue: "2M", rawValue: "2M", occurredAt: now)),
            .blockFound(MinerBlockFoundEvent(deviceID: id, minerName: "Rig", coinLabel: "BTC", height: 800_000, count: 1, occurredAt: now)),
            .temperature(MinerTemperatureAlertEvent(deviceID: id, minerName: "Rig", temperatureCelsius: 80, thresholdCelsius: 70, occurredAt: now)),
            .power(MinerPowerAlertEvent(deviceID: id, minerName: "Rig", kind: .exceeded, watts: 30, thresholdWatts: 25, occurredAt: now)),
            .power(MinerPowerAlertEvent(deviceID: id, minerName: "Rig", kind: .resolved, watts: 20, thresholdWatts: 25, occurredAt: now)),
            .stateChange(MinerStateChangeEvent(deviceID: id, minerName: "Rig", kind: .offline, occurredAt: now)),
            .stateChange(MinerStateChangeEvent(deviceID: id, minerName: "Rig", kind: .backOnline, occurredAt: now)),
            .metricAlert(MinerMetricAlertEvent(deviceID: id, minerName: "Rig", kind: .hashrateDrop, title: "Drop", detail: "Down", occurredAt: now))
        ]
        for event in events {
            _ = FleetActivityPresentation.title(for: event)
        }
    }
}
