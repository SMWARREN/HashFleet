import ImageIO
import SwiftUI
import Testing
import UIKit
@testable import HashFleet

private final class AnimatedWebPTestBundleAnchor: NSObject {}

@Suite
struct AnimatedWebPTests {
    /// Off-main preparation is intentionally asynchronous. Keep the original image,
    /// geometry and motion assertions, but wait for a realized frame rather than
    /// forcing a synchronous WebP decode just to satisfy a test's setup assumption.
    @MainActor private func waitForPreparedFrame(_ view: WebPFrameImageView) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while view.currentFrameIndex == nil {
            guard ContinuousClock.now < deadline else { throw PreparationFailure.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(view.image != nil)
    }

    private enum PreparationFailure: Error { case timeout }

    @Test func frameDurationIgnoresZeroDelayAndPrefersUnclampedTiming() {
        let zeroDelay: [CFString: Any] = [
            kCGImagePropertyWebPUnclampedDelayTime: NSNumber(value: 0),
            kCGImagePropertyWebPDelayTime: NSNumber(value: 0)
        ]
        #expect(AnimatedWebPImage.frameDuration(from: zeroDelay) == 1.0 / 24.0)

        let separateDelays: [CFString: Any] = [
            kCGImagePropertyWebPUnclampedDelayTime: NSNumber(value: 0.042),
            kCGImagePropertyWebPDelayTime: NSNumber(value: 0.01)
        ]
        #expect(abs(AnimatedWebPImage.frameDuration(from: separateDelays) - 0.042) < 0.000001)
    }

    @Test func decodesTheBundledBrandLoopFromTheApplicationAssetCatalog() throws {
        let asset = try #require(NSDataAsset(name: "HashFleetBrandLoop"))
        let source = try #require(CGImageSourceCreateWithData(asset.data as CFData, nil))

        #expect(CGImageSourceGetType(source) as String? == "org.webmproject.webp")
        #expect(CGImageSourceGetCount(source) == 48)
        #expect(AnimatedWebPImage.isAnimated(asset.data))

        let openingProperties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let openingWebP = try #require(
            openingProperties[kCGImagePropertyWebPDictionary] as? [CFString: Any]
        )
        let openingDelay = try #require(
            (openingWebP[kCGImagePropertyWebPDelayTime] as? NSNumber)?.doubleValue
        )
        #expect(openingDelay >= 0.04 && openingDelay <= 0.05)

        let openingFrame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let nextFrame = try #require(CGImageSourceCreateImageAtIndex(source, 1, nil))
        #expect(openingFrame.width == 640)
        #expect(openingFrame.height == 640)
        #expect(nextFrame.width == 640)
        #expect(nextFrame.height == 640)
        let firstFrameData = try #require(UIImage(cgImage: openingFrame).pngData())
        let nextFrameData = try #require(UIImage(cgImage: nextFrame).pngData())
        #expect(firstFrameData != nextFrameData, "The bundled miner fan must visibly animate")

        let alpha = try #require(openingProperties[kCGImagePropertyHasAlpha] as? Bool)
        #expect(alpha)
    }

    @Test func decodesTransparentAnimatedWebPFramesAndTiming() throws {
        let bundle = Bundle(for: AnimatedWebPTestBundleAnchor.self)
        let url = try #require(bundle.url(forResource: "animated-webp-2frames", withExtension: "webp"))
        let data = try Data(contentsOf: url)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))

        #expect(CGImageSourceGetType(source) as String? == "org.webmproject.webp")
        #expect(CGImageSourceGetCount(source) == 2)
        #expect(AnimatedWebPImage.isAnimated(data))

        var decodedFrames: [Data] = []
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = try #require(
                CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            )
            #expect(properties[kCGImagePropertyHasAlpha] as? Bool == true)

            let webP = try #require(properties[kCGImagePropertyWebPDictionary] as? [CFString: Any])
            let delay = try #require((webP[kCGImagePropertyWebPDelayTime] as? NSNumber)?.doubleValue)
            #expect(delay >= 0.03 && delay <= 0.06)

            let frame = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
            decodedFrames.append(try #require(UIImage(cgImage: frame).pngData()))
        }

        #expect(decodedFrames[0] != decodedFrames[1], "The animation fixture must contain visible frame changes")
    }

    @Test func rejectsStaticPNGAsAnAnimatedWebP() throws {
        let image = try #require(UIImage(systemName: "fanblades.fill"))
        let png = try #require(image.pngData())

        #expect(!AnimatedWebPImage.isAnimated(png))
    }

    @Test @MainActor func requestedPlaybackResumesWhenTheImageIsReattachedToItsWindow() async throws {
        let bundle = Bundle(for: AnimatedWebPTestBundleAnchor.self)
        let url = try #require(bundle.url(forResource: "animated-webp-2frames", withExtension: "webp"))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        let view = WebPFrameImageView(frame: window.bounds)
        defer {
            view.stop()
            view.removeFromSuperview()
            window.isHidden = true
        }
        view.configure(data: try Data(contentsOf: url), isPlaying: true,
                       displaySize: CGSize(width: 120, height: 120))
        controller.view.addSubview(view)
        view.removeFromSuperview()
        controller.view.addSubview(view)
        try await waitForPreparedFrame(view)
        let opening = try #require(view.image?.pngData())
        var didAdvance = false
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(25))
            if view.image?.pngData() != opening {
                didAdvance = true
                break
            }
        }
        #expect(didAdvance, "A requested animation must resume after window reattachment without needing a tap or another SwiftUI update")
    }

    @Test @MainActor func playerDisplaysTheOpeningFrameWhenMotionIsPaused() async throws {
        let bundle = Bundle(for: AnimatedWebPTestBundleAnchor.self)
        let url = try #require(bundle.url(forResource: "animated-webp-2frames", withExtension: "webp"))
        let view = WebPFrameImageView(frame: .zero)
        view.configure(
            data: try Data(contentsOf: url),
            isPlaying: false,
            displaySize: CGSize(width: 220, height: 220)
        )

        try await waitForPreparedFrame(view)
        let image = try #require(view.image)
        #expect(image.size == CGSize(width: 220, height: 220))
        #expect(view.contentMode == UIView.ContentMode.scaleAspectFit)
        view.stop()
    }

    @Test @MainActor func fleetEntranceUsesFiveRealBundledFanLoops() throws {
        let asset = try #require(NSDataAsset(name: "FleetClusterArtLoop"))
        let source = try #require(CGImageSourceCreateWithData(asset.data as CFData, nil))
        let duration = (0..<CGImageSourceGetCount(source)).reduce(0.0) { total, index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let webP = properties?[kCGImagePropertyWebPDictionary] as? [CFString: Any]
            return total + AnimatedWebPImage.frameDuration(from: webP)
        }
        #expect(abs(duration - 2.016) < 0.001)
        #expect(FleetLoadAnimatedArt.entranceDuration == .milliseconds(10080))
        #expect(FleetLoadAnimatedArt.replayDuration == .milliseconds(4032))
    }

    @Test(arguments: [false, true]) @MainActor
    func pausedOrExplicitlyStoppedPlaybackDoesNotResumeOnReattachment(explicitStop: Bool) async throws {
        let bundle = Bundle(for: AnimatedWebPTestBundleAnchor.self)
        let url = try #require(bundle.url(forResource: "animated-webp-2frames", withExtension: "webp"))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        let view = WebPFrameImageView(frame: window.bounds)
        defer {
            view.stop()
            view.removeFromSuperview()
            window.isHidden = true
        }
        view.configure(data: try Data(contentsOf: url), isPlaying: explicitStop,
                       displaySize: CGSize(width: 120, height: 120))
        controller.view.addSubview(view)
        try await waitForPreparedFrame(view)
        if explicitStop { view.stop() }
        view.removeFromSuperview()
        controller.view.addSubview(view)
        let opening = try #require(view.image?.pngData())
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(25))
            #expect(view.image?.pngData() == opening, "Paused and dismantled players must stay still after reattachment")
        }
    }

    @MainActor private func mountedPlayer(in view: UIView) -> WebPFrameImageView? {
        if let player = view as? WebPFrameImageView { return player }
        for child in view.subviews {
            if let player = mountedPlayer(in: child) { return player }
        }
        return nil
    }

    @Test @MainActor func coldPosterKeepsRequestedUIKitBoundsBeforeAnyFramePrepares() throws {
        let cases: [(String, String, CGSize)] = [
            ("HashFleetBrandLoop", "HashFleetLaunch", CGSize(width: 220, height: 220)),
            ("FleetClusterArtLoop", "FleetClusterArt", CGSize(width: 72, height: 50)),
            ("MinerCoolingArtLoop", "MinerCoolingArt", CGSize(width: 180, height: 106))
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (assetName, posterName, size) in cases {
                let asset = try #require(NSDataAsset(name: assetName))
                let hosting = UIHostingController(rootView:
                    AnimatedWebPImage(data: asset.data, isPlaying: false,
                                      displaySize: size, posterName: posterName)
                        .frame(width: size.width, height: size.height))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
                window.overrideUserInterfaceStyle = style
                window.rootViewController = hosting
                window.isHidden = false
                defer {
                    mountedPlayer(in: hosting.view)?.stop()
                    window.isHidden = true
                    window.rootViewController = nil
                }
                hosting.view.frame = window.bounds
                hosting.view.setNeedsLayout()
                hosting.view.layoutIfNeeded()
                window.layoutIfNeeded()
                let player = try #require(mountedPlayer(in: hosting.view))
                #expect(player.image != nil)
                #expect(player.currentFrameIndex == nil,
                        "Check the actual PNG phase synchronously, before a prepared frame can publish")
                #expect(player.bounds.size == size,
                        "The real UIKit view, not only its SwiftUI container, must respect the requested bounds")
                #expect(player.contentMode == .scaleAspectFit)
                print("Cold poster \(posterName), style=\(style.rawValue), requested=\(size), UIKit bounds=\(player.bounds.size), intrinsic=\(player.intrinsicContentSize)")
            }
        }
    }

    @Test @MainActor func approvedPosterIsVisibleImmediatelyWhileTheColdLoopPrepares() async throws {
        let asset = try #require(NSDataAsset(name: "HashFleetBrandLoop"))
        let store = WebPFrameStore()
        let view = WebPFrameImageView(frame: .zero, frameStore: store)
        defer { view.stop() }
        view.configure(data: asset.data, isPlaying: false, displaySize: CGSize(width: 220, height: 220),
                       posterName: "HashFleetLaunch")
        #expect(view.image != nil, "Cold loading must keep the approved PNG visible without decoding WebP on main")
        #expect(view.currentFrameIndex == nil)
        try await waitForPreparedFrame(view)
        #expect(view.currentFrameIndex == 0)
        #expect(view.image?.size == CGSize(width: 220, height: 220))
        #expect((await store.statistics()).mainThreadDecodes == 0)
    }
}
