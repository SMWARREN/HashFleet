import AppIntents
import Foundation
import SwiftUI
import Testing
import WidgetKit
import HashFleetCore
@testable import HashFleet
@testable import HashFleetWidgetTestSupport

@Suite("Automatic widget timeline reads", .serialized) @MainActor
struct FleetAutomaticWidgetTimelineTests {
    private let date = Date(timeIntervalSince1970: 1_793_200_000)

    @Test func scheduledTimelineFetchesWithoutAnIntentAndKeepsTheActualReadTime() async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let prepared = date.addingTimeInterval(-120)
        #expect(fixture.cacheStorage.save(fixture.glance(at: prepared)))
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: prepared, automatically: true))
        let calls = WidgetRefreshCalls()
        let provider = try fixture.provider(read: { _ in
            await calls.increment()
            return .init(hashRateGHs: 1_200, powerW: 19)
        }, now: { date })
        let timeline = await provider.automaticTimeline()
        #expect(await calls.value == 1)
        #expect(timeline.entries.first?.glance.updatedAt == date)
        #expect(timeline.entries.first?.glance.hashrateGHs == 1_200)
        #expect(fixture.refresh.storage.load()?.glance?.updatedAt == date)
        #expect(fixture.refresh.storage.load()?.configuration.expiresAt == prepared.addingTimeInterval(86_400))
        #expect(timeline.policy == .after(date.addingTimeInterval(5 * 60)))
        _ = await provider.automaticTimeline()
        #expect(await calls.value == 1)
        let aged = provider.snapshot(at: date.addingTimeInterval(61))
        #expect(aged.glance.updatedAt == date)
        #expect(aged.glance.isStale(at: date.addingTimeInterval(61)))
        #expect(aged.refresh?.message == "Auto refresh · waiting for iOS")
    }

    @Test func coldProvidersRepeatAutomaticReadsWithoutRenewingPermissionOrTheAggregateCache() async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let prepared = date.addingTimeInterval(-120)
        let aggregate = fixture.glance(at: prepared)
        #expect(fixture.cacheStorage.save(aggregate))
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: prepared, automatically: true))
        let permission = try #require(fixture.refresh.storage.load()?.configuration)
        let calls = WidgetRefreshCalls()

        // These are independently invoked providers with an injected clock, not simulated iOS wakes.
        // Their aggregate cache intentionally stays old so the transactional result must win.
        for (index, offset) in [0.0, 300.0, 3_600.0].enumerated() {
            let observedAt = date.addingTimeInterval(offset)
            let provider = try fixture.provider(read: { _ in
                await calls.increment()
                return .init(hashRateGHs: 1_200 + Double(index), powerW: 19)
            }, now: { observedAt })
            let timeline = await provider.automaticTimeline()
            #expect(await calls.value == index + 1)
            #expect(timeline.entries.first?.glance.updatedAt == observedAt)
            #expect(timeline.entries.first?.glance.hashrateGHs == 1_200 + Double(index))
            #expect(timeline.policy == .after(observedAt.addingTimeInterval(300)))
            #expect(fixture.cacheStorage.load() == aggregate)
            #expect(fixture.refresh.storage.load()?.configuration == permission)

            let freshAt = observedAt.addingTimeInterval(30)
            let anotherColdProvider = try fixture.provider(read: { _ in
                await calls.increment()
                return .init(hashRateGHs: 9_999, powerW: 999)
            }, now: { freshAt })
            let fresh = await anotherColdProvider.automaticTimeline()
            #expect(await calls.value == index + 1)
            #expect(fresh.entries.first?.glance.updatedAt == observedAt)
        }

        let expiredProvider = try fixture.provider(read: { _ in
            await calls.increment()
            return .init(hashRateGHs: 9_999, powerW: 999)
        }, now: { permission.expiresAt })
        let expired = await expiredProvider.automaticTimeline()
        #expect(await calls.value == 3)
        #expect(expired.entries.first?.glance.updatedAt == date.addingTimeInterval(3_600))
        #expect(expired.entries.first?.refresh?.isEnabled == false)
        #expect(fixture.refresh.storage.load()?.configuration == permission)
    }

    @Test func aNewerAggregateCacheWinsWithoutBeingReplacedByAnOlderRefreshReceipt() async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let prepared = date.addingTimeInterval(-120)
        #expect(fixture.cacheStorage.save(fixture.glance(at: prepared)))
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: prepared, automatically: true))
        let calls = WidgetRefreshCalls()
        let first = try fixture.provider(read: { _ in
            await calls.increment()
            return .init(hashRateGHs: 1_200, powerW: 19)
        }, now: { date })
        _ = await first.automaticTimeline()
        #expect(await calls.value == 1)

        let newerAt = date.addingTimeInterval(300)
        let newer = fixture.glance(at: newerAt)
        #expect(fixture.cacheStorage.save(newer))
        let cold = try fixture.provider(read: { _ in
            await calls.increment()
            throw URLError(.notConnectedToInternet)
        }, now: { newerAt })
        let cached = await cold.automaticTimeline()
        #expect(await calls.value == 1)
        #expect(cached.entries.first?.glance.updatedAt == newerAt)
        #expect(cached.entries.first?.glance.hashrateGHs == newer.hashrateGHs)

        let staleAt = newerAt.addingTimeInterval(60)
        let failedProvider = try fixture.provider(read: { _ in
            await calls.increment()
            throw URLError(.notConnectedToInternet)
        }, now: { staleAt })
        let failed = await failedProvider.automaticTimeline()
        #expect(await calls.value == 2)
        #expect(failed.entries.first?.glance.updatedAt == newerAt)
        #expect(failed.entries.first?.refresh?.message == "Refresh failed · saved reading")
        #expect(fixture.refresh.storage.load()?.glance?.updatedAt == date)
        #expect(fixture.cacheStorage.load() == newer)
    }

    @Test(arguments: ["manualOnly", "preview", "fresh", "expired", "demo", "differentInventory", "missing"])
    func scheduledTimelineNeverReadsOutsideItsGrant(kind: String) async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let prepared = date.addingTimeInterval(kind == "expired" ? -86_400 : -120)
        var saved = fixture.glance(at: kind == "fresh" ? date : prepared)
        saved.isDemo = kind == "demo"
        if kind == "differentInventory" { saved.minerCount = 2 }
        #expect(fixture.cacheStorage.save(saved))
        if kind != "missing" {
            #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: prepared,
                automatically: kind != "manualOnly"))
        }
        let calls = WidgetRefreshCalls()
        let provider = try fixture.provider(read: { _ in
            await calls.increment()
            return .init(hashRateGHs: 9_999, powerW: 999)
        }, now: { date })
        _ = provider.snapshot(at: date)
        _ = provider.timeline(at: date)
        let timeline = await provider.automaticTimeline(isPreview: kind == "preview")
        #expect(await calls.value == 0)
        #expect(timeline.entries.first?.glance.updatedAt == saved.updatedAt)
        #expect(fixture.refresh.storage.load()?.glance == nil)
    }

    @Test func failedAutomaticReadDoesNotFabricateFreshnessOrRetryInsideCooldown() async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let prepared = date.addingTimeInterval(-120)
        #expect(fixture.cacheStorage.save(fixture.glance(at: prepared)))
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget()], now: prepared, automatically: true))
        let calls = WidgetRefreshCalls()
        let provider = try fixture.provider(read: { _ in
            await calls.increment()
            throw URLError(.notConnectedToInternet)
        }, now: { date })
        let failed = await provider.automaticTimeline()
        #expect(await calls.value == 1)
        #expect(failed.entries.first?.glance.updatedAt == prepared)
        #expect(failed.entries.first?.refresh?.message == "Refresh failed · saved reading")
        _ = await provider.automaticTimeline()
        #expect(await calls.value == 1)
        #expect(fixture.refresh.storage.load()?.lastOutcome == .unavailable)
    }

    @Test func automaticConsentIsSeparateAndClearedWithLocalPermission() throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let device = MinerDevice(name: "Private fixture", address: "10.23.45.1")
        let snapshot = MinerSnapshot(info: MinerInfo(raw: ["macAddr": .string("02:11:22:33:44:01"),
            "hashRate": .number(1_200), "power": .number(19)]), updatedAt: date,
            completeSnapshotAt: date, powerObservedAt: date)
        let coordinator = fixture.coordinator()
        coordinator.setWidgetSharing(true, glance: fixture.glance(at: date))
        coordinator.setWidgetRefreshEnabled(true, devices: [device], snapshots: [device.id: snapshot],
            isDemo: false, now: date)
        #expect(!coordinator.allowsAutomaticWidgetRefresh)
        let initial = try #require(fixture.refresh.storage.load()?.configuration)
        #expect(initial.automaticRefreshGeneration == nil)
        coordinator.setAutomaticWidgetRefreshEnabled(true, devices: [device], snapshots: [device.id: snapshot],
            isDemo: false, now: date)
        #expect(coordinator.allowsAutomaticWidgetRefresh)
        #expect(fixture.refresh.storage.load()?.configuration.automaticRefreshGeneration != nil)
        #expect(fixture.refresh.storage.load()?.configuration.generation == initial.generation)
        coordinator.setWidgetRefreshEnabled(false, devices: [device], snapshots: [:], isDemo: false, now: date)
        #expect(!coordinator.allowsAutomaticWidgetRefresh)
        #expect(fixture.refresh.storage.load() == nil)
        coordinator.setWidgetRefreshEnabled(true, devices: [device], snapshots: [device.id: snapshot],
            isDemo: false, now: date)
        #expect(!coordinator.allowsAutomaticWidgetRefresh)
        #expect(fixture.refresh.storage.load()?.configuration.automaticRefreshGeneration == nil)
    }

    @Test func coldBackgroundOwnerPreservesAutomaticConsentWithoutRenewingIt() throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let device = MinerDevice(name: "Private fixture", address: "10.23.45.1")
        fixture.preferences.set(true, forKey: "app.hashfleet.shareWithWidgets")
        fixture.preferences.set(true, forKey: "app.hashfleet.allowWidgetRefresh")
        fixture.preferences.set(true, forKey: "app.hashfleet.allowAutomaticWidgetRefresh")
        #expect(fixture.refresh.storage.configure(targets: [widgetRefreshTarget(id: device.id)],
            now: date.addingTimeInterval(-3_601), automatically: true))
        let initial = try #require(fixture.refresh.storage.load()?.configuration)
        let cold = fixture.coordinator()
        cold.updateWidgetRefreshFleet(devices: [device], snapshots: [:], isDemo: false,
            isForeground: false, now: date)
        #expect(cold.allowsAutomaticWidgetRefresh)
        #expect(fixture.refresh.storage.load()?.configuration == initial)
        cold.setWidgetSharing(false, glance: fixture.glance(at: date))
        #expect(!cold.allowsAutomaticWidgetRefresh)
        #expect(fixture.refresh.storage.load() == nil)
        #expect(!fixture.preferences.bool(forKey: "app.hashfleet.allowAutomaticWidgetRefresh"))
    }
}
