import SwiftUI
import Testing
import HashFleetCore
@testable import HashFleet

@Suite(.serialized)
@MainActor
struct MinerLiveAndXMRigIsolationCoverageTests {
    @Test func releaseDashboardOmitsCPUCardsAndCPUHistoryPicker() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let esp = try #require(fixture.store.devices.first)
        var cpu = try #require(fixture.store.devices.last)
        cpu.kind = .xmrig
        cpu.name = "AAA Hidden CPU Sentinel"
        fixture.store.devices = [cpu, esp]
        let rendered = try await FleetViewRenderHarness.render(
            NavigationStack { DashboardView(store: fixture.store, insights: fixture.insights) },
            width: 1_100, height: 1_600)
        #expect(rendered.visibleText.contains("SAMPLE FLEET HASHRATE"))
        #expect(!rendered.visibleText.contains("Hidden CPU Sentinel"))
        #expect(!rendered.visibleText.contains("XMRig"))
        #expect(FleetHistoryKind.available(in: fixture.store.visibleDevices) == [.sha256])
        #expect(fixture.store.devices == [cpu, esp])
    }

    @Test func releaseHidesAddPickerAndCPUDetailWithoutRemovingConfiguration() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        var device = try #require(fixture.store.devices.first)
        device.kind = .xmrig
        fixture.store.devices = [device]
        let add = try await FleetViewRenderHarness.render(AddMinerView(store: fixture.store), height: 1_200)
        #expect(!add.visibleText.contains("XMRig"))
        let detail = try await FleetViewRenderHarness.render(
            NavigationStack { MinerDetailView(device: device, store: fixture.store) }, height: 1_000)
        #expect(detail.visibleText.contains("unavailable in this release"))
        #expect(!detail.visibleText.contains("XMRig control"))
        #expect(!detail.visibleText.contains("Hashrate trend"))
        #expect(fixture.store.devices == [device])
        #expect(fixture.store.visibleDevices.isEmpty)
    }
    @Test func xmrigCachedStaleAndOfflineSnapshotsNeverClaimCurrentMining() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let info = MinerInfo(raw: ["hashRate": .integer(0), "miningPaused": .bool(false)])
        let current = MinerSnapshot(info: info, updatedAt: now)
        #expect(XMRigControlView.stateLabel(snapshot: current, now: now) == "Mining")
        var paused = current
        paused.info = MinerInfo(raw: ["hashRate": .integer(0), "miningPaused": .bool(true)])
        #expect(XMRigControlView.stateLabel(snapshot: paused, now: now) == "Paused")
        var cached = current
        cached.isCached = true
        var offline = current
        offline.error = "Fixture offline"
        var reconnecting = current
        reconnecting.isReconnecting = true
        var stale = current
        stale.updatedAt = now.addingTimeInterval(-181)
        for snapshot in [cached, offline, reconnecting, stale, MinerSnapshot()] {
            #expect(XMRigControlView.stateLabel(snapshot: snapshot, now: now).contains("Offline or stale"))
            #expect(!MinerWriteAvailability.allows(snapshot, now: now))
        }
        var unchangedButRevalidated = stale
        unchangedButRevalidated.completeSnapshotAt = now
        #expect(XMRigControlView.stateLabel(snapshot: unchangedButRevalidated, now: now) == "Mining")
        unchangedButRevalidated.isCached = true
        #expect(!MinerWriteAvailability.allows(unchangedButRevalidated, now: now))
    }
    @Test(arguments: [false, true])
    func statusStripSeparatesDemoConnectedAndLivePresentation(_ live: Bool) async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let detail = MinerDetailView(device: device, store: fixture.store, isLive: live)

        let demo = try await FleetViewRenderHarness.render(detail.statusStrip)
        #expect(demo.visibleText.contains("DEMO"))
        #expect(demo.visibleText.contains("READ ONLY"))
        #expect(!demo.visibleText.contains("CONNECTED"))
        #expect(!demo.visibleText.contains("LIVE"))
        #expect(detail.isDetailOnline)

        fixture.store.isDemo = false
        let connected = try await FleetViewRenderHarness.render(detail.statusStrip)
        #expect(connected.visibleText.contains(live ? "LIVE" : "CONNECTED"))
        #expect(!connected.visibleText.contains("DEMO"))
        #expect(!connected.visibleText.contains("READ ONLY"))

        fixture.store.snapshots[device.id] = MinerSnapshot(
            info: nil,
            error: "Fixture unavailable"
        )
        #expect(!detail.isDetailOnline)
        let unavailable = try await FleetViewRenderHarness.render(detail.statusStrip)
        #expect(!unavailable.visibleText.contains("CONNECTED"))
        #expect(!unavailable.visibleText.contains("LIVE"))
    }

    @Test func reconnectingStatusDoesNotClaimOnline() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        fixture.store.isDemo = false
        let device = try #require(fixture.store.devices.first)
        var snapshot = try #require(fixture.store.snapshots[device.id])
        snapshot.isReconnecting = true
        fixture.store.snapshots[device.id] = snapshot

        let detail = MinerDetailView(device: device, store: fixture.store, isLive: true)
        #expect(!detail.isDetailOnline)
        let rendered = try await FleetViewRenderHarness.render(detail.statusStrip)
        #expect(rendered.visibleText.contains("RECONNECTING"))
        #expect(!rendered.visibleText.contains("LIVE"))
    }

    @Test func xmrigControlRendersReviewedPauseResumeWithoutSending() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        var device = try #require(fixture.store.devices.first)
        device.kind = .xmrig
        fixture.store.devices = [device]
        let before = try #require(fixture.store.snapshots[device.id])
        let control = XMRigControlView(device: device, store: fixture.store)

        #expect(XMRigControlView.Action.pause.title == "Pause mining")
        #expect(XMRigControlView.Action.resume.title == "Resume mining")
        #expect(XMRigControlView.Action.pause.explanation.contains("can be resumed"))
        #expect(XMRigControlView.Action.resume.explanation.contains("existing local configuration"))

        let rendered = try await FleetViewRenderHarness.render(NavigationStack { control }, height: 1_000)
        #expect(rendered.visibleText.contains("XMRig controller"))
        #expect(rendered.visibleText.contains("Pause mining"))
        #expect(rendered.visibleText.contains("Resume mining"))
        #expect(fixture.store.snapshots[device.id]?.info == before.info)
        #expect(fixture.store.snapshots[device.id]?.error == before.error)
        #expect(fixture.store.isDemo)
    }

    @Test func xmrigDetailRoutesOnlyToReviewedControlAndRetainsItsTelemetry() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        var device = try #require(fixture.store.devices.first)
        device.kind = .xmrig
        fixture.store.devices = [device]
        let info = MinerInfo(raw: [
            "hashRate": .number(0.002),
            "miningPaused": .bool(true),
            "sharesAccepted": .integer(12)
        ])
        fixture.store.snapshots[device.id] = MinerSnapshot(info: info)
        let detail = MinerDetailView(device: device, store: fixture.store)

        #expect(detail.isXMRig)
        #expect(detail.currentDevice.kind == .xmrig)
        let rendered = try await FleetViewRenderHarness.render(NavigationStack { detail.controls }, height: 1_200)
        #expect(rendered.visibleText.contains("XMRig control"))
        #expect(!rendered.visibleText.contains("Check compatibility"))
        #expect(!rendered.visibleText.contains("Settings & pools"))
        #expect(fixture.store.snapshots[device.id]?.info?.miningPaused == true)
    }

    @Test func internalDetailRenderStateStartsInSourceDefinedDefaults() throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let detail = MinerDetailView(device: device, store: fixture.store)

        #expect(detail.showsCooling)
        #expect(detail.showsTuning)
        #expect(!detail.showsAdvancedTools)
        #expect(!detail.showsIdentity)
        #expect(!detail.showsPools)
        #expect(!detail.showsRenamePrompt)
        #expect(!detail.showsRemoveConfirmation)
        #expect(detail.renameDraft.isEmpty)
        #expect(detail.renameError == nil)
        #expect(detail.tuningSessionRoute == nil)
        #expect(detail.contentWidth == 0)
        #expect(detail.snapshot?.info == fixture.store.snapshots[device.id]?.info)
        #expect(detail.currentDevice.id == device.id)
        #expect(!detail.isXMRig)
    }
}
