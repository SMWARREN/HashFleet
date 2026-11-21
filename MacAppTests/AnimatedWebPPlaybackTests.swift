import AppKit
import ImageIO
import Testing
@testable import HashFleetMac

@Suite(.serialized)
@MainActor
struct AnimatedWebPPlaybackTests {
    private func data(_ name: String = "HashFleetBrandLoop") throws -> Data {
#if WEBP_STANDALONE_TESTS
        return try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "webp")))
#else
        return try #require(NSDataAsset(name: name)).data
#endif
    }

    private func eventually(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw CheckFailure.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private enum CheckFailure: Error { case timeout }

    private func pixels(_ image: CGImage) throws -> Data {
        let data = try #require(image.dataProvider?.data)
        return data as Data
    }

    private func reference(_ data: Data, index: Int, width: Int, height: Int) throws -> Data {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let raw = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: (width * 4 + 63) & ~63, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .high
        context.draw(raw, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try pixels(try #require(context.makeImage()))
    }

    @Test(arguments: ["HashFleetBrandLoop", "FleetClusterArtLoop", "MinerCoolingArtLoop"],
          [WebPPixelSize.Geometry.aspectFit, .logicalSize])
    func preservesEveryAuthoredFrameTimingAlphaAndComposition(name: String, geometry: WebPPixelSize.Geometry) async throws {
        let store = WebPFrameStore()
        let bytes = try data(name)
        let animation = try #require(await store.animation(for: bytes))
        #expect(animation.durations.count == 48)
        #expect(abs(animation.duration - 2.016) < 0.001)
        #expect(animation.durations.allSatisfy { abs($0 - 0.042) < 0.001 })
        let size = try #require(WebPPixelSize(displaySize: CGSize(width: 72, height: 50), scale: 2, geometry: geometry))
        let fitted = size.fitting(animation)
        var previous: Data?
        var changed = false
        for index in animation.durations.indices {
            let frame = try #require(await store.frame(for: animation, index: index, pixelSize: size))
            #expect(frame.image.width == fitted.width)
            #expect(frame.image.height == fitted.height)
            let actual = try pixels(frame.image)
            #expect(actual == (try reference(bytes, index: index, width: fitted.width, height: fitted.height)))
            #expect(actual[3] == 0, "Transparent corners must not turn opaque")
            if let previous, previous != actual { changed = true }
            previous = actual
        }
        #expect(changed, "The approved fan motion must not become a static poster")
        let stats = await store.statistics()
        #expect(stats.mainThreadDecodes == 0)
        #expect(stats.decodedFrames == 48)
        let byteLimit = await store.byteLimit
        #expect(stats.peakResidentBytes <= byteLimit)
        #expect(FleetLoadAnimatedArt.entranceDuration == .milliseconds(10080))
        #expect(FleetLoadAnimatedArt.replayDuration == .milliseconds(4032))
    }

    @Test func cacheSharesPreparedBitmapsAndKeepsRetinaVariantsSeparate() async throws {
        let store = WebPFrameStore()
        let animation = try #require(await store.animation(for: data()))
        let size = try #require(WebPPixelSize(displaySize: CGSize(width: 72, height: 72), scale: 2))
        let first = try #require(await store.frame(for: animation, index: 0, pixelSize: size))
        let same = try #require(await store.frame(for: animation, index: 0, pixelSize: size))
        #expect(first.image === same.image)
        let retina = try #require(WebPPixelSize(displaySize: CGSize(width: 72, height: 72), scale: 3))
        let other = try #require(await store.frame(for: animation, index: 0, pixelSize: retina))
        #expect(first.image.width == 144)
        #expect(other.image.width == 216)
        #expect(first.image !== other.image)
        let stats = await store.statistics()
        #expect(stats.decodedFrames == 2)
        #expect(stats.cacheHits == 1)
    }

    @Test func pinnedFramesAndConcurrentRequestsCannotOversubscribeTheCache() async throws {
        let size = try #require(WebPPixelSize(displaySize: CGSize(width: 64, height: 64), scale: 1))
        let store = WebPFrameStore(byteLimit: size.byteCost * 2)
        let animation = try #require(await store.animation(for: data()))
        var held: [WebPFrameLease] = []
        held.append(try #require(await store.frame(for: animation, index: 0, pixelSize: size)))
        held.append(try #require(await store.frame(for: animation, index: 1, pixelSize: size)))
        #expect(await store.frame(for: animation, index: 2, pixelSize: size) == nil)
        #expect((await store.statistics()).leasedFrames == 2)
        held.removeFirst()
        try await eventually { (await store.statistics()).leasedFrames == 1 }
        let next = try #require(await store.frame(for: animation, index: 2, pixelSize: size))
        #expect(next.index == 2)
        let stats = await store.statistics()
        #expect(stats.residentBytes <= size.byteCost * 2)
        #expect(stats.peakResidentBytes <= size.byteCost * 2)
        #expect(held.count == 1)
    }

    @Test func concurrentConsumersCoalesceToOneDecode() async throws {
        let store = WebPFrameStore()
        let animation = try #require(await store.animation(for: data()))
        let size = try #require(WebPPixelSize(displaySize: CGSize(width: 72, height: 72), scale: 2))
        let frames = await withTaskGroup(of: WebPFrameLease?.self, returning: [WebPFrameLease].self) { group in
            for _ in 0..<20 { group.addTask { await store.frame(for: animation, index: 7, pixelSize: size) } }
            var results: [WebPFrameLease] = []
            for await frame in group { if let frame { results.append(frame) } }
            return results
        }
        #expect(frames.count == 20)
        #expect(frames.allSatisfy { $0.image === frames.first?.image })
        let stats = await store.statistics()
        #expect(stats.decodedFrames == 1)
        #expect(stats.cacheHits == 19)
        #expect(stats.leasedFrames == 1)
    }

    @Test func rejectsInvalidInputsAndHonorsCancellation() async throws {
        let store = WebPFrameStore()
        #expect(await store.animation(for: Data()) == nil)
        #expect(await store.animation(for: Data("not an image".utf8)) == nil)
        #expect(WebPPixelSize(displaySize: .zero, scale: 2) == nil)
        #expect(WebPPixelSize(displaySize: CGSize(width: CGFloat.nan, height: 72), scale: 2) == nil)
        #expect(WebPPixelSize(displaySize: CGSize(width: 72, height: 72), scale: .infinity) == nil)
        #expect(WebPPixelSize(displaySize: CGSize(width: 5000, height: 72), scale: 2) == nil)
        let animation = try #require(await store.animation(for: data()))
        let size = try #require(WebPPixelSize(displaySize: CGSize(width: 72, height: 72), scale: 2))
        #expect(await store.frame(for: animation, index: -1, pixelSize: size) == nil)
        #expect(await store.frame(for: animation, index: 48, pixelSize: size) == nil)
        let task = Task {
            try? await Task.sleep(for: .milliseconds(100))
            return await store.frame(for: animation, index: 0, pixelSize: size)
        }
        task.cancel()
        #expect(await task.value == nil)
        #expect((await store.statistics()).decodedFrames == 0)
    }

    @Test func frameClockUsesOriginalDurationAcrossLoops() async throws {
        let store = WebPFrameStore()
        let animation = try #require(await store.animation(for: data()))
        #expect(animation.frameIndex(at: 0) == 0)
        #expect(animation.frameIndex(at: 0.043) == 1)
        #expect(animation.frameIndex(at: 2.016 + 0.043) == 1)
        #expect(animation.frameIndex(at: -.infinity) == 0)
        #expect(animation.frameIndex(at: .nan) == 0)
    }

    private func window(containing view: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -3000, y: -3000, width: 300, height: 300),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        return window // Never order front, activate, or interact with the operator's display.
    }

    @Test func pausedPosterAndResizePrepareTheCorrectDisplayGeometry() async throws {
        let view = WebPFrameImageView(frame: .zero, frameStore: WebPFrameStore())
        defer { view.stop() }
        let bytes = try data()
        view.configure(data: bytes, isPlaying: false, displaySize: CGSize(width: 120, height: 120))
        try await eventually { view.image != nil }
        #expect(view.currentFrameIndex == 0)
        #expect(view.image?.size == CGSize(width: 120, height: 120))
        view.configure(data: bytes, isPlaying: false, displaySize: CGSize(width: 240, height: 240))
        try await eventually { view.image?.size == CGSize(width: 240, height: 240) }
        #expect(view.currentFrameIndex == 0)
        #expect(view.imageScaling == .scaleProportionallyUpOrDown)
        view.configure(data: bytes, isPlaying: false, displaySize: CGSize(width: 120.1, height: 50.1))
        try await eventually { view.image?.size == CGSize(width: 120.1, height: 50.1) }
        view.configure(data: bytes, isPlaying: false, displaySize: CGSize(width: 120.2, height: 50.2))
        try await eventually { view.image?.size == CGSize(width: 120.2, height: 50.2) }
        let shown = try #require(view.image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        #expect(shown.width == Int(ceil(120.2 * scale)))
        #expect(shown.height == Int(ceil(50.2 * scale)))
    }

    @Test func playbackSurvivesDetachButPausedAndStoppedViewsDoNotRestart() async throws {
        let view = WebPFrameImageView(frame: CGRect(x: 0, y: 0, width: 120, height: 120), frameStore: WebPFrameStore())
        let bytes = try data()
        let host = window(containing: view)
        defer { view.stop(); view.removeFromSuperview(); host.close() }
        view.configure(data: bytes, isPlaying: true, displaySize: CGSize(width: 120, height: 120))
        try await eventually { (view.currentFrameIndex ?? 0) > 0 }
        view.removeFromSuperview()
        let detached = view.currentFrameIndex
        try await Task.sleep(for: .milliseconds(120))
        #expect(view.currentFrameIndex == detached)
        host.contentView?.addSubview(view)
        try await eventually { view.currentFrameIndex != detached }
        view.configure(data: bytes, isPlaying: false, displaySize: CGSize(width: 120, height: 120))
        try await eventually { view.currentFrameIndex == 0 }
        view.removeFromSuperview()
        host.contentView?.addSubview(view)
        try await Task.sleep(for: .milliseconds(120))
        #expect(view.currentFrameIndex == 0)
        view.stop()
        view.removeFromSuperview()
        host.contentView?.addSubview(view)
        try await Task.sleep(for: .milliseconds(120))
        #expect(view.currentFrameIndex == 0)
    }

    @Test func permanentFrameFailureStopsRetryingUntilTheGeometryChanges() async throws {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = try #require(WebPPixelSize(displaySize: CGSize(width: 64, height: 64), scale: scale))
        let store = WebPFrameStore(byteLimit: size.byteCost * 2)
        let view = WebPFrameImageView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), frameStore: store)
        let host = window(containing: view)
        defer { view.stop(); view.removeFromSuperview(); host.close() }
        let bytes = try data()
        view.configure(data: bytes, isPlaying: false, displaySize: CGSize(width: 64, height: 64))
        try await eventually { view.currentFrameIndex == 0 }
        let before = (await store.statistics()).frameRequests

        // This fitted bitmap cannot fit even in an otherwise empty cache. Unlike
        // temporary pinned pressure, retrying it on every display tick cannot help.
        view.configure(data: bytes, isPlaying: true, displaySize: CGSize(width: 128, height: 128))
        try await eventually { (await store.statistics()).frameRequests > before }
        try await Task.sleep(for: .milliseconds(250))
        let afterFailure = (await store.statistics()).frameRequests
        #expect(afterFailure == before + 1)
        let heldFrame = view.currentFrameIndex
        #expect(view.image != nil, "A permanent failure must preserve the last approved picture")
        try await Task.sleep(for: .milliseconds(250))
        #expect((await store.statistics()).frameRequests == afterFailure)
        #expect(view.currentFrameIndex == heldFrame)

        view.configure(data: bytes, isPlaying: true, displaySize: CGSize(width: 64, height: 64))
        try await eventually { view.currentFrameIndex != heldFrame }
        #expect((await store.statistics()).frameRequests > afterFailure)
        #expect((await store.statistics()).mainThreadDecodes == 0)
    }

    @Test func stoppingDuringColdPreparationDiscardsEveryLateResult() async throws {
        let view = WebPFrameImageView(frame: .zero, frameStore: WebPFrameStore())
        view.configure(data: try data(), isPlaying: true, displaySize: CGSize(width: 220, height: 220))
        view.stop()
        try await Task.sleep(for: .milliseconds(150))
        #expect(view.image == nil)
        #expect(view.currentFrameIndex == nil)
    }

    @Test func replacingTheAssetCannotPublishAnOldAsyncResult() async throws {
        let store = WebPFrameStore()
        let view = WebPFrameImageView(frame: .zero, frameStore: store)
        defer { view.stop() }
        view.configure(data: try data("HashFleetBrandLoop"), isPlaying: false, displaySize: CGSize(width: 72, height: 72))
        view.configure(data: try data("MinerCoolingArtLoop"), isPlaying: false, displaySize: CGSize(width: 90, height: 60))
        try await eventually { view.image?.size == CGSize(width: 90, height: 60) }
        let expected = try #require(await store.animation(for: data("MinerCoolingArtLoop")))
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = try #require(WebPPixelSize(displaySize: CGSize(width: 90, height: 60), scale: scale, geometry: .logicalSize))
        let frame = try #require(await store.frame(for: expected, index: 0, pixelSize: size))
        let shown = try #require(view.image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(try pixels(shown) == pixels(frame.image))
    }

    @Test func aColdPausedPosterRecoversAfterPinnedCachePressureClears() async throws {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = try #require(WebPPixelSize(displaySize: CGSize(width: 64, height: 64), scale: scale))
        let store = WebPFrameStore(byteLimit: size.byteCost * 2)
        let bytes = try data()
        let animation = try #require(await store.animation(for: bytes))
        var held: [WebPFrameLease] = []
        for index in [1, 2] { held.append(try #require(await store.frame(for: animation, index: index, pixelSize: size))) }
        let view = WebPFrameImageView(frame: .zero, frameStore: store)
        defer { view.stop() }
        view.configure(data: bytes, isPlaying: false, displaySize: CGSize(width: 64, height: 64))
        try await Task.sleep(for: .milliseconds(150))
        #expect(view.image == nil)
        #expect((await store.statistics()).decodedFrames == 2)
        held.removeAll()
        try await eventually { view.currentFrameIndex == 0 }
        #expect(view.image != nil)
        #expect((await store.statistics()).peakResidentBytes <= size.byteCost * 2)
    }

    @Test func preparationAndPressureRetryDoNotRetainAnAbandonedView() async throws {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = try #require(WebPPixelSize(displaySize: CGSize(width: 64, height: 64), scale: scale))
        let store = WebPFrameStore(byteLimit: size.byteCost)
        let bytes = try data()
        let animation = try #require(await store.animation(for: bytes))
        let held = try #require(await store.frame(for: animation, index: 1, pixelSize: size))
        weak var abandoned: WebPFrameImageView?
        do {
            let view = WebPFrameImageView(frame: .zero, frameStore: store)
            abandoned = view
            view.configure(data: bytes, isPlaying: true, displaySize: CGSize(width: 64, height: 64))
            try await Task.sleep(for: .milliseconds(120))
        }
        try await eventually { abandoned == nil }
        #expect(held.index == 1)
        #expect((await store.statistics()).decodedFrames == 1)
    }
}
