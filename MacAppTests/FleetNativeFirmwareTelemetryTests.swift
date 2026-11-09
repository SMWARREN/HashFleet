import AppKit
import HashFleetCore
import SwiftUI
import Testing
@testable import HashFleetMac

@MainActor
@Suite("Shared ASIC grid on native Mac", .serialized)
struct FleetNativeFirmwareTelemetryTests {
    private var info: MinerInfo {
        let rates = Array(repeating: JSONValue.integer(500), count: 8)
        return MinerInfo(raw: [
            "hashrateMonitor": .object(["asics": .array([
                .object(["domains": .array(rates)]),
                .object(["domains": .array(rates)])
            ])]),
            "expectedHashrate": .integer(8_000),
            "uptimeSeconds": .integer(100),
            "version": .string("Offline register fixture")
        ])
    }

    private func image(
        width: CGFloat, expanded: Bool, textSize: DynamicTypeSize = .large
    ) throws -> CGImage {
        let view = FirmwareTelemetryView(
            info: info, observedAt: .now, minerIdentity: "offline-fixture",
            isCached: false, error: nil, isReconnecting: false,
            freshness: nil, initiallyExpanded: expanded
        )
        .environment(\.dynamicTypeSize, textSize)
        .environment(\.colorScheme, .dark)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }

    @Test func gridUsesAvailableWidthWithoutPlatformSpecificForks() {
        #expect(FirmwareTelemetryGridMetrics.columnCount(availableWidth: 200, accessibilitySize: false) == 1)
        #expect(FirmwareTelemetryGridMetrics.columnCount(availableWidth: 330, accessibilitySize: false) == 2)
        #expect(FirmwareTelemetryGridMetrics.columnCount(availableWidth: 390, accessibilitySize: false) == 2)
        #expect(FirmwareTelemetryGridMetrics.columnCount(availableWidth: 834, accessibilitySize: false) > 2)
        #expect(FirmwareTelemetryGridMetrics.columnCount(availableWidth: 1_280, accessibilitySize: true) == 1)
    }

    @Test(arguments: [CGFloat(390), CGFloat(650), CGFloat(1_160)])
    func actualSharedViewRendersCollapsedAndExpanded(width: CGFloat) throws {
        let collapsed = try image(width: width, expanded: false)
        let expanded = try image(width: width, expanded: true)
        #expect(collapsed.width == Int(width))
        #expect(expanded.width == Int(width))
        #expect(collapsed.height > 0)
        #expect(expanded.height > collapsed.height + 100,
                "Expanding the real shared view must reveal the sixteen register tiles")
        let representation = NSBitmapImageRep(cgImage: expanded)
        let data = try #require(representation.representation(using: .png, properties: [:]))
        Attachment.record(data, named: "native-shared-asic-grid-\(Int(width)).png")
    }

    @Test func accessibilityTextUsesSingleColumnAndGrowsInsteadOfClipping() throws {
        let standard = try image(width: 390, expanded: true)
        let accessible = try image(width: 390, expanded: true, textSize: .accessibility2)
        #expect(accessible.width == standard.width)
        #expect(accessible.height > standard.height)
        let representation = NSBitmapImageRep(cgImage: accessible)
        let data = try #require(representation.representation(using: .png, properties: [:]))
        Attachment.record(data, named: "native-shared-asic-grid-accessibility.png")
    }
}
