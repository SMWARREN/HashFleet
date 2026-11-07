import Foundation
import SwiftUI
import Testing
import HashFleetCore
@testable import HashFleet

/// Real tool bodies and public probe state. No request, import, clipboard, or write button is tapped.
@Suite(.serialized)
@MainActor
struct MinerToolsRenderingCoverageTests {
    @Test(arguments: MinerEndpoint.catalog.filter { !$0.isWebSocket })
    func endpointFormsDescribeTheirExactOperationWithoutExecuting(_ endpoint: MinerEndpoint) async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let view = MinerEndpointView(device: device, store: fixture.store, endpoint: endpoint,
                                     insights: fixture.insights)
        #expect(!view.canWrite)
        #expect(view.resolvedEndpoint == endpoint)
        let rendered = try await FleetViewRenderHarness.render(NavigationStack { view }, height: 2_400)
        #expect(rendered.recognizes("\(endpoint.method) \(endpoint.path)", allowingLineWraps: true))
        switch endpoint {
        case .updatePool(let slot):
            #expect(rendered.visibleText.contains("Update pool slot"))
            #expect(view.poolSlot == slot)
        case .deletePool(let slot):
            #expect(rendered.visibleText.contains("Delete pool slot"))
            #expect(view.poolSlot == slot)
        default:
            #expect(rendered.visibleText.contains(endpoint.title))
        }
        #expect(rendered.visibleText.contains("Demo mode: writes are locked"))
        #expect(rendered.visibleText.contains("An upstream catalog entry is not a capability guarantee"))
        // OCR observes the words, not the exact typographic ellipsis. Native AX
        // punctuation and the numeric title glyph remain separate acceptance gaps.
        let action = MinerRequestSafety.isWrite(endpoint) ? "Review request" : "Send read request"
        #expect(rendered.visibleText.contains(action))
        #expect(view.model.response.isEmpty && !view.model.isRunning)
        #expect(view.pending == nil)
        if view.needsJSON {
            #expect(rendered.visibleText.contains("JSON request body"))
            #expect(rendered.visibleText.contains("Only included keys will be sent"))
        }
        if view.isPool {
            #expect(rendered.visibleText.contains("NVS slot"))
            #expect(rendered.visibleText.contains("Slots are persistent IDs"))
            #expect(rendered.visibleText.contains("not the array position in info.pools"))
            #expect((0...7).contains(view.poolSlot))
        }
        if view.isBinary {
            #expect(rendered.visibleText.contains("High risk: verify board and image compatibility"))
            #expect(rendered.visibleText.contains("No upload starts until you review and type APPLY"))
        }
        if endpoint == .statistics {
            #expect(rendered.visibleText.contains("Column names are case-sensitive"))
        }
    }

    @Test func endpointCatalogSeparatesReadsAndWritesAndNeverInventsSupport() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let view = MinerEndpointCatalogView(device: device, store: fixture.store, insights: fixture.insights)
        let rendered = try await FleetViewRenderHarness.render(NavigationStack { view }, height: 7_800)
        #expect(rendered.visibleText.contains("Endpoint explorer"))
        #expect(rendered.visibleText.contains("Firmware-dependent capabilities"))
        #expect(rendered.visibleText.contains("Demo mode never contacts a miner or executes writes"))
        #expect(rendered.visibleText.contains("Writes always require exact review"))
        #expect(rendered.visibleText.contains("Read endpoints"))
        #expect(rendered.visibleText.contains("Write endpoints"))
        #expect(rendered.visibleText.contains("Support: unverified on this firmware"))
        #expect(!rendered.visibleText.contains("Detected ESP-Miner-compatible API"))
        #expect(fixture.store.capabilities.reports.isEmpty)
    }

    @Test func compatibilityDistinguishesSampleUncheckedAndFailedRead() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let sample = try await FleetViewRenderHarness.render(NavigationStack {
            MinerCompatibilityView(device: device, store: fixture.store, insights: fixture.insights)
        }, height: 2_200)
        #expect(sample.visibleText.contains("Demo preview"))
        #expect(sample.visibleText.contains("Checking is disabled in demo mode"))
        #expect(fixture.store.capabilities.reports.isEmpty)

        fixture.store.isDemo = false
        let unchecked = try await FleetViewRenderHarness.render(NavigationStack {
            MinerCompatibilityView(device: device, store: fixture.store, insights: fixture.insights)
        }, height: 2_200)
        #expect(unchecked.visibleText.contains("Not checked yet"))
        #expect(fixture.store.capabilities.reports.isEmpty, "Opening the screen must not probe a miner")

        await fixture.store.capabilities.check(device: device, isDemo: false)
        let report = try #require(fixture.store.capabilities.reports[device.id])
        #expect(report.infoStatus.isFailed)
        let failed = try await FleetViewRenderHarness.render(NavigationStack {
            MinerCompatibilityView(device: device, store: fixture.store, insights: fixture.insights)
        }, height: 2_200)
        #expect(failed.visibleText.contains("Check incomplete"))
        #expect(failed.visibleText.contains("does not mean your hardware is unsupported"))
        #expect(failed.visibleText.contains("The previous attempt did not finish"))
        #expect(sample.pngData != failed.pngData)
        fixture.store.capabilities.reset()
        #expect(fixture.store.capabilities.reports.isEmpty)
    }

    @Test(arguments: [false, true])
    func customEditorKeepsDraftLocalAndDisplaysItsActualLock(_ demo: Bool) async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        var staged = 0
        let json = "{\"frequency\":550,\"fixture_custom\":{\"enabled\":true}}"
        let view = MinerCustomJSONView(device: device, isDemo: demo, isOffline: !demo, initialJSON: json) { _ in
            staged += 1
        }
        let rendered = try await FleetViewRenderHarness.render(NavigationStack { view }, height: 1_800)
        #expect(rendered.visibleText.contains("Custom firmware settings editor"))
        #expect(rendered.visibleText.contains("JSON Payload (Object Only)"))
        #expect(rendered.visibleText.contains("fixture_custom"))
        #expect(rendered.visibleText.contains("Nothing is sent until confirmed with APPLY"))
        let notice = demo ? "Demo mode: mutations are locked" : "Miner is offline or stale. Settings are read-only"
        #expect(rendered.visibleText.contains(notice))
        #expect(staged == 0)
    }

    @Test(arguments: [false, true])
    func collapsedDiagnosticsShowMissingReadingsWithoutClaimingExpandedSections(_ reported: Bool) async throws {
        let raw: [String: JSONValue] = reported
            ? ["hashRate": .number(1_250), "temp": .number(53), "fanrpm": .number(2_860)] : [:]
        let model = MinerDiagnosticsModel(info: MinerInfo(raw: raw))
        let rendered = try await FleetViewRenderHarness.render(MinerDiagnosticsView(model: model))
        #expect(rendered.visibleText.contains("Miner Diagnostics"))
        #expect(rendered.visibleText.contains("Telemetry, clocks, cooling, energy & pool state"))
        #expect(!rendered.visibleText.contains("SYSTEM & FIRMWARE"))
        if reported {
            #expect(model.hashrate.currentHashrateGHs == 1_250)
            #expect(model.thermal.primaryChipTempCelsius == 53)
            #expect(!rendered.visibleText.contains("Hashrate was not reported"))
        } else {
            #expect(model.hashrate.currentHashrateGHs == nil)
            #expect(rendered.visibleText.contains("Hashrate was not reported in the latest reading"))
            #expect(rendered.visibleText.contains("Chip temperature was not reported by the firmware"))
        }
    }

    @Test(arguments: [MinerEndpoint.liveWebSocket, .logWebSocket])
    func livePanelsRemainDisconnectedInDemo(_ endpoint: MinerEndpoint) async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let view = MinerLiveView(device: device, isDemo: true, initialEndpoint: endpoint)
        let rendered = try await FleetViewRenderHarness.render(NavigationStack { view }, height: 1_800)
        #expect(rendered.visibleText.contains(endpoint.path))
        #expect(rendered.visibleText.contains("Demo mode does not open WebSocket"))
        #expect(rendered.visibleText.contains("No frames yet"))
        #expect(!rendered.visibleText.contains("Connected"))
    }
}
