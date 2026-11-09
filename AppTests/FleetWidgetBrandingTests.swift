import SwiftUI
import Testing
import UIKit
@testable import HashFleetWidgetTestSupport

@Suite("Hash Fleet widget branding") @MainActor
struct FleetWidgetBrandingTests {
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func approvedColorAndMonochromeMarksExistInTheActualWidgetBundle(style: UIUserInterfaceStyle) throws {
        #expect(FleetWidgetBrandAssets.displayName == "Hash Fleet")
        let traits = UITraitCollection(userInterfaceStyle: style)
        for monochrome in [false, true] {
            let name = FleetWidgetBrandAssets.assetName(monochrome: monochrome)
            let image = try #require(UIImage(named: name, in: FleetWidgetBrandAssets.bundle, compatibleWith: traits))
            #expect(image.size.width > 0 && image.size.height > 0)
            let pixels = try #require(image.cgImage)
            #expect(pixels.width >= 90 && pixels.height >= 90)
        }
        #expect(FleetWidgetBrandAssets.colorName != FleetWidgetBrandAssets.templateName)
    }

    @Test func staleCopyNeverClaimsAnUnobservedPendingRefresh() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let glance = FleetGlance(updatedAt: date, onlineCount: 1, minerCount: 2,
            hashrateGHs: 1200, powerWatts: 20, isDemo: false)
        let presentation = FleetGlancePresentation(glance: glance, isStale: true)
        #expect(presentation.status.contains("Last known"))
        #expect(presentation.status.contains("open app to refresh"))
        #expect(!presentation.status.contains("pending"))
        #expect(presentation.rateLabel == "LAST KNOWN HASHRATE")
        #expect(presentation.accessibilitySummary.contains("open app to refresh"))
        #expect(!presentation.accessibilitySummary.contains("pending"))
    }

    @Test(arguments: [false, true])
    func brandArtworkHasTransparentOutsidePixels(monochrome: Bool) throws {
        let image = try rasterizedAsset(monochrome: monochrome)
        for (x, y) in [(0, 0), (95, 0), (0, 95), (95, 95)] {
            #expect(image[(y * 96 + x) * 4 + 3] == 0,
                "A widget mark must not carry an opaque background tile")
        }
        let transparentPixels = stride(from: 3, to: image.count, by: 4).filter { image[$0] < 16 }.count
        #expect(transparentPixels > 96 * 96 / 4)
    }

    @Test(arguments: [false, true])
    func embeddedProductionWidgetUsesTheSameTransparentArtwork(monochrome: Bool) throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let urls = try FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
        let widget = try #require(urls.compactMap { Bundle(url: $0) }.first {
            $0.bundleIdentifier == "app.hashfleet.widgets"
        })
        let expected = try rasterizedAsset(monochrome: monochrome)
        let embedded = try rasterizedAsset(monochrome: monochrome, in: widget)
        #expect(embedded == expected,
            "Host-framework alpha checks must also describe the embedded production extension")
    }

    @Test func monochromeArtworkKeepsInteriorCutoutsInsteadOfBecomingASolidBlock() throws {
        let image = try rasterizedAsset(monochrome: true)
        let alpha = (24..<72).flatMap { y in (24..<72).map { x in image[(y * 96 + x) * 4 + 3] } }
        #expect(alpha.contains { $0 > 200 }, "The fan must have visible strokes")
        #expect(alpha.filter { $0 < 32 }.count > alpha.count / 5,
            "Template tinting needs transparent fan cutouts, not an opaque silhouette")
    }

    @Test func archivedArtworkIsBoundedToDisplayResolutionAndKeepsItsAlpha() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            for monochrome in [false, true] {
                let image = try #require(FleetWidgetBrandAssets.thumbnail(
                    monochrome: monochrome, colorScheme: colorScheme, pointSize: 52, displayScale: 3)?.cgImage)
                #expect(image.width == 156 && image.height == 156)
                let pixels = try rasterized(image)
                for (x, y) in [(0, 0), (95, 0), (0, 95), (95, 95)] {
                    #expect(pixels[(y * 96 + x) * 4 + 3] == 0)
                }
            }
        }
        let capped = try #require(FleetWidgetBrandAssets.thumbnail(
            monochrome: false, colorScheme: .light, pointSize: .greatestFiniteMagnitude, displayScale: 3)?.cgImage)
        #expect(capped.width == 256 && capped.height == 256)
        for size in [CGFloat.zero, -1, .infinity, .nan] {
            #expect(FleetWidgetBrandAssets.thumbnail(
                monochrome: false, colorScheme: .light, pointSize: size, displayScale: 3) == nil)
        }
        for scale in [CGFloat.zero, -1, .infinity, .nan] {
            #expect(FleetWidgetBrandAssets.thumbnail(
                monochrome: false, colorScheme: .light, pointSize: 18, displayScale: scale) == nil)
        }
    }

    @Test func brandUsesRealArtworkAndCorrectVisibleName() async throws {
        let rendered = try await FleetViewRenderHarness.render(
            VStack(spacing: 12) {
                FleetWidgetBrand()
                FleetWidgetBrand(isActivity: true)
                FleetWidgetBrandMark(size: 60)
                FleetWidgetBrandMark(size: 40, monochrome: true)
            }.padding(16), width: 260, height: 220)
        #expect(rendered.visibleText.contains("Hash Fleet"))
        #expect(!rendered.visibleText.localizedCaseInsensitiveContains("Axe Fleet"))
        #expect(rendered.pixelVariation > 1)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func renderedArtworkKeepsTransparentCornersOnBothCanvases(colorScheme: ColorScheme) async throws {
        let canvas = colorScheme == .light ? Color.white : Color.black
        for monochrome in [false, true] {
            let rendered = try await FleetViewRenderHarness.render(
                FleetWidgetBrandMark(size: 60, monochrome: monochrome)
                    .foregroundStyle(Color.orange)
                    .padding(18)
                    .background(canvas)
                    .environment(\.colorScheme, colorScheme)
                    .ignoresSafeArea(), width: 96, height: 96)
            let image = try #require(UIImage(data: rendered.pngData)?.cgImage)
            let pixels = try rasterized(image)
            let reference = Array(pixels[(48 * 96 * 4)..<(48 * 96 * 4 + 3)])
            for (x, y) in [(19, 19), (76, 19), (19, 76), (76, 76)] {
                let offset = (y * 96 + x) * 4
                let rgb = Array(pixels[offset..<(offset + 3)])
                #expect(zip(rgb, reference).allSatisfy { abs(Int($0.0) - Int($0.1)) <= 8 },
                    "Actual SwiftUI artwork must blend with its surrounding canvas")
            }
            #expect(rendered.pixelVariation > 1, "The mark must remain visible")
        }
    }

    /// Hosted compact canvases check essential units, not installed Watch delivery.
    @Test(arguments: [CGFloat(184), 320])
    func smallSupplementalKeepsMeasurementLegibleAndPrivateAtCompactWidths(width: CGFloat) async throws {
        let glance = FleetGlance(updatedAt: Date(timeIntervalSince1970: 1_791_475_200),
            onlineCount: 2, minerCount: 3, hashrateGHs: 2_400.5, powerWatts: 38.25, isDemo: false)
        let content = FleetSmallSupplementalActivity(
            presentation: FleetGlancePresentation(glance: glance, isStale: false))
            .background(FleetWidgetTheme.charcoal)
        let regular = try await FleetViewRenderHarness.render(content, width: width, height: 180)
        let redacted = try await FleetViewRenderHarness.render(
            content.redacted(reason: .privacy), width: width, height: 180)

        #expect(regular.visibleText.contains("2.40 TH/s"),
            "The essential hashrate unit must remain legible with its value on compact canvases")
        #expect(!redacted.visibleText.contains("2.40"))
        #expect(!redacted.visibleText.contains("TH/s"))
        #expect(regular.pngData != redacted.pngData)
    }

    private func rasterizedAsset(
        monochrome: Bool, in bundle: Bundle = FleetWidgetBrandAssets.bundle
    ) throws -> [UInt8] {
        let asset = try #require(UIImage(named: FleetWidgetBrandAssets.assetName(monochrome: monochrome),
            in: bundle, compatibleWith: nil)?.cgImage)
        return try rasterized(asset)
    }

    private func rasterized(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 96 * 96 * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(data: bytes.baseAddress, width: 96, height: 96,
                bitsPerComponent: 8, bytesPerRow: 96 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        return pixels
    }
}
