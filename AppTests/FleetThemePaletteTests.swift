import SwiftUI
import Testing
@testable import HashFleet

@Suite("Shared palette parity")
struct FleetThemePaletteTests {
    @MainActor
    @Test func sharedPaletteKeepsTheApprovedLightAndDarkColors() {
        let palette: [(Color, UInt32, UInt32)] = [
            (FleetTheme.canvas, 0xFFFFFF, 0x02090C),
            (FleetTheme.surface, 0xF5F5F5, 0x10191D),
            (FleetTheme.raised, 0xE5E5E5, 0x182126),
            (FleetTheme.ink, 0x21201E, 0xF4F6F7),
            (FleetTheme.secondary, 0x595959, 0xBFC6CC),
            (FleetTheme.accent, 0x8A5000, 0xF5AC26),
            (FleetTheme.panelAccent, 0xE9931E, 0xF5AC26),
            (FleetTheme.charcoal, 0x111111, 0x111111),
            (FleetTheme.buttonInk, 0xFFFFFF, 0x10120F),
            (FleetTheme.controlBorder, 0x897869, 0x566F7C),
            (FleetTheme.positive, 0x356447, 0x25A354),
            (FleetTheme.warning, 0x864705, 0xF5AC26),
            (FleetTheme.separator, 0xCCCCCC, 0x27343A)
        ]
        for scheme in [ColorScheme.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            for (color, light, dark) in palette {
                let rgb = scheme == .light ? light : dark
                let actual = color.resolve(in: environment)
                #expect(abs(actual.red - Float((rgb >> 16) & 255) / 255) < 0.005)
                #expect(abs(actual.green - Float((rgb >> 8) & 255) / 255) < 0.005)
                #expect(abs(actual.blue - Float(rgb & 255) / 255) < 0.005)
                #expect(actual.opacity == 1)
            }
        }
    }

    @MainActor
    @Test(arguments: [ColorScheme.light, .dark], FleetPrimaryButtonStyle.Tone.allCases)
    func buttonLabelAndDisabledContrastUseApprovedPairs(scheme: ColorScheme, tone: FleetPrimaryButtonStyle.Tone) {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let (expectedInk, expectedFill): (Color, Color) = switch tone {
        case .accent: (FleetTheme.buttonInk, FleetTheme.accent)
        case .darkPanel: (FleetTheme.charcoal, FleetTheme.panelAccent)
        case .secondary: (FleetTheme.ink, FleetTheme.raised)
        }
        for isEnabled in [true, false] {
            let palette = FleetPrimaryButtonStyle.Palette.resolve(tone, isEnabled: isEnabled)
            let ink = palette.ink.resolve(in: environment)
            let fill = palette.fill.resolve(in: environment)
            let darker = min(luminance(ink), luminance(fill))
            let lighter = max(luminance(ink), luminance(fill))
            #expect(ink == (isEnabled ? expectedInk : FleetTheme.secondary).resolve(in: environment))
            #expect(fill == (isEnabled ? expectedFill : FleetTheme.surface).resolve(in: environment))
            #expect(ink.opacity == 1 && fill.opacity == 1)
            #expect((lighter + 0.05) / (darker + 0.05) >= 4.5,
                    "Readable \(tone) in \(scheme), enabled: \(isEnabled)")
        }
    }

    @MainActor
    @Test(arguments: [ColorScheme.light, .dark], FleetPrimaryButtonStyle.Tone.allCases)
    func mountedButtonKeepsItsLabelInkAndFill(scheme: ColorScheme, tone: FleetPrimaryButtonStyle.Tone) throws {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        for isEnabled in [true, false] {
            let button = Button {} label: { Label("Review", systemImage: "hand.raised") }
                .buttonStyle(FleetPrimaryButtonStyle(tone: tone, size: .compact, fullWidth: true))
                .disabled(!isEnabled)
                .tint(.blue) // An outside tint must not replace the label foreground.
                .environment(\.colorScheme, scheme)
                .frame(width: 200)
            let renderer = ImageRenderer(content: button)
            renderer.scale = 3
            let image = try #require(renderer.cgImage)
            let palette = FleetPrimaryButtonStyle.Palette.resolve(tone, isEnabled: isEnabled)
            let ink = palette.ink.resolve(in: environment)
            let fill = palette.fill.resolve(in: environment)
            let pixels = try interiorPixelCounts(in: image, ink: ink, fill: fill)
            #expect(pixels.ink > 40, "The label itself must render the specified ink, including when disabled")
            #expect(pixels.fill > 1_000, "The visible button surface must render the original fill")
            #expect(image.height >= 44 * 3)
        }
    }

    @MainActor
    @Test(arguments: [ColorScheme.light, .dark])
    func compactButtonRendersAtNarrowAccessibleWidth(scheme: ColorScheme) throws {
        let button = Button("Review changes before sending") {}
            .buttonStyle(FleetPrimaryButtonStyle(size: .compact, fullWidth: true))
            .dynamicTypeSize(.accessibility3)
            .environment(\.colorScheme, scheme)
            .frame(width: 220)
        let image = try #require(ImageRenderer(content: button).cgImage)
        #expect(image.width == 220)
        #expect(image.height > 44, "A longer accessibility label should wrap, not shrink into 44 points")
    }

    private func luminance(_ color: Color.Resolved) -> Double {
        func linear(_ raw: Float) -> Double {
            let value = Double(raw)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    private func interiorPixelCounts(in image: CGImage, ink: Color.Resolved, fill: Color.Resolved) throws
        -> (ink: Int, fill: Int) {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let rowBytes = image.width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * image.height)
        return try bytes.withUnsafeMutableBytes { storage in
            let context = try #require(CGContext(
                data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: rowBytes, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = storage.bindMemory(to: UInt8.self)
            func matches(_ color: Color.Resolved, _ offset: Int) -> Bool {
                abs(Int(pixels[offset]) - Int((color.red * 255).rounded())) <= 3
                    && abs(Int(pixels[offset + 1]) - Int((color.green * 255).rounded())) <= 3
                    && abs(Int(pixels[offset + 2]) - Int((color.blue * 255).rounded())) <= 3
                    && pixels[offset + 3] == 255
            }
            var counts = (ink: 0, fill: 0)
            // Exclude the rounded corners and stroke: only the label can supply ink here.
            for y in (image.height / 4)..<(3 * image.height / 4) {
                for x in (image.width / 5)..<(4 * image.width / 5) {
                    let offset = y * rowBytes + x * 4
                    if matches(ink, offset) { counts.ink += 1 }
                    if matches(fill, offset) { counts.fill += 1 }
                }
            }
            return counts
        }
    }
}
