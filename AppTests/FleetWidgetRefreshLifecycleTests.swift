import AppIntents
import Foundation
import SwiftUI
import Testing
import WidgetKit
import HashFleetCore
@testable import HashFleet
@testable import HashFleetWidgetTestSupport

@Suite("Prepared widget refresh lifetime", .serialized) @MainActor
struct FleetWidgetRefreshLifecycleTests {
    private func prepare(_ fixture: RefreshIntegrationFixture, device: MinerDevice, at date: Date) throws {
        fixture.preferences.set(true, forKey: "app.hashfleet.shareWithWidgets")
        fixture.preferences.set(true, forKey: "app.hashfleet.allowWidgetRefresh")
        #expect(fixture.cacheStorage.save(fixture.glance(at: date)))
        #expect(fixture.refresh.storage.configure(targets: [HashFleet.FleetWidgetRefreshTarget(
            id: device.id, baseURL: try device.validatedURL(), expectedMAC: "02:11:22:33:44:01"
        )], now: date))
    }

    private func snapshot(at date: Date) -> MinerSnapshot {
        MinerSnapshot(info: MinerInfo(raw: ["macAddr": .string("02:11:22:33:44:01"),
            "hashRate": .number(1_200), "power": .number(19)]), updatedAt: date,
            completeSnapshotAt: date, powerObservedAt: date)
    }

    @Test func coldBackgroundStartupKeepsPreparedReadAndIntentStillUpdatesWidget() async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        let device = MinerDevice(name: "Private fixture", address: "10.23.45.1")
        try prepare(fixture, device: device, at: now.addingTimeInterval(-120))
        let initial = try #require(fixture.refresh.storage.load()?.configuration)
        // A newly started app process has no complete in-memory frames yet.
        let cold = fixture.coordinator()
        cold.updateWidgetRefreshFleet(devices: [device], snapshots: [:], isDemo: false,
            isForeground: false, now: now)
        #expect(fixture.refresh.storage.load()?.configuration == initial)
        let reads = WidgetRefreshCalls()
        let outcome = await HashFleet.RefreshFleetWidgetIntent().refresh(using: .init(
            storage: fixture.refresh.storage, read: { _ in
                await reads.increment()
                return .init(hashRateGHs: 1_200, powerW: 19)
            }, now: { now }))
        #expect(outcome == .refreshed)
        #expect(await reads.value == 1)
        let entry = try fixture.provider().snapshot(at: now)
        #expect(entry.glance.updatedAt == now && entry.glance.hashrateGHs == 1_200)
        #expect(entry.refresh?.isEnabled == true && entry.refresh?.message == nil)
        #expect(fixture.refresh.storage.load()?.configuration == initial,
                "An intent must not renew or replace its existing permission")
    }

    @Test(arguments: [false, true], ["missing", "cached", "reconnecting", "error", "stale", "partial"])
    func incompleteFramesDoNotErasePreparedPermission(isForeground: Bool, kind: String) throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        let device = MinerDevice(name: "Private fixture", address: "10.23.45.1")
        try prepare(fixture, device: device, at: now.addingTimeInterval(-3_601))
        let before = try Data(contentsOf: fixture.refresh.file)
        var value = snapshot(at: now)
        switch kind {
        case "cached": value.isCached = true
        case "reconnecting": value.isReconnecting = true
        case "error": value.error = "Synthetic unavailable reading"
        case "stale": value.completeSnapshotAt = now.addingTimeInterval(-61)
        case "partial": value.completeSnapshotAt = nil
        default: break
        }
        fixture.coordinator().updateWidgetRefreshFleet(devices: [device],
            snapshots: kind == "missing" ? [:] : [device.id: value], isDemo: false,
            isForeground: isForeground, now: now)
        #expect(fixture.refresh.storage.load() != nil)
        #expect((try? Data(contentsOf: fixture.refresh.file)) == before,
                "Retaining prepared pins must neither renew permission nor discard saved data")
    }

    @Test(arguments: [false, true], ["demo", "address", "id", "kind", "credential", "removed", "duplicate", "hostname"])
    func changedSelectionStillRevokesPermission(isForeground: Bool, kind: String) throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        var device = MinerDevice(name: "Private fixture", address: "10.23.45.1")
        try prepare(fixture, device: device, at: now.addingTimeInterval(-120))
        switch kind {
        case "address": device.address = "10.23.45.2"
        case "id": device = MinerDevice(name: "Replacement", address: device.address)
        case "kind": device.kind = .xmrig
        case "credential": device.keychainCredentialReference = "synthetic-reference"
        case "hostname": device.address = "offline.invalid"
        default: break
        }
        let devices = kind == "removed" ? [] : (kind == "duplicate" ? [device, device] : [device])
        fixture.coordinator().updateWidgetRefreshFleet(devices: devices, snapshots: [:],
            isDemo: kind == "demo", isForeground: isForeground, now: now)
        #expect(fixture.refresh.storage.load() == nil)
    }

    @Test(arguments: ["changed", "ambiguous", "malformed"])
    func freshBackgroundIdentityContradictionsRevokeRatherThanRepin(kind: String) throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        let device = MinerDevice(name: "Private fixture", address: "10.23.45.1")
        try prepare(fixture, device: device, at: now.addingTimeInterval(-120))
        var value = snapshot(at: now)
        switch kind {
        case "changed": value.info = MinerInfo(raw: ["macAddr": .string("02:11:22:33:44:02")])
        case "ambiguous": value.info = MinerInfo(raw: ["macAddr": .string("02:11:22:33:44:01"),
            "mac": .string("02:11:22:33:44:02")])
        default: value.info = MinerInfo(raw: ["macAddr": .string("invalid")])
        }
        fixture.coordinator().updateWidgetRefreshFleet(devices: [device], snapshots: [device.id: value],
            isDemo: false, isForeground: false, now: now)
        #expect(fixture.refresh.storage.load() == nil)
    }

    @Test(arguments: [false, true])
    func expiryDisablesReadsWithoutErasingLastObservation(isForeground: Bool) async throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        let device = MinerDevice(name: "Private fixture", address: "10.23.45.1")
        try prepare(fixture, device: device, at: now.addingTimeInterval(-86_500))
        let observed = now.addingTimeInterval(-200)
        #expect(await HashFleet.FleetWidgetRefreshRunner(storage: fixture.refresh.storage,
            read: { _ in .init(hashRateGHs: 1_200, powerW: 19) }, now: { observed }).refresh() == .refreshed)
        let before = try Data(contentsOf: fixture.refresh.file)
        fixture.coordinator().updateWidgetRefreshFleet(devices: [device], snapshots: [:], isDemo: false,
            isForeground: isForeground, now: now)
        #expect((try? Data(contentsOf: fixture.refresh.file)) == before)
        let entry = try fixture.provider().snapshot(at: now)
        #expect(entry.glance.updatedAt == observed)
        #expect(entry.refresh?.isEnabled == false)
        let reads = WidgetRefreshCalls()
        #expect(await HashFleet.FleetWidgetRefreshRunner(storage: fixture.refresh.storage, read: { _ in
            await reads.increment(); return .init(hashRateGHs: 9_999, powerW: 999)
        }, now: { now }).refresh() == .needsSetup)
        #expect(await reads.value == 0)
    }

    @Test(arguments: ["sharing", "localRefresh"])
    func explicitOptOutStillRevokesOnAnExistingCoordinator(kind: String) throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        let device = MinerDevice(name: "Private fixture", address: "10.23.45.1")
        try prepare(fixture, device: device, at: now.addingTimeInterval(-120))
        let coordinator = fixture.coordinator()
        fixture.preferences.set(false, forKey: kind == "sharing"
            ? "app.hashfleet.shareWithWidgets" : "app.hashfleet.allowWidgetRefresh")
        coordinator.updateWidgetRefreshFleet(devices: [device], snapshots: [:], isDemo: false,
            isForeground: false, now: now)
        #expect(fixture.refresh.storage.load() == nil)
    }

    @Test func onlyFreshForegroundReadingsCanPrepareOrRenewPermission() throws {
        let fixture = try RefreshIntegrationFixture()
        defer { fixture.clear() }
        let now = Date()
        let device = MinerDevice(name: "Private fixture", address: "10.23.45.1")
        fixture.preferences.set(true, forKey: "app.hashfleet.shareWithWidgets")
        fixture.preferences.set(true, forKey: "app.hashfleet.allowWidgetRefresh")
        let cold = fixture.coordinator()
        cold.updateWidgetRefreshFleet(devices: [device], snapshots: [device.id: snapshot(at: now)],
            isDemo: false, isForeground: false, now: now)
        #expect(fixture.refresh.storage.load() == nil)
        try prepare(fixture, device: device, at: now.addingTimeInterval(-3_601))
        let initial = try #require(fixture.refresh.storage.load()?.configuration)
        cold.updateWidgetRefreshFleet(devices: [device], snapshots: [:], isDemo: false,
            isForeground: true, now: now)
        #expect(fixture.refresh.storage.load()?.configuration == initial)
        let fresh = now.addingTimeInterval(1)
        cold.updateWidgetRefreshFleet(devices: [device], snapshots: [device.id: snapshot(at: fresh)],
            isDemo: false, isForeground: true, now: fresh)
        let renewed = try #require(fixture.refresh.storage.load()?.configuration)
        #expect(renewed.generation == initial.generation && renewed.createdAt == initial.createdAt)
        #expect(renewed.renewedAt == fresh && renewed.expiresAt == fresh.addingTimeInterval(86_400))
    }
}
