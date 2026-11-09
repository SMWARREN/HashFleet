import Foundation
import SwiftUI
import Testing
@testable import HashFleet
@testable import HashFleetWidgetTestSupport

@Suite("Local refresh cache and widget workflow", .serialized) @MainActor
struct FleetGlanceWorkflowTests {
    @Test func aBackgroundPublisherCannotRestoreReadingsAfterAnotherCoordinatorOptsOut() async throws {
        let fixture = try CacheFixture()
        defer { fixture.clear() }
        let original = HashFleet.FleetGlance(updatedAt: Date().addingTimeInterval(-5), onlineCount: 1,
            minerCount: 1, hashrateGHs: 1_000, powerWatts: 15, isDemo: false)
        #expect(fixture.storage.save(original))
        let settings = fixture.coordinator()
        let background = fixture.coordinator()
        #expect(background.sharesWithWidgets)

        // The background coordinator captured consent before its local read finished.
        // A different foreground coordinator owns the user's subsequent opt-out.
        settings.setWidgetSharing(false, glance: original)
        #expect(fixture.storage.load() == .empty)
        let latest = HashFleet.FleetGlance(updatedAt: Date(), onlineCount: 1, minerCount: 1,
            hashrateGHs: 1_200, powerWatts: 18, isDemo: false)
        let complete = await FleetBackgroundGlancePublication.publish(
            latest, isComplete: true, expectedDemo: false
        ) { await background.publish($0) }

        #expect(complete, "Snapshot completeness is independent of sharing consent")
        #expect(!background.sharesWithWidgets, "A retained publisher must re-read current consent")
        #expect(fixture.storage.load() == .empty, "Opt-out must remain effective after an in-flight read")
        #expect(fixture.cache.data(forKey: HashFleet.FleetGlanceStorage.key) == nil)
        #expect(try fixture.provider().snapshot(at: Date()).glance == .empty)
    }

    @Test func aRealLocalPollPersistsThroughTheCoordinatorIntoTheProductionProviderAndView() async throws {
        let fixture = try CacheFixture()
        defer { fixture.clear() }
        let source = FleetTelemetryCompletenessTests()
        // Reuse the isolated HTTP fixture. Its URLProtocol handles every request, never the LAN.
        let poll = try await source.store([
            source.complete(hashrate: 1_200, power: 19),
            source.complete(hashrate: 1_200, power: 19), nil
        ])
        defer { poll.store.cancelRefresh(); poll.defaults.removePersistentDomain(forName: poll.suite) }
        #expect(poll.store.canPublishGlance)
        let observed = poll.store.glance
        #expect(observed.hashrateGHs == 2_400 && observed.powerWatts == 38)
        #expect(observed.onlineCount == 2 && observed.minerCount == 3)
        let coordinator = fixture.coordinator()
        let complete = await FleetBackgroundGlancePublication.publish(
            observed, isComplete: poll.store.canPublishGlance, expectedDemo: poll.store.isDemo
        ) { await coordinator.publish($0) }
        #expect(complete)
        #expect(fixture.storage.load() == observed)

        // Decode through the separately compiled widget module and a separate defaults object.
        // This checks the actual serialized contract, not a direct nominal-type conversion.
        let provider = try fixture.provider()
        let now = Date()
        let snapshot = provider.snapshot(at: now)
        #expect(snapshot.glance.updatedAt == observed.updatedAt)
        #expect(snapshot.glance.hashrateGHs == observed.hashrateGHs)
        #expect(snapshot.glance.powerWatts == observed.powerWatts)
        #expect(snapshot.glance.onlineCount == 2 && snapshot.glance.minerCount == 3)
        #expect(!snapshot.glance.isDemo)
        #expect(snapshot.presentation.badge == "RECENT")
        let timeline = provider.timeline(at: now)
        #expect(timeline.entries.count == 2)
        #expect(timeline.policy == .after(now.addingTimeInterval(15 * 60)))
        let stale = try #require(timeline.entries.last)
        #expect(stale.date == observed.updatedAt.addingTimeInterval(HashFleet.FleetGlance.freshnessInterval))
        #expect(stale.presentation.badge == "STALE")
        #expect(stale.glance.updatedAt == snapshot.glance.updatedAt)

        let data = try #require(fixture.cache.data(forKey: HashFleet.FleetGlanceStorage.key))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["updatedAt", "onlineCount", "minerCount", "hashrateGHs", "powerWatts", "isDemo"])
        // WidgetKit owns the read-only family environment. Exercise its actual medium
        // component and privacy modifier rather than pretending a host can select a family.
        let view = HashFleetWidgetTestSupport.FleetMediumWidget(
            presentation: snapshot.presentation, renderingMode: .fullColor)
            .modifier(HashFleetWidgetTestSupport.FleetWidgetPrivacy(presentation: snapshot.presentation))
        let visible = try await FleetViewRenderHarness.render(view, width: 360, height: 220)
        let hidden = try await FleetViewRenderHarness.render(
            view.redacted(reason: .privacy), width: 360, height: 220)
        #expect(visible.visibleText.contains("Hash Fleet"))
        #expect(visible.visibleText.contains("2.40 TH/s"))
        #expect(visible.visibleText.contains("38 W"))
        #expect(!hidden.visibleText.contains("2.40 TH/s"))
        #expect(!hidden.visibleText.contains("38 W"))
        #expect(visible.pngData != hidden.pngData)
    }

    @Test func anIncompleteLocalPollKeepsThePreviousObservationAndItsStaleTimeline() async throws {
        let fixture = try CacheFixture()
        defer { fixture.clear() }
        let previous = oldReading()
        #expect(fixture.storage.save(previous))
        let source = FleetTelemetryCompletenessTests()
        let poll = try await source.store([source.complete(hashrate: 1_200, power: 19), source.hostnameOnly])
        defer { poll.store.cancelRefresh(); poll.defaults.removePersistentDomain(forName: poll.suite) }
        #expect(!poll.store.canPublishGlance)
        let coordinator = fixture.coordinator()
        let complete = await FleetBackgroundGlancePublication.publish(
            poll.store.glance, isComplete: poll.store.canPublishGlance, expectedDemo: false
        ) { await coordinator.publish($0) }
        #expect(!complete)
        #expect(fixture.storage.load() == previous)
        let now = Date()
        let timeline = try fixture.provider().timeline(at: now)
        #expect(timeline.entries.count == 1)
        #expect(timeline.policy == .after(now.addingTimeInterval(15 * 60)))
        let entry = try #require(timeline.entries.first)
        #expect(entry.glance.updatedAt == previous.updatedAt)
        #expect(entry.glance.hashrateGHs == previous.hashrateGHs)
        #expect(entry.presentation.badge == "STALE")
        #expect(entry.presentation.status.contains("open app to refresh"))
    }

    @Test func aCancelledPublicationCannotReplaceTheStoredObservation() async throws {
        let fixture = try CacheFixture()
        defer { fixture.clear() }
        let previous = oldReading()
        #expect(fixture.storage.save(previous))
        let coordinator = fixture.coordinator()
        let latest = HashFleet.FleetGlance(updatedAt: Date(), onlineCount: 1, minerCount: 1,
            hashrateGHs: 1_200, powerWatts: 18, isDemo: false)
        let task = Task { @MainActor in
            await FleetBackgroundGlancePublication.publish(latest, isComplete: true, expectedDemo: false) {
                await coordinator.publish($0)
            }
        }
        task.cancel()
        #expect(await task.value == false)
        #expect(fixture.storage.load() == previous)
        #expect(try fixture.provider().snapshot(at: Date()).glance.updatedAt == previous.updatedAt)
    }

    @Test(arguments: [false, true])
    func aDemoIdentityChangeCannotRelabelThePersistedObservation(incomingDemo: Bool) async throws {
        let fixture = try CacheFixture()
        defer { fixture.clear() }
        var previous = oldReading()
        previous.isDemo = !incomingDemo
        #expect(fixture.storage.save(previous))
        let coordinator = fixture.coordinator()
        let latest = HashFleet.FleetGlance(updatedAt: Date(), onlineCount: 1, minerCount: 1,
            hashrateGHs: 1_200, powerWatts: 18, isDemo: incomingDemo)
        let complete = await FleetBackgroundGlancePublication.publish(
            latest, isComplete: true, expectedDemo: !incomingDemo
        ) { await coordinator.publish($0) }
        #expect(!complete)
        #expect(fixture.storage.load() == previous)
        let snapshot = try fixture.provider().snapshot(at: Date())
        #expect(snapshot.glance.isDemo == previous.isDemo)
        #expect(snapshot.glance.updatedAt == previous.updatedAt)
    }

    private func oldReading() -> HashFleet.FleetGlance {
        HashFleet.FleetGlance(updatedAt: Date().addingTimeInterval(-90), onlineCount: 1,
            minerCount: 2, hashrateGHs: 800, powerWatts: 12, isDemo: false)
    }

    @MainActor private struct CacheFixture {
        let preferenceSuite: String
        let cacheSuite: String
        let preferences: UserDefaults
        let cache: UserDefaults
        let storage: HashFleet.FleetGlanceStorage

        init() throws {
            let id = UUID().uuidString
            preferenceSuite = "app.hashfleet.workflow.preferences.\(id)"
            cacheSuite = "app.hashfleet.workflow.cache.\(id)"
            preferences = try #require(UserDefaults(suiteName: preferenceSuite))
            cache = try #require(UserDefaults(suiteName: cacheSuite))
            preferences.set(true, forKey: "app.hashfleet.shareWithWidgets")
            storage = HashFleet.FleetGlanceStorage(defaults: cache)
        }

        func coordinator() -> FleetGlanceCoordinator {
            FleetGlanceCoordinator(defaults: preferences, storage: storage,
                isTesting: false, activityName: "Hash Fleet isolated cache workflow \(preferenceSuite)")
        }

        func provider() throws -> HashFleetWidgetTestSupport.FleetWidgetProvider {
            let reader = try #require(UserDefaults(suiteName: cacheSuite))
            return HashFleetWidgetTestSupport.FleetWidgetProvider(
                storage: HashFleetWidgetTestSupport.FleetGlanceStorage(defaults: reader))
        }

        func clear() {
            preferences.removePersistentDomain(forName: preferenceSuite)
            cache.removePersistentDomain(forName: cacheSuite)
        }
    }
}
