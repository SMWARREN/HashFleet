import Foundation
import AppIntents
@preconcurrency import ActivityKit
import Testing
@testable import HashFleet

@Suite("Generation-bound widget to Live Activity handoff", .serialized)
struct FleetActivityRefreshHandoffTests: Sendable {
    private let date = Date(timeIntervalSince1970: 1_793_200_000)

    @Test func successfulReadDeliversExactObservationOnlyAfterPersistence() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: date))
        let generation = try #require(fixture.storage.load()?.configuration.generation)
        let receipts = ActivityRefreshReceipts()
        let outcome = await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            .init(hashRateGHs: 0, powerW: 0)
        }, now: { date }).refresh { receipt in
            #expect(receipt.isAuthorized(in: fixture.storage, at: date))
            #expect(fixture.storage.load()?.glance == receipt.glance)
            await receipts.append(receipt)
        }
        #expect(outcome == .refreshed)
        let values = await receipts.values
        #expect(values.count == 1)
        let receipt = try #require(values.first)
        #expect(receipt.generation == generation)
        #expect(receipt.glance.updatedAt == date)
        #expect(receipt.glance.hashrateGHs == 0 && receipt.glance.powerWatts == 0)
        #expect(!receipt.glance.isDemo)
    }

    @Test func failedReadNeverDeliversOrRewritesTheSavedTime() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: date))
        #expect(await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            .init(hashRateGHs: 100, powerW: 10)
        }, now: { date }).refresh() == .refreshed)
        let old = fixture.storage.load()?.glance
        let calls = WidgetRefreshCalls()
        let later = date.addingTimeInterval(20)
        #expect(await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            throw URLError(.notConnectedToInternet)
        }, now: { later }).refresh { _ in await calls.increment() } == .unavailable)
        #expect(await calls.value == 0)
        #expect(fixture.storage.load()?.glance == old)
    }

    @Test(arguments: [false, true])
    func revokedOrReplacedPermissionCannotDeliverAnInFlightRead(reenable: Bool) async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        let target = widgetRefreshTarget()
        #expect(fixture.storage.configure(targets: [target], now: date))
        let gate = WidgetRefreshGate()
        let calls = WidgetRefreshCalls()
        let task = Task {
            await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
                await gate.pause()
                return .init(hashRateGHs: 100, powerW: 10)
            }, now: { date }).refresh { _ in await calls.increment() }
        }
        await gate.waitForEntry()
        #expect(fixture.storage.revoke())
        if reenable { #expect(fixture.storage.configure(targets: [target], now: date)) }
        await gate.release()
        #expect(await task.value == .needsSetup)
        #expect(await calls.value == 0)
    }

    @Test func partialAndCancelledReadsNeverReachTheActivityBoundary() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        let targets = [widgetRefreshTarget()]
        #expect(fixture.storage.configure(targets: targets, now: date))
        let calls = WidgetRefreshCalls()
        #expect(await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            .init(hashRateGHs: 1, powerW: nil)
        }, now: { date }).refresh { _ in await calls.increment() } == .unavailable)
        let gate = WidgetRefreshGate()
        let later = date.addingTimeInterval(20)
        let task = Task {
            await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
                await gate.pause()
                return .init(hashRateGHs: 1, powerW: 1)
            }, now: { later }).refresh { _ in await calls.increment() }
        }
        await gate.waitForEntry()
        task.cancel()
        await gate.release()
        #expect(await task.value == .cancelled)
        #expect(await calls.value == 0)
        #expect(fixture.storage.load()?.glance == nil)
    }

    @Test func publishedReceiptExpiresAndRevocationCannotBeUndoneBySameTargets() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        let target = widgetRefreshTarget()
        #expect(fixture.storage.configure(targets: [target], now: date))
        let receipts = ActivityRefreshReceipts()
        #expect(await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            .init(hashRateGHs: 1, powerW: 1)
        }, now: { date }).refresh { receipt in await receipts.append(receipt) } == .refreshed)
        let receipt = try #require(await receipts.values.first)
        #expect(receipt.isAuthorized(in: fixture.storage, at: date.addingTimeInterval(59.999)))
        #expect(!receipt.isAuthorized(in: fixture.storage, at: date.addingTimeInterval(60)))
        #expect(!receipt.isAuthorized(in: fixture.storage, at: date.addingTimeInterval(-5.001)))
        #expect(fixture.storage.revoke())
        #expect(!receipt.hasCurrentPermission(in: fixture.storage, at: date))
        #expect(fixture.storage.configure(targets: [target], now: date))
        #expect(!receipt.isAuthorized(in: fixture.storage, at: date))
        #expect(!receipt.hasCurrentPermission(in: fixture.storage, at: date))
    }

    @Test func replacementRequiresExactGenerationRealFleetAndStrictlyNewerObservation() {
        let generation = UUID()
        let glance = FleetGlance(updatedAt: date, onlineCount: 1, minerCount: 1,
            hashrateGHs: 0, powerWatts: 0, isDemo: false)
        let receipt = FleetActivityRefreshPublication(generation: generation, glance: glance)
        var previous = glance
        previous.updatedAt = date.addingTimeInterval(-1)
        #expect(receipt.canReplace(previous, refreshGeneration: generation))
        #expect(!receipt.canReplace(previous, refreshGeneration: nil))
        #expect(!receipt.canReplace(previous, refreshGeneration: UUID()))
        #expect(!receipt.canReplace(glance, refreshGeneration: generation))
        previous.updatedAt = date.addingTimeInterval(1)
        #expect(!receipt.canReplace(previous, refreshGeneration: generation))
        previous.updatedAt = date.addingTimeInterval(-1)
        previous.isDemo = true
        #expect(!receipt.canReplace(previous, refreshGeneration: generation))
        previous.isDemo = false
        previous.minerCount = 2
        #expect(!receipt.canReplace(previous, refreshGeneration: generation))
        previous.minerCount = 1
        previous.hashrateGHs = .nan
        #expect(!receipt.canReplace(previous, refreshGeneration: generation))
    }

    @Test func newerReceiptDoesNotRevokeTheSamePermission() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: date))
        let receipts = ActivityRefreshReceipts()
        for offset in [0.0, 20.0] {
            let time = date.addingTimeInterval(offset)
            #expect(await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
                .init(hashRateGHs: 1, powerW: 1)
            }, now: { time }).refresh { receipt in await receipts.append(receipt) } == .refreshed)
        }
        let first = try #require(await receipts.values.first)
        #expect(!first.isAuthorized(in: fixture.storage, at: date.addingTimeInterval(20)))
        #expect(first.hasCurrentPermission(in: fixture.storage, at: date.addingTimeInterval(20)))
    }

    @Test func legacyAttributesDecodeAndSwiftDateEpochMatchesAPNsContentState() throws {
        let legacy = try JSONDecoder().decode(FleetActivityAttributes.self, from: Data("{\"name\":\"HashFleet\"}".utf8))
        #expect(legacy.refreshGeneration == nil)
        let attributes = FleetActivityAttributes(name: "HashFleet", refreshGeneration: UUID())
        let restored = try JSONDecoder().decode(FleetActivityAttributes.self, from: JSONEncoder().encode(attributes))
        #expect(restored.name == attributes.name && restored.refreshGeneration == attributes.refreshGeneration)
        let json = "{\"glance\":{\"updatedAt\":\(date.timeIntervalSince1970 - 978_307_200),\"onlineCount\":1,\"minerCount\":1,\"hashrateGHs\":0,\"powerWatts\":0,\"isDemo\":false}}"
        let content = try JSONDecoder().decode(FleetActivityAttributes.ContentState.self, from: Data(json.utf8))
        #expect(content.glance.updatedAt == date)
        #expect(content.glance.isValid && !content.glance.isDemo)
    }

    @Test func refreshIntentUsesAppProcessProtocolWithoutOpeningUI() {
        func requireLiveActivityIntent<T: LiveActivityIntent>(_: T.Type) {}
        requireLiveActivityIntent(RefreshFleetWidgetIntent.self)
        #expect(RefreshFleetWidgetIntent.openAppWhenRun == false)
        #expect(RefreshFleetWidgetIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
    }

    @MainActor @Test func persistedWidgetReadUpdatesExistingLocalActivityThroughSDK() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        let suite = "HashFleet.ActivityHandoffIntegration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "app.hashfleet.shareWithWidgets")
        defaults.set(true, forKey: "app.hashfleet.allowWidgetRefresh")
        // Stay inside the freshness window while leaving room for the next failed read's cooldown.
        let observationDate = Date().addingTimeInterval(-20)
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: observationDate))
        let generation = try #require(fixture.storage.load()?.configuration.generation)
        let activityName = "HashFleet Handoff Integration \(UUID().uuidString)"
        let coordinator = FleetGlanceCoordinator(defaults: defaults,
            storage: FleetGlanceStorage(defaults: defaults), refreshStorage: fixture.storage,
            activityName: activityName)
        try #require(coordinator.activitiesAllowed, "ActivityKit must be enabled for SDK acceptance")
        let initial = FleetGlance(updatedAt: observationDate.addingTimeInterval(-20),
            onlineCount: 1, minerCount: 1, hashrateGHs: 100, powerWatts: 10, isDemo: false)
        await coordinator.start(initial)
        do {
            #expect(coordinator.error == nil)
            let activity = try #require(Activity<FleetActivityAttributes>.activities.first {
                $0.attributes.name == activityName
            }, "The foreground test host must create an actual local Live Activity")
            #expect(activity.attributes.refreshGeneration == generation)
            #expect(activity.pushToken == nil)
            #expect(activity.content.state.glance == initial)

            let expected = FleetGlance(updatedAt: observationDate, onlineCount: 1, minerCount: 1,
                hashrateGHs: 2_400, powerWatts: 91.25, isDemo: false)
            let outcome = await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
                .init(hashRateGHs: 2_400, powerW: 91.25)
            }, now: { observationDate }).refresh { publication in
                await FleetActivityRefreshHandoff.deliver(publication, storage: fixture.storage,
                    activityName: activityName)
            }
            #expect(outcome == .refreshed)
            #expect(fixture.storage.load()?.glance == expected)
            // ActivityKit acknowledges update() before every Activity handle sees its content.
            // Wait for the exact observation, with a hard bound rather than accepting stale data.
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while activity.content.state.glance != expected && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(activity.content.state.glance == expected)
            #expect(activity.content.staleDate == observationDate.addingTimeInterval(FleetGlance.freshnessInterval))
            #expect(Activity<FleetActivityAttributes>.activities.filter {
                $0.attributes.name == activityName
            }.map(\.id) == [activity.id], "Refresh must update the existing activity, not create another")

            let later = Date()
            let failed = await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
                throw URLError(.notConnectedToInternet)
            }, now: { later }).refresh { publication in
                await FleetActivityRefreshHandoff.deliver(publication, storage: fixture.storage,
                    activityName: activityName)
            }
            #expect(failed == .unavailable)
            #expect(activity.content.state.glance == expected)
            #expect(activity.content.staleDate == observationDate.addingTimeInterval(FleetGlance.freshnessInterval))
        } catch {
            await coordinator.stop()
            throw error
        }
        await coordinator.stop()
        #expect(!Activity<FleetActivityAttributes>.activities.contains {
            $0.attributes.name == activityName && ($0.activityState == .active || $0.activityState == .stale)
        })
    }
}

private actor ActivityRefreshReceipts {
    private(set) var values: [FleetActivityRefreshPublication] = []
    func append(_ value: FleetActivityRefreshPublication) { values.append(value) }
}
