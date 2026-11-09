import Testing
import UIKit
import SwiftUI
@testable import HashFleet

@Suite @MainActor
struct LaunchBrandTests {
    @Test(arguments: [1, 2, 3])
    func minerFansResolveBothAppearancesForEveryRequestedScale(scale: Int) throws {
        var variants: [Data] = []
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection { traits in
                traits.userInterfaceStyle = style
                traits.displayScale = CGFloat(scale)
            }
            let image = try #require(UIImage(named: "MinerFans", in: .main, compatibleWith: traits))
            #expect(image.size == CGSize(width: 96, height: 96))
            // Device-specific builds may retain only the device's native scale.
            // UIKit's fallback must still preserve the 96-point logical size.
            #expect([1.0, 2.0, 3.0].contains(Double(image.scale)))
            let cgImage = try #require(image.cgImage)
            #expect(cgImage.width == Int(96 * image.scale))
            #expect(cgImage.height == Int(96 * image.scale))
            let pixels = try fanPixels(cgImage)
            let width = cgImage.width
            let height = cgImage.height
            // All four outer edges must be transparent, not a baked-in white/checkerboard tile.
            for x in 0..<width {
                #expect(pixels[x * 4 + 3] == 0)
                #expect(pixels[((height - 1) * width + x) * 4 + 3] == 0)
            }
            for y in 0..<height {
                #expect(pixels[(y * width) * 4 + 3] == 0)
                #expect(pixels[(y * width + width - 1) * 4 + 3] == 0)
            }
            let opaqueCount = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 240 }.count
            let coverage = Double(opaqueCount) / Double(width * height)
            #expect(coverage > 0.45 && coverage < 0.75)
            variants.append(Data(pixels))
        }
        // The onboarding card is FleetTheme.charcoal (0x111111) in BOTH appearances, so this
        // artwork is deliberately appearance-independent. Both traits must resolve the same master.
        #expect(variants[0] == variants[1], "MinerFans must resolve one master in both appearances")
    }

    @Test(arguments: [96.0, 200.0])
    func minerFansRenderInSwiftUIWithoutPlaceholderOrTint(size: Double) throws {
        var variants: [Data] = []
        for scheme in [ColorScheme.light, .dark] {
            let view = FleetMinerFansImage(size: size)
                .environment(\.colorScheme, scheme)
                .environment(\.displayScale, 3)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = try #require(renderer.cgImage)
            #expect(image.width == Int(size * 3))
            #expect(image.height == Int(size * 3))
            let pixels = try fanPixels(image)
            #expect(pixels.contains { $0 != 0 }, "Missing images render an empty frame")
            var goldPixels = 0
            for offset in stride(from: 0, to: pixels.count, by: 4) {
                let red = Int(pixels[offset])
                let blue = Int(pixels[offset + 2])
                let alpha = Int(pixels[offset + 3])
                if red > 130 && red > blue + 60 && alpha > 240 {
                    goldPixels += 1
                }
            }
            #expect(goldPixels > image.width * image.height / 20)
            let tinted = ImageRenderer(content: view.foregroundStyle(.pink))
            tinted.scale = 3
            #expect(try fanPixels(#require(tinted.cgImage)) == pixels)
            variants.append(Data(pixels))
        }
        #expect(variants[0] == variants[1], "SwiftUI must render the same master in both schemes")
    }

    /// Documents the invariant that makes a single MinerFans master correct.
    /// If charcoal ever becomes appearance-dependent, MinerFans needs a real light variant again.
    @Test func onboardingFanSurfaceIsIdenticalInBothAppearances() throws {
        let surface = UIColor(FleetTheme.charcoal)
        var values: [[CGFloat]] = []
        for style in [UIUserInterfaceStyle.light, .dark] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #expect(surface.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                .getRed(&r, green: &g, blue: &b, alpha: &a))
            values.append([r, g, b, a])
        }
        #expect(values[0] == values[1])
        // Dark enough that the graphite/gold artwork reads without a light-mode repaint.
        #expect(values[0][0] < 0.15 && values[0][1] < 0.15 && values[0][2] < 0.15)
    }

    @Test func fleetAndCoolingIllustrationsResolveAsTransparentBundledArtwork() throws {
        let names = ["FleetClusterArt", "MinerCoolingArt"]
        for name in names {
            let image = try #require(UIImage(named: name, in: .main, compatibleWith: nil), "Missing asset: \(name)")
            let cgImage = try #require(image.cgImage, "Asset did not decode: \(name)")
            let pixels = try fanPixels(cgImage)
            let width = cgImage.width
            let height = cgImage.height

            #expect(width >= 512 && height >= 512, "Artwork needs enough native pixels for the 3x UI sizes")
            for x in 0..<width {
                #expect(pixels[x * 4 + 3] <= 2, "Top edge must stay transparent: \(name)")
                #expect(pixels[((height - 1) * width + x) * 4 + 3] <= 2, "Bottom edge must stay transparent: \(name)")
            }
            for y in 0..<height {
                #expect(pixels[(y * width) * 4 + 3] <= 2, "Left edge must stay transparent: \(name)")
                #expect(pixels[(y * width + width - 1) * 4 + 3] <= 2, "Right edge must stay transparent: \(name)")
            }

            let visiblePixels = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 32 }.count
            #expect(visiblePixels > width * height / 8, "Artwork should contain a visible subject: \(name)")
        }
    }

    private func fanPixels(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    @Test func compiledLaunchCentersSingleMinerAndResolvesBothModes() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for size in [CGSize(width: 393, height: 852), CGSize(width: 852, height: 393)] {
                let controller = try #require(
                    UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController()
                )
                controller.overrideUserInterfaceStyle = style
                // Resolve the storyboard's adaptive image and system background using the target
                // appearance before UIKit instantiates the launch view hierarchy.
                controller.loadViewIfNeeded()
                controller.view.frame = CGRect(origin: .zero, size: size)
                controller.view.layoutIfNeeded()
                let images = controller.view.subviews.compactMap { $0 as? UIImageView }
                #expect(images.count == 1)
                let miner = try #require(images.first)
                #expect(abs(miner.center.x - size.width / 2) < 0.5)
                #expect(abs(miner.center.y - size.height / 2) < 0.5)
                #expect(miner.contentMode == .scaleAspectFit)
                #expect(miner.image != nil)
                #expect(miner.bounds.size == CGSize(width: 220, height: 220))
                let logo = try #require(
                    UIImage(
                        named: "HashFleetLaunch",
                        in: .main,
                        compatibleWith: UITraitCollection(userInterfaceStyle: style)
                    )
                )
                #expect(miner.image?.pngData() == logo.pngData())
                let background = try #require(controller.view.backgroundColor)
                    .resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                var white: CGFloat = 0
                var alpha: CGFloat = 0
                #expect(background.getWhite(&white, alpha: &alpha))
                let expectedWhite: CGFloat = style == .light ? 1 : 0
                #expect(abs(white - expectedWhite) < 0.01)
            }
        }
    }

    @Test func fleetMinerFansImageRendersInSmallSize() {
        let view = FleetMinerFansImage(size: 48)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        #expect(renderer.cgImage != nil)
    }
}
