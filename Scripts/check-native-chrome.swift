import AppKit
import SwiftUI

// Compile with the real production source, without launching the app/test host:
// xcrun swiftc -parse-as-library App/Design/FleetTypography.swift App/Design/FleetHeaderTitle.swift \
//   App/Design/FleetHeaderArtwork.swift MacApp/FleetMacChrome.swift Shared/FleetToolbarLocation.swift \
//   Scripts/check-native-chrome.swift -o "$JCODE_SCRATCH_DIR/check-native-chrome"
// The process prohibits activation, never creates/orders a window and renders only
// its own SwiftUI components. This is not a live fullscreen or native-menu review.
@main
struct NativeChromeChecks {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    static func run() throws {
        let app = NSApplication.shared
        if app.activationPolicy() != .prohibited {
            try require(app.setActivationPolicy(.prohibited), "Could not prohibit activation")
        }
        try require(app.activationPolicy() == .prohibited, "Runner activation must remain prohibited")
        try require(!app.isActive && app.windows.isEmpty, "Offscreen runner must have no active app/window")
        let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        var checks = 0

        for scheme in [ColorScheme.dark, .light] {
            let expected: UInt32 = scheme == .dark ? 0x000000 : 0xFFFFFF
            let image = try render(FleetMacChrome.background.frame(width: 180, height: 52), scheme: scheme)
            for point in [(1, 1), (90, 26), (178, 50)] {
                try expectPixel(image, point.0, point.1, expected)
            }
            checks += 1

            for enabled in [true, false] {
                let control = try render(
                    FleetMacToolbarControl { Color.clear.frame(width: 12, height: 12) }
                        .environment(\.isEnabled, enabled)
                        .padding(20)
                        .background(Color(.sRGB, red: 1, green: 0, blue: 1)),
                    scheme: scheme)
                try require(control.width == 84 && control.height == 84, "Control target must remain 44x44")
                try expectPixel(control, 42, 30, expected)
                try expectPixel(control, 24, 24, 0xFF00FF)
                try expectPixel(control, 26, 26, 0xFF00FF)
                try expectPixel(control, 42, 20, 0xFF00FF)
                checks += 1
            }

            let menu = try render(
                Color.clear.frame(width: 360, height: 540)
                    .fleetMacMenuSurface()
                    .padding(20)
                    .background(Color(.sRGB, red: 1, green: 0, blue: 1)),
                scheme: scheme)
            try require(menu.width == 400 && menu.height == 580, "Status menu must preserve its content bounds")
            for point in [(20, 20), (22, 22), (379, 20), (20, 559), (379, 559)] {
                try expectPixel(menu, point.0, point.1, 0xFF00FF)
            }
            for point in [(200, 20), (20, 290), (200, 290), (379, 290)] {
                try expectPixel(menu, point.0, point.1, expected)
            }
            if let output { try save(menu, to: output.appendingPathComponent("menu-surface-\(scheme).png")) }
            checks += 1

            let action = try render(
                Button("Open Hash Fleet") {}.buttonStyle(FleetMacToolbarButtonStyle()), scheme: scheme)
            try require(action.height == 44 && action.width >= 110, "Text action must keep 44pt target and text insets")
            checks += 1

            for size in [CGSize(width: 260, height: 420), CGSize(width: 300, height: 780),
                         CGSize(width: 400, height: 540)] {
                let fill = Color(.sRGB, red: 1, green: 1, blue: 0)
                let sidebar = try render(
                    fill.frame(width: size.width, height: size.height)
                        .fleetMacSidebarSurface(fill: fill), scheme: scheme)
                let top = Int(FleetMacChrome.sidebarTopInset)
                let bottom = sidebar.height - 1
                try require(sidebar.width == Int(size.width), "Sidebar rounding must not change column width")
                for point in [(0, top), (2, top + 2), (sidebar.width - 1, top),
                              (0, bottom), (sidebar.width - 1, bottom)] {
                    try expectPixel(sidebar, point.0, point.1, expected)
                }
                for point in [(sidebar.width / 2, top), (0, sidebar.height / 2), (sidebar.width / 2, bottom)] {
                    try expectPixel(sidebar, point.0, point.1, 0xFFFF00)
                }
                if let output {
                    try save(sidebar, to: output.appendingPathComponent("sidebar-corners-\(Int(size.width))-\(scheme).png"))
                }
                checks += 1
            }
        }

        for compact in ["4/4 22.00 TH/s", "DEMO 3/3 3.02 TH/s", "DEMO 3/3 3.02 TH/s !", "0/0 Not reported", "24/24 120 TH/s"] {
            let title = FleetMacChrome.statusTitle(compactTitle: compact)
            try require(title == compact, "Status title must omit the name while retaining complete telemetry, demo and stale state")
            checks += 1
        }

        // The requested title is standalone, not the previous inline logo/name group.
        // Compare actual title pixels with the original iPad text recipe at each category.
        for category in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            let brand = try render(FleetMacToolbarBrand().environment(\.dynamicTypeSize, category), scheme: .dark)
            let originalIPadTitle = try render(
                Text("Hash Fleet").fleetFont(.headline).lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(FleetMacChrome.foreground)
                    .frame(minHeight: 44).fixedSize(horizontal: true, vertical: false)
                    .environment(\.dynamicTypeSize, category), scheme: .dark)
            try require(brand.width == originalIPadTitle.width && brand.height == originalIPadTitle.height,
                        "Standalone native wordmark must retain the original iPad headline metrics and cap")
            try require(try pixelData(brand) == pixelData(originalIPadTitle),
                        "The actual shared wordmark must retain the original iPad glyphs, weight and spacing")
            checks += 1
        }
        let artwork = try render(FleetHeaderArtwork(), scheme: .dark)
        try require(artwork.width == 44 && artwork.height == 44, "Desktop artwork must fill its existing 44pt target without changing wordmark metrics")
        checks += 1

        for symbol in ["gearshape", "ellipsis"] {
            let menu = Menu { Button("Open settings") {} } label: {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
            }.fleetToolbarMenu()
            let size = hostedSize(menu)
            try require(size.width >= 44 && size.height == 44,
                        "Actual SwiftUI Menu \(symbol) must retain a 44pt target, not only the generic Button fixture")
            checks += 1
        }
        let brokenMenu = Menu { Button("Open settings") {} } label: {
            Image(systemName: "gearshape").font(.system(size: 14, weight: .medium))
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fleetToolbarMenu()
        let brokenSize = hostedSize(brokenMenu)
        try require(brokenSize.width < 44 && brokenSize.height < 44,
                    "Negative control must detect the former inner-plain Menu regression")
        checks += 1

        for width: CGFloat in [480, 728, 1_028, 2_056] {
            let header = try render(
                HStack(spacing: 8) {
                    FleetHeaderArtwork().frame(width: 44, height: 44)
                    Text("Little Supra").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Refresh", systemImage: "arrow.triangle.2.circlepath") {}
                        .labelStyle(.iconOnly).buttonStyle(FleetMacToolbarButtonStyle())
                    Button("Manage miner", systemImage: "ellipsis") {}
                        .labelStyle(.iconOnly).buttonStyle(FleetMacToolbarButtonStyle())
                }
                .foregroundStyle(FleetMacChrome.foreground)
                .padding(.horizontal, 12)
                .frame(width: width, height: 52)
                .overlay { FleetMacToolbarBrand() }
                .background(FleetMacChrome.background), scheme: .dark)
            try require(header.width == Int(width) && header.height == 52, "Component header must fit requested width")
            for point in [(0, 0), (Int(width / 2), 0), (Int(width) - 1, 51)] {
                try expectPixel(header, point.0, point.1, 0x000000)
            }
            if let output { try save(header, to: output.appendingPathComponent("component-header-\(Int(width)).png")) }
            checks += 1
        }

        try require(!app.isActive && app.windows.isEmpty && app.activationPolicy() == .prohibited,
                    "Offscreen validation must never create or activate a window")
        print("PASS: \(checks) offscreen chrome checks, no app activation or windows")
        print("DEFERRED: native menu opening, system toolbar overflow and actual maximize/minimize/fullscreen visual acceptance")
    }

    @MainActor
    static func render<V: View>(_ view: V, scheme: ColorScheme) throws -> CGImage {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = 1
        renderer.colorMode = .nonLinear
        guard let image = renderer.cgImage else { throw Failure(description: "Component did not render") }
        return image
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    @MainActor
    static func hostedSize<V: View>(_ view: V) -> CGSize {
        // A real Menu goes through AppKit hosting, without constructing/ordering a window.
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        return host.fittingSize
    }

    static func pixelData(_ image: CGImage) throws -> Data {
        guard let data = image.dataProvider?.data, CFDataGetLength(data) > 0 else {
            throw Failure(description: "Rendered text must contain readable pixel data")
        }
        return data as Data
    }

    static func expectPixel(_ image: CGImage, _ x: Int, _ y: Int, _ expected: UInt32) throws {
        let bytesPerRow = image.width * 4
        var bytes = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        try bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw Failure(description: "Could not read rendered pixels")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = y * bytesPerRow + x * 4
        let expectedChannels = [Int((expected >> 16) & 255), Int((expected >> 8) & 255), Int(expected & 255)]
        let observed = (0..<3).map { Int(bytes[offset + $0]) }
        try require(zip(observed, expectedChannels).allSatisfy { abs($0 - $1) <= 2 } && bytes[offset + 3] == 255,
                    "Pixel (\(x),\(y)) expected \(String(expected, radix: 16)), observed \(observed)")
    }

    static func save(_ image: CGImage, to url: URL) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure(description: "Could not encode component fixture")
        }
        try png.write(to: url)
    }
}
