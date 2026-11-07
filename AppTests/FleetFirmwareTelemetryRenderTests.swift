import Foundation
import SwiftUI
import Testing
import HashFleetCore
@testable import HashFleet

@MainActor
struct FleetFirmwareTelemetryRenderTests {
    @Test(arguments: [CGFloat(390), CGFloat(1000)])
    func actualDomainAndPoolViewRendersSixteenDomainsWithoutRawSecrets(width: CGFloat) async throws {
        let rates = Array(repeating: JSONValue.integer(500), count: 8)
        let info = MinerInfo(raw: [
            "hashrateMonitor": .object(["asics": .array([
                .object(["domains": .array(rates)]), .object(["domains": .array(rates)])
            ])]),
            "expectedHashrate": .integer(8000), "uptimeSeconds": .integer(100),
            "version": .string("fixture-1"), "isUsingFallbackStratum": .integer(1),
            "fallbackStratumTLS": .integer(1), "fallbackStratumProtocol": .string("SV1"),
            "poolBanner": .string("Fixture pool welcome"),
            "primaryPoolError": .string("Fixture connection denied"),
            "stratumUser": .string("DO_NOT_RENDER_WALLET")
        ])
        let view = FirmwareTelemetryView(info: info, observedAt: .now, minerIdentity: "fixture",
            isCached: false, error: nil, isReconnecting: false, freshness: nil, initiallyExpanded: true)
        let rendered = try await FleetViewRenderHarness.render(view, width: width, height: 2600)
        let text = rendered.visibleText.lowercased()
        #expect(rendered.pixelVariation > 8)
        #expect(text.contains("asic hashrate"))
        #expect(text.contains("domain 8"))
        #expect(text.contains("nominal"))
        #expect(text.contains("fallback"))
        #expect(text.contains("tls configured"))
        #expect(text.contains("fixture connection denied"))
        #expect(text.contains("do_not_render_wallet") == false)
    }

    @Test func legacyAndCachedTelemetryAreClearlyNotInventedLiveReadings() async throws {
        let view = FirmwareTelemetryView(info: MinerInfo(raw: [:]), observedAt: nil,
            minerIdentity: "fixture", isCached: true, error: nil, isReconnecting: false, freshness: nil,
            initiallyExpanded: true)
        let rendered = try await FleetViewRenderHarness.render(view, height: 650)
        let text = rendered.visibleText.lowercased()
        #expect(text.contains("last known asic hashrate"))
        #expect(text.contains("not reported"))
        #expect(text.contains("active pool not reported"))
        #expect(text.contains("0 gh/s") == false)
    }

    @Test func registerGridUsesMoreColumnsAsWidthGrowsAndOneAtAccessibilitySizes() {
        #expect(FirmwareTelemetryGridMetrics.columnCount(availableWidth: 330, accessibilitySize: false) == 2)
        #expect(FirmwareTelemetryGridMetrics.columnCount(availableWidth: 390, accessibilitySize: false) == 2)
        #expect(FirmwareTelemetryGridMetrics.columnCount(availableWidth: 400, accessibilitySize: false) == 2)
        #expect(FirmwareTelemetryGridMetrics.columnCount(availableWidth: 834, accessibilitySize: false) == 4)
        #expect(FirmwareTelemetryGridMetrics.columnCount(availableWidth: 1_120, accessibilitySize: true) == 1)
    }

    @Test func collapsedDefaultKeepsSummaryAndPoolDiagnosticsVisible() async throws {
        let info = fixtureInfo()
        let view = FirmwareTelemetryView(info: info, observedAt: .now, minerIdentity: "fixture",
            isCached: false, error: nil, isReconnecting: false, freshness: nil)
        let rendered = try await FleetViewRenderHarness.render(view, width: 390, height: 1_200)
        let text = rendered.visibleText.lowercased()
        #expect(text.contains("asic hashrate"))
        #expect(text.contains("chip-domain readings"))
        #expect(text.contains("domain 8") == false)
        #expect(text.contains("pool connection"))
        #expect(text.contains("fixture connection denied"))
    }

    @Test(arguments: [CGFloat(390), CGFloat(834), CGFloat(1_280)])
    func expandedGridRendersAtNarrowAndWideWidths(width: CGFloat) async throws {
        let view = FirmwareTelemetryView(info: fixtureInfo(), observedAt: .now, minerIdentity: "fixture",
            isCached: false, error: nil, isReconnecting: false, freshness: nil, initiallyExpanded: true)
        let rendered = try await FleetViewRenderHarness.render(view, width: width, height: 2_600)
        #expect(rendered.pixelVariation > 8)
        #expect(rendered.visibleText.lowercased().contains("domain 8"))
        #expect(rendered.visibleText.lowercased().contains("fixture connection denied"))
    }

    @Test func accessibilityTextKeepsExpandedDomainTilesInOneColumnAndReadable() async throws {
        #expect(FirmwareTelemetryGridMetrics.columnCount(availableWidth: 1_280, accessibilitySize: true) == 1)
        let view = FirmwareTelemetryView(info: fixtureInfo(), observedAt: .now, minerIdentity: "fixture",
            isCached: false, error: nil, isReconnecting: false, freshness: nil, initiallyExpanded: true)
            .environment(\.dynamicTypeSize, .accessibility2)
        let rendered = try await FleetViewRenderHarness.render(view, width: 1_280, height: 3_600)
        #expect(rendered.pixelVariation > 8)
        #expect(rendered.visibleText.lowercased().contains("domain 8"))
        #expect(rendered.visibleText.lowercased().contains("fixture connection denied"))
    }

    private func fixtureInfo() -> MinerInfo {
        let rates = Array(repeating: JSONValue.integer(500), count: 8)
        return MinerInfo(raw: [
            "hashrateMonitor": .object(["asics": .array([
                .object(["domains": .array(rates)]), .object(["domains": .array(rates)])
            ])]),
            "expectedHashrate": .integer(8000), "uptimeSeconds": .integer(100),
            "version": .string("fixture-1"), "isUsingFallbackStratum": .integer(1),
            "fallbackStratumTLS": .integer(1), "fallbackStratumProtocol": .string("SV1"),
            "poolBanner": .string("Fixture pool welcome"),
            "primaryPoolError": .string("Fixture connection denied"),
            "stratumUser": .string("DO_NOT_RENDER_WALLET")
        ])
    }
}
