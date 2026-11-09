import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import HashFleet

@Suite("ASIC sparkline visibility", .serialized) @MainActor
struct FirmwareTelemetrySparklineTests {
    @Test(arguments: [Double?.none, Double?.some(140)])
    func firstObservedSampleIsVisibleRatherThanOnlyTheReference(nominal: Double?) async throws {
        let rendered = try await render(values: [120], nominal: nominal)
        let pixels = try accentPixels(in: rendered.pngData)
        #expect(pixels.count >= 12, "A lone observed reading must draw an actual data marker, not a move-only path")
        #expect(pixels.allSatisfy { $0.x > 3 && $0.y > 3 && $0.x < 176 && $0.y < 76 },
                "The observed reading must remain inset from the plot edges")
    }

    @Test(arguments: [[120.0, 120, 120], [0.0, 0, 0], [118.0, 123, 119, 121]])
    func constantAndVaryingReadingsStayInsideThePlot(values: [Double]) async throws {
        let rendered = try await render(values: values, nominal: nil)
        let pixels = try accentPixels(in: rendered.pngData)
        #expect(pixels.count > 20)
        #expect(pixels.map(\.y).min().map { $0 > 9 } == true,
                "Top padding must keep a real line or marker visible")
        #expect(pixels.map(\.y).max().map { $0 < 70 } == true,
                "Constant and zero readings must not sit on the clipping edge")
    }

    @Test(arguments: [[], [Double.nan, .infinity, -1]])
    func missingOrInvalidReadingsDoNotDrawInventedHistory(values: [Double]) async throws {
        let rendered = try await render(values: values, nominal: 140)
        #expect(try accentPixels(in: rendered.pngData).isEmpty)
        #expect(rendered.visibleText.lowercased().contains("collecting observed samples"))
    }

    @Test(arguments: [[Double.nan, 120, .infinity], [0, Double.greatestFiniteMagnitude]])
    func invalidAndVeryLargeValuesDoNotHideRealObservations(values: [Double]) async throws {
        let rendered = try await render(values: values, nominal: nil)
        let pixels = try accentPixels(in: rendered.pngData)
        #expect(pixels.count >= 12)
        #expect(pixels.allSatisfy { $0.x > 3 && $0.y > 3 && $0.x < 176 && $0.y < 76 })
    }

    private func render(values: [Double], nominal: Double?) async throws -> FleetRenderedView {
        try await FleetViewRenderHarness.render(
            FirmwareTelemetrySparkline(values: values, nominal: nominal)
                .frame(width: 164, height: 64)
                .padding(8)
                .background(FleetTheme.canvas)
                .environment(\.colorScheme, .dark)
                // This is an isolated plot, not a screen. Exclude the simulator's
                // navigation/home safe areas from the 180 × 80 plot fixture.
                .ignoresSafeArea(),
            width: 180, height: 80
        )
    }

    private func accentPixels(in data: Data) throws -> [CGPoint] {
        let image = try #require(UIImage(data: data)?.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(data: &bytes, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let scaleX = CGFloat(image.width) / 180
        let scaleY = CGFloat(image.height) / 80
        var points: [CGPoint] = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = (y * image.width + x) * 4
                // Actual dark-theme observed-series gold. The nominal reference and grid are neutral.
                if bytes[offset] > 200, bytes[offset + 1] > 100, bytes[offset + 1] < 210,
                   bytes[offset + 2] < 85, bytes[offset + 3] > 220 {
                    points.append(CGPoint(x: CGFloat(x) / scaleX, y: CGFloat(y) / scaleY))
                }
            }
        }
        return points
    }
}
