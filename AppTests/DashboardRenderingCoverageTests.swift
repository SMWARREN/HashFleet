import Foundation
import Testing
import SwiftUI
import HashFleetCore
@testable import HashFleet

@Suite(.serialized)
@MainActor
struct DashboardRenderingCoverageTests {
    @Test(arguments: [false, true])
    func dashboardRendersEmptyAndSampleFleetsWithoutChangingDevices(_ demo: Bool) async throws {
        let fixture = try FleetRenderFixture(demo: demo)
        defer { fixture.cleanup() }
        await fixture.insights.refresh()
        let originalDevices = fixture.store.devices
        let rendered = try await FleetViewRenderHarness.render(
            NavigationStack { DashboardView(store: fixture.store, insights: fixture.insights) }, height: 1_600)
        #expect(fixture.store.devices == originalDevices)
        if demo {
            #expect(rendered.visibleText.contains("SAMPLE FLEET HASHRATE"))
        } else {
            #expect(rendered.visibleText.localizedCaseInsensitiveContains("miner"))
            #expect(fixture.store.devices.isEmpty)
        }
    }

    @Test(arguments: [DemoFleet.HistoryMode.populated, .empty, .staleDaily])
    func historyRendersDataBackedWindowWithSampleAndMissingDataHonestly(_ mode: DemoFleet.HistoryMode) async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let snapshots = DemoFleet.snapshots(for: fixture.store.devices, historyMode: mode)
        let card = FleetHistoryCard(devices: fixture.store.devices, snapshots: snapshots, isDemo: true,
                                    initialDisplay: .miners, initialRecentRange: .oneMinute)
        let rendered = try await FleetViewRenderHarness.render(card, width: 800, height: 1_200)
        #expect(rendered.visibleText.contains("Simulated hashrate history"))
        if mode == .populated {
            #expect(rendered.visibleText.contains("1-minute average per-miner reading"))
            #expect(rendered.visibleText.contains("21 samples"))
        } else {
            #expect(rendered.visibleText.contains("No readings in this time window yet."))
            #expect(!rendered.visibleText.contains("1-minute average per-miner reading"))
        }
    }

    @Test func defaultFleetTrendIsCompactAndKeepsIndividualHistoryAvailable() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let snapshots = DemoFleet.snapshots(for: fixture.store.devices)
        let fleet = try await FleetViewRenderHarness.render(
            FleetHistoryCard(devices: fixture.store.devices, snapshots: snapshots, isDemo: true),
            width: 800, height: 1_200)
        let miners = try await FleetViewRenderHarness.render(
            FleetHistoryCard(devices: fixture.store.devices, snapshots: snapshots, isDemo: true,
                             initialDisplay: .miners, initialRecentRange: .day),
            width: 800, height: 1_200)
        #expect(fleet.visibleText.contains("1m"))
        #expect(fleet.visibleText.localizedCaseInsensitiveContains("TH/s"))
        #expect(!fleet.visibleText.contains("1-minute average per-miner reading"))
        #expect(miners.visibleText.contains("1-minute average per-miner reading"))
        #expect(miners.visibleText.contains("Workshop Gamma"))
        #expect(!fleet.visibleText.contains("Workshop Gamma"))
        #expect(fleet.pngData != miners.pngData)
    }

    @Test func historyEmptyFleetShowsNoFabricatedSeries() async throws {
        let rendered = try await FleetViewRenderHarness.render(FleetHistoryCard(devices: [], snapshots: [:], isDemo: false))
        #expect(rendered.visibleText.contains("Your history will appear here over time"))
        #expect(!rendered.visibleText.contains("Simulated"))
    }

    @Test func scopedPoolsRenderOnlySelectedMinerAndKeepDemoExplicit() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let rendered = try await FleetViewRenderHarness.render(
            FleetPoolsCard(fleet: fixture.store, deviceID: device.id), width: 800, height: 1_600)
        #expect(rendered.visibleText.localizedCaseInsensitiveContains("pool"))
        let selected = ConnectedPoolsStore.configuredPools(fleet: fixture.store, deviceID: device.id)
        #expect(!selected.isEmpty)
        #expect(ConnectedPoolsStore.configuredPools(fleet: fixture.store, deviceID: UUID()).isEmpty)
    }

    @Test func tickerRendersSafeReportedStatusAndNoAddresses() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let model = FleetStatusTickerModel(devices: fixture.store.devices, snapshots: fixture.store.snapshots, isDemo: true)
        #expect(model.items.count == fixture.store.devices.count)
        #expect(model.items.allSatisfy { $0.isOnline && $0.isSimulated })
        let rendered = try await FleetViewRenderHarness.render(FleetStatusTicker(fleet: fixture.store))
        #expect(rendered.visibleText.contains(fixture.store.devices[0].name))
        for device in fixture.store.devices { #expect(!rendered.visibleText.contains(device.address)) }
    }

    @Test func tickerKeepsConnectingReconnectingAndOfflineDistinct() throws {
        let fixture = try FleetRenderFixture(demo: false)
        defer { fixture.cleanup() }
        let devices = (0..<3).map { MinerDevice(name: "Fixture \($0)", address: "fixture-\($0).invalid") }
        let snapshots = [
            devices[1].id: MinerSnapshot(info: nil, isReconnecting: true),
            devices[2].id: MinerSnapshot(info: nil, error: "private-fixture.invalid timed out")
        ]
        let model = FleetStatusTickerModel(devices: devices, snapshots: snapshots)
        #expect(model.items.map(\.status) == [.connecting, .reconnecting, .offline])
        #expect(model.items.allSatisfy { $0.segments.isEmpty })
        #expect(model.items.allSatisfy { !$0.summary.contains("private-fixture.invalid") })
    }

    @Test func splitViewAndSidebarRenderWithoutTakingASelection() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let selection = Binding.constant(FleetSidebarDestination?.none)
        let split = FleetSplitView(store: fixture.store, insights: fixture.insights, startupReady: true,
            fleetPath: .constant(NavigationPath()), sidebarSelection: selection)
        let wide = try await FleetViewRenderHarness.render(split, width: 1_024, height: 1_200)
        #expect(wide.size.width == 1_024)
        #expect(wide.visibleText.localizedCaseInsensitiveContains("fleet"))
        let sidebar = FleetSidebarView(selection: selection, store: fixture.store, insights: fixture.insights,
            showingAddMiner: .constant(false), onRefresh: {})
        let rendered = try await FleetViewRenderHarness.render(sidebar, height: 1_200)
        #expect(rendered.visibleText.contains(fixture.store.devices[0].name))
        #expect(selection.wrappedValue == nil)
    }

    @Test func onboardingShowsBothConnectionAndSafeExploration() async throws {
        var callbacks = 0
        // The demo action follows the full onboarding guide, below a phone-height crop.
        let rendered = try await FleetViewRenderHarness.render(FleetOnboardingView(
            addMiner: { callbacks += 1 }, exploreDemo: { callbacks += 1 }, forceReduceMotion: true), height: 1_600)
        #expect(rendered.visibleText.contains("Connect your first miner"))
        #expect(rendered.visibleText.contains("Just looking? Try the demo"))
        #expect(rendered.visibleText.contains("The sample data is clearly labeled"))
        #expect(callbacks == 0, "Merely rendering navigation choices must not activate either action")
    }

    @Test(arguments: [MinerBestShareEvent.Kind.allTime, .session])
    func bestShareBannerNamesTheActualKindAndNeverClaimsABlock(_ kind: MinerBestShareEvent.Kind) async throws {
        let event = MinerBestShareEvent(deviceID: UUID(), minerName: "Fixture Gamma", kind: kind,
            displayValue: "1.2M", rawValue: "1.2M", occurredAt: Date())
        var dismissals = 0
        let rendered = try await FleetViewRenderHarness.render(
            FleetBestShareCelebrationBanner(event: event, dismiss: { dismissals += 1 }))
        #expect(rendered.visibleText.contains("Fixture Gamma"))
        #expect(rendered.visibleText.contains(kind.title))
        #expect(rendered.visibleText.contains("1.2M difficulty"))
        #expect(!rendered.visibleText.contains("Block found"))
        #expect(dismissals == 0)
    }

    @Test(arguments: [nil, 123_456] as [Int?])
    func blockBannerDoesNotInventAnUnreportedHeight(_ height: Int?) async throws {
        let event = MinerBlockFoundEvent(deviceID: UUID(), minerName: "Fixture Gamma", coinLabel: "BTC",
            height: height, count: 1, occurredAt: Date())
        let rendered = try await FleetViewRenderHarness.render(FleetBlockFoundCelebrationBanner(event: event, dismiss: {}))
        // The spoken sentence is an accessibility label, not the banner's visible text.
        #expect(rendered.visibleText.contains("BLOCK FOUND"))
        #expect(rendered.visibleText.contains("Fixture Gamma"))
        #expect(rendered.visibleText.contains("BTC"))
        #expect(rendered.visibleText.contains("height") == (height != nil))
        if let height {
            #expect(rendered.visibleText.contains("height \(FleetFormat.blockHeight(height))"))
        }
    }

    @Test(arguments: [0, 1, 3])
    func aggregateHeroQualifiesMissingPartialAndCompleteReadings(_ reporting: Int) async throws {
        let rate = FleetMetricTotal(value: reporting == 0 ? 0 : 1_200, reporting: reporting, online: 3)
        let hero = FleetHeroCard(hashrate: rate, power: FleetMetricTotal(value: 50, reporting: 3, online: 3),
            onlineCount: 3, deviceCount: 4, isDemo: false, isRefreshing: false, isInitialLoading: false,
            realtimeMonitoring: false, liveConnectionCount: 0, liveFallbackCount: 0)
        let rendered = try await FleetViewRenderHarness.render(hero)
        // Assert FleetReadingCaption's visible qualification, not accessibleRate's spoken summary.
        if reporting == 0 {
            #expect(rendered.visibleText.contains("No online miner reported a hashrate."))
            #expect(rendered.visibleText.contains("This is not a zero-"))
            #expect(rendered.visibleText.contains("hashrate fleet."))
            #expect(!rendered.visibleText.localizedCaseInsensitiveContains("TH/s"))
        } else {
            #expect(rendered.visibleText.contains("1.20"))
            #expect(rendered.visibleText.localizedCaseInsensitiveContains("TH/s"))
            if reporting == 1 {
                #expect(rendered.visibleText.contains("Subtotal from 1 of 3 online miners."))
                #expect(rendered.visibleText.contains("2 did not report a hashrate."))
            } else {
                #expect(!rendered.visibleText.localizedCaseInsensitiveContains("subtotal"))
                #expect(!rendered.visibleText.contains("did not report a hashrate"))
            }
        }
        #expect(rendered.visibleText.contains("FLEET HASHRATE"))
        #expect(rendered.visibleText.contains("3 of 4 online"))
    }

    @Test func metricCardDescribesValueAndItsScopeTogether() async throws {
        let card = FleetMetricCard(title: "Total Power", value: "150", unit: "W", symbol: "bolt.fill",
            caption: "Reported by all miners", identifier: "render.power", accessibleValue: "150 Watts")
        let rendered = try await FleetViewRenderHarness.render(card)
        // The visible unit is W. The expanded Watts sentence belongs to native AX coverage.
        #expect(rendered.visibleText.contains("Total Power"))
        #expect(rendered.visibleText.contains("150 W"))
        #expect(rendered.visibleText.contains("Reported by all miners"))
    }

    @Test(arguments: [false, true])
    func minerOverviewRendersCompactAndExpandedReportedReadings(_ compact: Bool) async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let card = MinerOverviewCard(device: device, snapshot: fixture.store.snapshots[device.id],
            isDemo: true, compact: compact, isLive: true, liveConnectionError: nil)
        let rendered = try await FleetViewRenderHarness.render(card, height: 1_200)
        #expect(rendered.visibleText.contains(device.name))
        #expect(rendered.visibleText.contains("Sample"))
        #expect(!rendered.visibleText.contains(device.address))
    }
}
