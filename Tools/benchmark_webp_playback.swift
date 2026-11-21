// Focused native rendering-path comparison, not a whole-app responsiveness benchmark.
// Baseline reconstructs the pre-change showFrame path with ImageIO caching disabled.
// Both paths force first drawing on MainActor into the same sRGB bitmap surface.
import AppKit
import Foundation
import ImageIO

@main
struct WebPPlaybackBenchmark {
    private enum Failure: Error { case invalidInput }

    struct Samples: Codable {
        let count: Int
        let medianMS: Double
        let p95MS: Double
        let maximumMS: Double
        let totalMS: Double

        init(_ values: [Double]) {
            let sorted = values.sorted()
            count = sorted.count
            medianMS = sorted[sorted.count / 2]
            p95MS = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            maximumMS = sorted.last ?? 0
            totalMS = sorted.reduce(0, +)
        }
    }

    struct Result: Codable {
        let asset: String
        let displayWidth: Int
        let displayHeight: Int
        let scale: Int
        let baselineUI: Samples
        let preparedUI: Samples
        let asynchronousRequest: Samples
        let coldFirstFrameMS: Double
        let decodedFrames: Int
        let cacheHits: Int
        let mainThreadDecodes: Int
        let peakPreparedBytes: Int
        let preparedByteLimit: Int
    }

    @MainActor static func draw(_ image: NSImage, into context: CGContext, rect: CGRect) {
        precondition(Thread.isMainThread)
        context.clear(rect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let components = start.duration(to: .now).components
        return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }

    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw Failure.invalidInput }
        _ = NSApplication.shared // No window, app activation, network, or display interaction.
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let byteLimit = 16 * 1024 * 1024
        var results: [Result] = []
        for name in ["HashFleetBrandLoop", "FleetClusterArtLoop", "MinerCoolingArtLoop"] {
            let url = root.appending(path: "App/Resources/Assets.xcassets/\(name).dataset/\(name).webp")
            let data = try Data(contentsOf: url)
            for size in [CGSize(width: 72, height: 50), CGSize(width: 220, height: 220)] {
                guard let source = CGImageSourceCreateWithData(data as CFData,
                          [kCGImageSourceShouldCache: false] as CFDictionary),
                      let pixels = WebPPixelSize(displaySize: size, scale: 2, geometry: .logicalSize),
                      let color = CGColorSpace(name: CGColorSpace.sRGB),
                      let context = CGContext(data: nil, width: pixels.width, height: pixels.height,
                          bitsPerComponent: 8, bytesPerRow: pixels.bytesPerRow, space: color,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.invalidInput }
                let rect = CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
                var baseline: [Double] = []
                for _ in 0..<2 {
                    for index in 0..<CGImageSourceGetCount(source) {
                        let start = ContinuousClock.now
                        try autoreleasepool {
                            guard let frame = CGImageSourceCreateImageAtIndex(source, index,
                                [kCGImageSourceShouldCache: false] as CFDictionary) else { throw Failure.invalidInput }
                            let image = NSImage(cgImage: frame, size: size)
                            draw(image, into: context, rect: rect)
                        }
                        baseline.append(milliseconds(since: start))
                    }
                }
                let store = WebPFrameStore(byteLimit: byteLimit)
                let cold = ContinuousClock.now
                guard let animation = await store.animation(for: data) else { throw Failure.invalidInput }
                var presentation: [Double] = []
                var requests: [Double] = []
                var firstFrameMS = 0.0
                for pass in 0..<2 {
                    for index in animation.durations.indices {
                        let requestStart = ContinuousClock.now
                        guard let frame = await store.frame(for: animation, index: index, pixelSize: pixels) else {
                            throw Failure.invalidInput
                        }
                        requests.append(milliseconds(since: requestStart))
                        let start = ContinuousClock.now
                        autoreleasepool {
                            let image = NSImage(cgImage: frame.image, size: size)
                            draw(image, into: context, rect: rect)
                        }
                        presentation.append(milliseconds(since: start))
                        if pass == 0, index == 0 { firstFrameMS = milliseconds(since: cold) }
                    }
                }
                let stats = await store.statistics()
                guard stats.mainThreadDecodes == 0, stats.peakResidentBytes <= byteLimit else {
                    throw Failure.invalidInput
                }
                results.append(Result(asset: name, displayWidth: Int(size.width), displayHeight: Int(size.height), scale: 2,
                    baselineUI: Samples(baseline), preparedUI: Samples(presentation), asynchronousRequest: Samples(requests),
                    coldFirstFrameMS: firstFrameMS, decodedFrames: stats.decodedFrames, cacheHits: stats.cacheHits,
                    mainThreadDecodes: stats.mainThreadDecodes, peakPreparedBytes: stats.peakResidentBytes,
                    preparedByteLimit: byteLimit))
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let output = String(data: try encoder.encode(results), encoding: .utf8) else {
            throw Failure.invalidInput
        }
        print(output)
    }
}
