import ImageIO
import Testing
import UIKit
@testable import HashFleet

private final class AnimatedWebPTestBundleAnchor: NSObject {}

@Suite
struct AnimatedWebPTests {
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

    @Test @MainActor func playerDisplaysTheOpeningFrameWhenMotionIsPaused() throws {
        let bundle = Bundle(for: AnimatedWebPTestBundleAnchor.self)
        let url = try #require(bundle.url(forResource: "animated-webp-2frames", withExtension: "webp"))
        let view = WebPFrameImageView(frame: .zero)
        view.configure(
            data: try Data(contentsOf: url),
            isPlaying: false,
            displaySize: CGSize(width: 220, height: 220)
        )

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
        if explicitStop { view.stop() }
        view.removeFromSuperview()
        controller.view.addSubview(view)
        let opening = try #require(view.image?.pngData())
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(25))
            #expect(view.image?.pngData() == opening, "Paused and dismantled players must stay still after reattachment")
        }
    }
}
