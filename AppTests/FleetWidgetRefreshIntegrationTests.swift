import AppIntents
import Foundation
import SwiftUI
import Testing
import WidgetKit
import HashFleetCore
@testable import HashFleet
@testable import HashFleetWidgetTestSupport

@Suite("Explicit local widget refresh integration", .serialized) @MainActor
struct FleetWidgetRefreshIntegrationTests {
    @Test func ordinarySharingDoesNotEnableLocalReadsAndSeparateConsentCanBeRevoked() throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let coordinator = fixture.coordinator()
        let now = Date()
        let device = MinerDevice(name: "Private fixture name", address: "10.23.45.1")
        coordinator.updateWidgetRefreshFleet(devices: [device], snapshots: [:], isDemo: false, now: now)
        #expect(!coordinator.sharesWithWidgets && !coordinator.allowsWidgetRefresh)
        coordinator.setWidgetSharing(true, glance: fixture.glance(at: now))
        #expect(coordinator.sharesWithWidgets && !coordinator.allowsWidgetRefresh)
        let snapshots = [device.id: snapshot(at: now.addingTimeInterval(1))]
        coordinator.updateWidgetRefreshFleet(devices: [device], snapshots: snapshots, isDemo: false, now: now.addingTimeInterval(1))
        #expect(fixture.refresh.storage.load() == nil)
        coordinator.setWidgetRefreshEnabled(true, devices: [device], snapshots: snapshots,
            isDemo: false, now: now.addingTimeInterval(1))
        #expect(coordinator.allowsWidgetRefresh)
        #expect(fixture.refresh.storage.load()?.configuration.targets.count == 1)
        #expect(coordinator.widgetRefreshStatus.contains("Ready"))
        coordinator.setWidgetSharing(false, glance: fixture.glance(at: now))
        #expect(!coordinator.allowsWidgetRefresh)
        #expect(!fixture.preferences.bool(forKey: "app.hashfleet.allowWidgetRefresh"))
        #expect(fixture.refresh.storage.load() == nil)
        #expect(fixture.cacheStorage.load() == .empty)
        coordinator.setWidgetSharing(true, glance: fixture.glance(at: now))
        #expect(!coordinator.allowsWidgetRefresh, "Re-enabling aggregates must not silently restore local reads")
    }

    @Test func aForegroundAddressChangeAndDemoRoundTripRequireNewCompleteObservations() throws {
        let now = Date()
        var preparation = FleetWidgetRefreshPreparation()
        var device = MinerDevice(name: "Fixture", address: "10.23.45.1")
        let old = snapshot(at: now.addingTimeInterval(-1))
        #expect(preparation.targets(devices: [device], snapshots: [device.id: old], isDemo: false, now: now) == nil)
        let fresh = snapshot(at: now.addingTimeInterval(1))
        #expect(preparation.targets(devices: [device], snapshots: [device.id: fresh], isDemo: false,
            now: now.addingTimeInterval(1))?.count == 1)
        device.address = "10.23.45.2"
        #expect(preparation.targets(devices: [device], snapshots: [device.id: fresh], isDemo: false,
            now: now.addingTimeInterval(2)) == nil)
        let replacement = snapshot(at: now.addingTimeInterval(3))
        #expect(preparation.targets(devices: [device], snapshots: [device.id: replacement], isDemo: false,
            now: now.addingTimeInterval(3))?.first?.baseURL.host == "10.23.45.2")
        device.address = "10.23.45.1"
        #expect(preparation.targets(devices: [device], snapshots: [device.id: replacement], isDemo: false,
            now: now.addingTimeInterval(4)) == nil, "Address ABA must invalidate the earlier snapshot")
        let newer = snapshot(at: now.addingTimeInterval(5))
        #expect(preparation.targets(devices: [device], snapshots: [device.id: newer], isDemo: false,
            now: now.addingTimeInterval(5)) != nil)
        #expect(preparation.targets(devices: [device], snapshots: [device.id: newer], isDemo: true,
            now: now.addingTimeInterval(6)) == nil)
        #expect(preparation.targets(devices: [device], snapshots: [device.id: newer], isDemo: false,
            now: now.addingTimeInterval(7)) == nil)
        #expect(preparation.targets(devices: [device], snapshots: [device.id: snapshot(at: now.addingTimeInterval(8))],
            isDemo: false, now: now.addingTimeInterval(8)) != nil)
    }

    @Test func backgroundUpdatesCannotPrepareOrRenewButCanRevokeLocalPermission() throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        fixture.preferences.set(true, forKey: "app.hashfleet.shareWithWidgets")
        fixture.preferences.set(true, forKey: "app.hashfleet.allowWidgetRefresh")
        let coordinator = fixture.coordinator()
        #expect(!coordinator.widgetRefreshStatus.hasPrefix("Off."))
        let now = Date()
        let device = MinerDevice(name: "Fixture", address: "10.23.45.1")
        coordinator.updateWidgetRefreshFleet(devices: [device], snapshots: [:], isDemo: false,
            isForeground: false, now: now)
        let preparedAt = now.addingTimeInterval(1)
        let fresh = [device.id: snapshot(at: preparedAt)]
        coordinator.updateWidgetRefreshFleet(devices: [device], snapshots: fresh, isDemo: false,
            isForeground: false, now: preparedAt)
        #expect(fixture.refresh.storage.load() == nil)
        coordinator.updateWidgetRefreshFleet(devices: [device], snapshots: fresh, isDemo: false,
            isForeground: true, now: preparedAt)
        let initial = try #require(fixture.refresh.storage.load()?.configuration)
        let backgroundAt = preparedAt.addingTimeInterval(3_601)
        coordinator.updateWidgetRefreshFleet(devices: [device], snapshots: [device.id: snapshot(at: backgroundAt)],
            isDemo: false, isForeground: false, now: backgroundAt)
        let retained = try #require(fixture.refresh.storage.load()?.configuration)
        #expect(retained.generation == initial.generation)
        #expect(retained.expiresAt == initial.expiresAt)
        coordinator.updateWidgetRefreshFleet(devices: [device], snapshots: [:], isDemo: true,
            isForeground: false, now: backgroundAt)
        #expect(fixture.refresh.storage.load() == nil)
    }

    @Test func aStorageFailureCannotClaimThatPermissionWasRemoved() throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let coordinator = fixture.coordinator()
        let now = Date()
        coordinator.setWidgetSharing(true, glance: fixture.glance(at: now))
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: now))
        // Corrupt only this disposable fixture's lock path to reproduce a filesystem failure.
        let lock = fixture.refresh.directory.appendingPathComponent(HashFleet.FleetWidgetRefreshStorage.lockFilename)
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        coordinator.setWidgetSharing(false, glance: fixture.glance(at: now))
        #expect(coordinator.error != nil)
        #expect(coordinator.widgetRefreshStatus.contains("could not be removed"))
        #expect(!coordinator.widgetRefreshStatus.hasPrefix("Off."))
    }

    @Test(arguments: ["cached", "reconnecting", "error", "stale", "partial", "ambiguousMAC", "malformedMAC", "credential", "xmrig", "hostname"])
    func unsafeForegroundPreparationIsAllOrNothing(kind: String) {
        var preparation = FleetWidgetRefreshPreparation()
        var device = MinerDevice(name: "Fixture", address: "10.23.45.1")
        if kind == "credential" { device.keychainCredentialReference = "private-fixture-reference" }
        if kind == "xmrig" { device.kind = .xmrig }
        if kind == "hostname" { device.address = "fixture.local" }
        let now = Date()
        _ = preparation.targets(devices: [device], snapshots: [:], isDemo: false, now: now.addingTimeInterval(-1))
        var value = snapshot(at: now)
        switch kind {
        case "cached": value.isCached = true
        case "reconnecting": value.isReconnecting = true
        case "error": value.error = "fixture failure"
        case "stale": value.completeSnapshotAt = now.addingTimeInterval(-61)
        case "partial": value.completeSnapshotAt = nil
        case "ambiguousMAC": value.info = MinerInfo(raw: ["macAddr": .string("02:11:22:33:44:01"), "mac": .string("02:11:22:33:44:02")])
        case "malformedMAC": value.info = MinerInfo(raw: ["macAddr": .string("invalid")])
        default: break
        }
        #expect(preparation.targets(devices: [device], snapshots: [device.id: value], isDemo: false, now: now) == nil)
    }

    @Test func realDemoChangeAndOptOutDuringIntentAwaitCannotRecreateState() async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        let device = MinerDevice(name: "Fixture", address: "10.23.45.1")
        let coordinator = fixture.coordinator()
        coordinator.setWidgetSharing(true, glance: fixture.glance(at: now))
        coordinator.updateWidgetRefreshFleet(devices: [device], snapshots: [:], isDemo: false, now: now)
        coordinator.setWidgetRefreshEnabled(true, devices: [device], snapshots: [device.id: snapshot(at: now.addingTimeInterval(1))],
            isDemo: false, now: now.addingTimeInterval(1))
        let gate = WidgetRefreshGate()
        let readAt = now.addingTimeInterval(2)
        let task = Task {
            await HashFleet.RefreshFleetWidgetIntent().refresh(using: .init(storage: fixture.refresh.storage, read: { _ in
                await gate.pause(); return .init(hashRateGHs: 1_200, powerW: 19)
            }, now: { readAt }))
        }
        await gate.waitForEntry()
        coordinator.updateWidgetRefreshFleet(devices: [device], snapshots: [:], isDemo: true, now: readAt)
        coordinator.setWidgetSharing(false, glance: fixture.glance(at: readAt))
        await gate.release()
        #expect(await task.value == .needsSetup)
        #expect(fixture.refresh.storage.load() == nil)
        #expect(try fixture.provider().snapshot(at: readAt).refresh == nil)
    }

    @Test func actionAwaitsPersistenceAndTheSeparatelyCompiledProviderUsesRealObservationTime() async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        #expect(fixture.cacheStorage.save(fixture.glance(at: now.addingTimeInterval(-90))))
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: now))
        let gate = WidgetRefreshGate()
        let action = Task {
            await HashFleet.RefreshFleetWidgetIntent().refresh(using: .init(storage: fixture.refresh.storage, read: { target in
                #expect(target.name == "Miner")
                await gate.pause(); return .init(hashRateGHs: 1_200, powerW: 19)
            }, now: { now }))
        }
        await gate.waitForEntry()
        #expect(fixture.refresh.storage.load()?.glance == nil)
        #expect(try fixture.provider().snapshot(at: now).glance.updatedAt == now.addingTimeInterval(-90))
        await gate.release()
        #expect(await action.value == .refreshed)
        let provider = try fixture.provider()
        let result = provider.snapshot(at: now)
        #expect(result.glance.hashrateGHs == 1_200 && result.glance.powerWatts == 19)
        #expect(result.glance.updatedAt == now)
        #expect(result.refresh?.isEnabled == true && result.refresh?.message == nil)
        let timeline = provider.timeline(at: now)
        #expect(timeline.policy == .after(now.addingTimeInterval(15 * 60)))
        #expect(timeline.entries.last?.date == now.addingTimeInterval(60))
        #expect(timeline.entries.last?.glance.updatedAt == now)
        #expect(timeline.entries.last?.presentation.badge == "STALE")
        // The legacy six-field payload is unchanged and not overwritten by extension-side work.
        #expect(fixture.cacheStorage.load().updatedAt == now.addingTimeInterval(-90))
        let bytes = try Data(contentsOf: fixture.refresh.file)
        let json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let config = try #require(json["configuration"] as? [String: Any])
        let targets = try #require(config["targets"] as? [[String: Any]])
        #expect(Set(targets[0].keys) == ["id", "baseURL", "expectedMAC"])
        let decodedConfig = try #require(String(bytes: bytes, encoding: .utf8))
        #expect(!decodedConfig.contains("Private fixture name"))
        #expect(HashFleet.RefreshFleetWidgetIntent.openAppWhenRun == false)
        #expect(HashFleet.RefreshFleetWidgetIntent.isDiscoverable == false)
        #expect(HashFleet.RefreshFleetWidgetIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
    }

    @Test func aNewerAppObservationDemoOrDifferentInventoryIsNeverReplaced() async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: now))
        #expect(await HashFleet.FleetWidgetRefreshRunner(storage: fixture.refresh.storage, read: { _ in
            .init(hashRateGHs: 1_200, powerW: 19)
        }, now: { now }).refresh() == .refreshed)
        var saved = fixture.glance(at: now.addingTimeInterval(1))
        #expect(fixture.cacheStorage.save(saved))
        #expect(try fixture.provider().snapshot(at: now.addingTimeInterval(1)).glance.hashrateGHs == saved.hashrateGHs)
        saved.isDemo = true
        #expect(fixture.cacheStorage.save(saved))
        let demo = try fixture.provider().snapshot(at: now)
        #expect(demo.glance.isDemo && demo.refresh == nil)
        saved.isDemo = false
        saved.minerCount = 2
        saved.updatedAt = now.addingTimeInterval(-90)
        #expect(fixture.cacheStorage.save(saved))
        #expect(try fixture.provider().snapshot(at: now).glance.minerCount == 2)
        #expect(try fixture.provider().snapshot(at: now).refresh?.isEnabled == false)
    }

    @Test func expiredPermissionRetainsTheNewestSavedReadingWithoutStartingReads() async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        #expect(fixture.cacheStorage.save(fixture.glance(at: now.addingTimeInterval(-90))))
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: now.addingTimeInterval(-86_370)))
        #expect(await HashFleet.FleetWidgetRefreshRunner(storage: fixture.refresh.storage, read: { _ in
            .init(hashRateGHs: 1_200, powerW: 19)
        }, now: { now }).refresh() == .refreshed)
        let expiry = now.addingTimeInterval(30)
        let entry = try fixture.provider().snapshot(at: expiry)
        #expect(entry.refresh?.isEnabled == false)
        #expect(entry.glance.updatedAt == now)
        #expect(entry.glance.hashrateGHs == 1_200)
        let calls = WidgetRefreshCalls()
        #expect(await HashFleet.FleetWidgetRefreshRunner(storage: fixture.refresh.storage, read: { _ in
            await calls.increment()
            return .init(hashRateGHs: 9_999, powerW: 999)
        }, now: { expiry }).refresh() == .needsSetup)
        #expect(await calls.value == 0)
    }

    @Test func failureKeepsTheVisibleSavedReadingAndExpiryRemovesTheAction() async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        let saved = fixture.glance(at: now.addingTimeInterval(-90))
        #expect(fixture.cacheStorage.save(saved))
        let configured = now.addingTimeInterval(-86_370)
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: configured))
        #expect(await HashFleet.RefreshFleetWidgetIntent().refresh(using: .init(storage: fixture.refresh.storage, read: { _ in
            throw URLError(.notConnectedToInternet)
        }, now: { now })) == .unavailable)
        let provider = try fixture.provider()
        let entry = provider.snapshot(at: now)
        #expect(entry.glance.updatedAt == saved.updatedAt)
        #expect(entry.presentation.badge == "STALE")
        #expect(entry.refresh?.message == "Refresh failed · saved reading")
        let expiry = now.addingTimeInterval(30)
        let expired = try #require(provider.timeline(at: now).entries.first { $0.date == expiry })
        #expect(expired.refresh?.isEnabled == false)
        #expect(expired.glance.updatedAt == saved.updatedAt)
        // Host the actual widget entry view. No test-supplied OCR words or fake accessibility text.
        let rendered = try await FleetViewRenderHarness.render(
            HashFleetWidgetTestSupport.FleetWidgetView(entry: entry), width: 184, height: 184)
        #expect(rendered.visibleText.contains("Hash Fleet"))
        #expect(rendered.visibleText.contains("Refresh failed"))
        let hidden = try await FleetViewRenderHarness.render(
            HashFleetWidgetTestSupport.FleetWidgetView(entry: entry).redacted(reason: .privacy), width: 184, height: 184)
        #expect(!hidden.visibleText.contains("0.80"))
        #expect(hidden.pngData != rendered.pngData)
    }

    @Test(arguments: ["small", "medium", "large"])
    func readyAndFailedActionLayoutsKeepRealMeasurementsLegibleAndPrivate(familyName: String) async throws {
        let family: WidgetFamily
        let size: CGSize
        switch familyName {
        case "small": family = .systemSmall; size = CGSize(width: 184, height: 184)
        case "medium": family = .systemMedium; size = CGSize(width: 360, height: 184)
        default: family = .systemLarge; size = CGSize(width: 360, height: 376)
        }
        let now = Date()
        // CLDR may use a narrow no-break space before AM/PM. The unchanged OCR harness
        // normalizes whitespace only, so apply that same operation to the expected format.
        let visibleTime = now.formatted(.dateTime.hour().minute().locale(Locale(identifier: "en_US")))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for scheme in [ColorScheme.light, .dark] {
            for message: String? in [nil, "Refresh failed · saved reading"] {
                let entry = HashFleetWidgetTestSupport.FleetWidgetEntry(date: now,
                    glance: .init(updatedAt: now, onlineCount: 1, minerCount: 1, hashrateGHs: 1_200,
                        powerWatts: 19, isDemo: false), refresh: .init(isEnabled: true, message: message))
                let content = HashFleetWidgetTestSupport.FleetWidgetContent(entry: entry, family: family)
                    .background(HashFleetWidgetTestSupport.FleetWidgetTheme.canvas)
                    .preferredColorScheme(scheme)
                    // A widget gets its family rectangle, not the host phone's status-bar inset.
                    // Keep the shared render harness unchanged and bound only this fixture.
                    .frame(width: size.width, height: size.height)
                    .ignoresSafeArea()
                let rendered = try await FleetViewRenderHarness.render(content, width: size.width, height: size.height)
                #expect(rendered.visibleText.contains("Hash Fleet"))
                #expect(rendered.visibleText.contains("1.20"))
                #expect(rendered.visibleText.contains(visibleTime), "The saved observation time must fit inside every widget family")
                if message != nil { #expect(rendered.visibleText.contains("Refresh failed")) }
                let hidden = try await FleetViewRenderHarness.render(content.redacted(reason: .privacy),
                    width: size.width, height: size.height)
                #expect(!hidden.visibleText.contains("1.20"))
                #expect(hidden.pngData != rendered.pngData)
            }
        }
    }

    @Test(arguments: [false, true])
    func aRealInFlightReadShowsLoadingThenClearsForSuccessOrFailure(fails: Bool) async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        let saved = fixture.glance(at: now.addingTimeInterval(-120))
        #expect(fixture.cacheStorage.save(saved))
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: saved.updatedAt))
        let gate = WidgetRefreshGate()
        let calls = WidgetRefreshCalls()
        let runner = HashFleet.FleetWidgetRefreshRunner(storage: fixture.refresh.storage, read: { _ in
            await calls.increment()
            await gate.pause()
            if fails { throw URLError(.notConnectedToInternet) }
            return .init(hashRateGHs: 1_200, powerW: 19)
        }, now: { now })
        let provider = try fixture.provider()
        let task = Task { await HashFleet.RefreshFleetWidgetIntent().refresh(using: runner) }
        await gate.waitForEntry()
        let pending = provider.snapshot(at: now)
        #expect(pending.refresh?.isRefreshing == true)
        #expect(pending.refresh?.message == "Refreshing…")
        #expect(pending.glance.updatedAt == saved.updatedAt)
        #expect(provider.snapshot(at: now.addingTimeInterval(-1)).refresh?.isRefreshing == false)
        let expiry = now.addingTimeInterval(15)
        let recovery = provider.timeline(at: now).entries.first { $0.date == expiry }
        #expect(recovery?.refresh?.isRefreshing == false)
        #expect(recovery?.refresh?.message == "Refresh timed out · saved reading")
        #expect(recovery?.glance.updatedAt == saved.updatedAt)
        let permissionExpired = provider.snapshot(at: saved.updatedAt.addingTimeInterval(86_400))
        #expect(permissionExpired.refresh?.isEnabled == false)
        #expect(permissionExpired.refresh?.isRefreshing == false)
        #expect(await runner.refresh() == .busy)
        #expect(await calls.value == 1, "Repeated taps must not start a second network read")
        await gate.release()
        #expect(await task.value == (fails ? .unavailable : .refreshed))
        let finished = provider.snapshot(at: now)
        #expect(finished.refresh?.isRefreshing == false)
        #expect(finished.refresh?.message == (fails ? "Refresh failed · saved reading" : nil))
        #expect(finished.glance.updatedAt == (fails ? saved.updatedAt : now))
        #expect(fixture.refresh.storage.load()?.lease == nil)
    }

    @Test func repeatedConcurrentIntentsCannotStartAnotherReadOrBypassCompletionCooldown() async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        let saved = fixture.glance(at: now.addingTimeInterval(-120))
        #expect(fixture.cacheStorage.save(saved))
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: saved.updatedAt))
        let gate = WidgetRefreshGate()
        let initialCalls = WidgetRefreshCalls()
        let duplicateCalls = WidgetRefreshCalls()
        let initialRunner = HashFleet.FleetWidgetRefreshRunner(storage: fixture.refresh.storage, read: { _ in
            await initialCalls.increment()
            await gate.pause()
            return .init(hashRateGHs: 1_200, powerW: 19)
        }, now: { now })
        let duplicateRunner = HashFleet.FleetWidgetRefreshRunner(storage: fixture.refresh.storage, read: { _ in
            await duplicateCalls.increment()
            return .init(hashRateGHs: 9_999, powerW: 999)
        }, now: { now })
        let initial = Task { await HashFleet.RefreshFleetWidgetIntent().refresh(using: initialRunner) }
        await gate.waitForEntry()
        let outcomes = await withTaskGroup(of: HashFleet.FleetWidgetRefreshOutcome.self) { group in
            for _ in 0..<32 {
                group.addTask { await HashFleet.RefreshFleetWidgetIntent().refresh(using: duplicateRunner) }
            }
            var results: [HashFleet.FleetWidgetRefreshOutcome] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(outcomes.count == 32)
        // A contender may fail closed at the bounded file-lock deadline, but may never read.
        #expect(outcomes.allSatisfy { $0 == .busy || $0 == .unavailable })
        #expect(await duplicateCalls.value == 0)
        #expect(await initialCalls.value == 1)
        let pending = try fixture.provider().snapshot(at: now)
        #expect(pending.refresh?.isRefreshing == true)
        #expect(pending.glance.updatedAt == saved.updatedAt)

        await gate.release()
        #expect(await initial.value == .refreshed)
        #expect(fixture.refresh.storage.load()?.lease == nil)
        let finished = try fixture.provider().snapshot(at: now)
        #expect(finished.refresh?.isRefreshing == false)
        #expect(finished.glance.updatedAt == now)
        for _ in 0..<32 {
            #expect(await HashFleet.RefreshFleetWidgetIntent().refresh(using: duplicateRunner) == .busy)
        }
        #expect(await duplicateCalls.value == 0)
        #expect(fixture.refresh.storage.load()?.glance?.hashrateGHs == 1_200)
    }

    @Test func cancellationClearsLoadingWithoutChangingTheSavedObservation() async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        let saved = fixture.glance(at: now.addingTimeInterval(-120))
        #expect(fixture.cacheStorage.save(saved))
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: saved.updatedAt))
        let gate = WidgetRefreshGate()
        let runner = HashFleet.FleetWidgetRefreshRunner(storage: fixture.refresh.storage, read: { _ in
            await gate.pause()
            return .init(hashRateGHs: 1_200, powerW: 19)
        }, now: { now })
        let provider = try fixture.provider()
        let task = Task { await runner.refresh() }
        await gate.waitForEntry()
        #expect(provider.snapshot(at: now).refresh?.isRefreshing == true)
        task.cancel()
        await gate.release()
        #expect(await task.value == .cancelled)
        let cancelled = provider.snapshot(at: now)
        #expect(cancelled.refresh?.isRefreshing == false)
        #expect(cancelled.refresh?.message == "Refresh stopped · saved reading")
        #expect(cancelled.glance.updatedAt == saved.updatedAt)
    }

    private func snapshot(at date: Date) -> MinerSnapshot {
        MinerSnapshot(info: MinerInfo(raw: ["macAddr": .string("02:11:22:33:44:01"), "hashRate": .number(1_200), "power": .number(19)]),
            updatedAt: date, completeSnapshotAt: date, powerObservedAt: date)
    }
}

@MainActor struct RefreshIntegrationFixture {
    let suite: String
    let preferences: UserDefaults
    let cache: UserDefaults
    let cacheStorage: HashFleet.FleetGlanceStorage
    let refresh: WidgetRefreshFixture
    init() throws {
        suite = "app.hashfleet.widget-local-refresh.\(UUID().uuidString)"
        preferences = try #require(UserDefaults(suiteName: suite))
        cache = try #require(UserDefaults(suiteName: suite + ".cache"))
        cacheStorage = .init(defaults: cache)
        refresh = try WidgetRefreshFixture()
    }
    func glance(at date: Date) -> HashFleet.FleetGlance {
        .init(updatedAt: date, onlineCount: 1, minerCount: 1, hashrateGHs: 800, powerWatts: 12, isDemo: false)
    }
    func coordinator() -> FleetGlanceCoordinator {
        .init(defaults: preferences, storage: cacheStorage, refreshStorage: refresh.storage,
            activityName: "Private widget refresh test \(suite)")
    }
    func provider(
        read: @escaping HashFleetWidgetTestSupport.FleetWidgetRefreshRunner.Read = { try await FleetScheduledCheckReader().read($0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> HashFleetWidgetTestSupport.FleetWidgetProvider {
        .init(storage: .init(defaults: try #require(UserDefaults(suiteName: suite + ".cache"))),
            refreshStorage: .init(directory: refresh.directory), read: read, now: now)
    }
    func clear() {
        preferences.removePersistentDomain(forName: suite)
        cache.removePersistentDomain(forName: suite + ".cache")
        refresh.clear()
    }
}
