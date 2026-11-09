import Foundation
import SwiftUI
import Testing
import ImageIO
import UniformTypeIdentifiers
import HashFleetCore
#if os(iOS)
import UIKit
#endif
#if os(macOS)
@testable import HashFleetMac
#else
@testable import HashFleet
#endif

/// Uses the production components and offline demo data, never a saved fleet or a scanner.
@Suite("Rounded surface content clearance", .serialized)
@MainActor
struct FleetRoundedSurfaceSpacingTests {
    private func image<V: View>(_ view: V) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }

    private func save(_ image: CGImage, named name: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashfleet-rounded-spacing-20261106", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(macOS)
        let platform = "mac"
        #else
        let platform = "ios"
        #endif
        let url = directory.appendingPathComponent("\(platform)-\(name).png")
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        print("ROUNDED_SPACING_ARTIFACT \(url.path)")
    }

    @Test func pillPaddingIsInsideTheSurfaceOnAllFourSides() throws {
        let label = Text("Live reading").font(.system(size: 16)).fixedSize()
        let plain = try image(label)
        let padded = try image(label.fleetPillPadding().background(.black, in: Capsule()))
        #expect(abs(padded.width - plain.width - 24) <= 1)
        #expect(abs(padded.height - plain.height - 12) <= 1)
        #expect(FleetSurfaceSpacing.selection.leading >= 12)
        #expect(FleetSurfaceSpacing.selection.trailing >= 12)
        #expect(FleetSurfaceSpacing.selection.top >= 8)
        #expect(FleetSurfaceSpacing.selection.bottom >= 8)
    }

    @Test func cardPaddingIsRealContentSpaceRatherThanAnOuterMargin() throws {
        let content = Color.white.frame(width: 80, height: 40)
        let rendered = try image(content.fleetCard(
            padding: FleetSurfaceSpacing.cardInset, fill: .black, border: .clear
        ))
        #expect(rendered.width == 112)
        #expect(rendered.height == 72)
    }

    @Test func tourClearanceIsSharedAndClippedToTheViewport() throws {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let target = CGRect(x: 100, y: 120, width: 220, height: 44)
        let expanded = try #require(FleetTourGeometry.clippedTarget(
            target, outset: FleetTourGeometry.highlightOutset, in: bounds
        ))
        #expect(expanded == CGRect(x: 88, y: 108, width: 244, height: 68))
        let edge = CGRect(x: 0, y: 2, width: 100, height: 44)
        let clipped = try #require(FleetTourGeometry.clippedTarget(
            edge, outset: FleetTourGeometry.highlightOutset, in: bounds
        ))
        #expect(bounds.contains(clipped))
        #expect(clipped.contains(edge))
    }

    /// Bright parent gutters reveal content escaping the allocated range-control width.
    @Test(arguments: [240.0, 320.0, 390.0, 760.0], [false, true])
    func actualHistorySelectorsDoNotPaintIntoTheirParentGutters(width: Double, accessibility: Bool) throws {
        let devices = DemoFleet.devices
        let card = FleetHistoryCard(devices: devices, snapshots: DemoFleet.snapshots(for: devices),
                                   isDemo: true, initialRecentRange: .day)
        let rendered = try image(card.windowControls
            .environment(\.dynamicTypeSize, accessibility ? .accessibility3 : .large)
            .environment(\.colorScheme, .dark)
            .frame(width: width)
            .padding(24)
            .background(Color(red: 1, green: 0, blue: 1)))
        #expect(rendered.width == Int(width) + 48)
        var pixels = [UInt8](repeating: 0, count: rendered.width * rendered.height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: rendered.width, height: rendered.height,
            bitsPerComponent: 8, bytesPerRow: rendered.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        var escapedPixels = 0
        for y in 0..<rendered.height {
            for x in Array(0..<16) + Array((rendered.width - 16)..<rendered.width) {
                let offset = (y * rendered.width + x) * 4
                if pixels[offset] < 250 || pixels[offset + 1] > 5 || pixels[offset + 2] < 250 {
                    escapedPixels += 1
                }
            }
        }
        #expect(escapedPixels == 0, "Range labels or highlights escaped their allocated width")
        try save(rendered, named: "selectors-\(Int(width))-\(accessibility ? "a11y" : "normal")")
    }

    @Test(arguments: [320.0, 390.0, 760.0], [false, true])
    func productionRoundedSurfacesRenderWithWrappingAtPhoneAndTabletWidths(width: Double, accessibility: Bool) throws {
        let devices = DemoFleet.devices
        for scheme in [ColorScheme.light, .dark] {
            let gallery = VStack(alignment: .leading, spacing: 16) {
                Text("Rounded surface spacing").fleetFont(.title2, weight: .bold)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        FleetStatusBadge(title: "Live reading", color: FleetTheme.positive)
                        Text("Last known reading").fleetFont(.caption).fleetPillPadding()
                            .background(FleetTheme.raised, in: Capsule())
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        FleetStatusBadge(title: "Live reading", color: FleetTheme.positive)
                        Text("Last known reading").fleetFont(.caption).fleetPillPadding()
                            .background(FleetTheme.raised, in: Capsule())
                    }
                }
                FleetSettingsCard {
                    FleetSettingsCardHeader(title: "Frequency & voltage", subtitle: "Review before applying", symbol: "slider.horizontal.3")
                    Text("Long descriptions wrap naturally inside the rounded panel, with space between the text and every curved edge.")
                        .fleetFont(.body).fixedSize(horizontal: false, vertical: true)
                }
                MinerControlsCard {
                    MinerControlsHeader(title: "Miner controls", subtitle: "Demo only. Nothing is sent.", symbol: "shield")
                    Text("525 MHz · 1150 mV").fleetFont(.body)
                }
                FleetHistoryCard(devices: devices, snapshots: DemoFleet.snapshots(for: devices),
                                 isDemo: true, initialRecentRange: .day)
                Button("Review this change") {}.buttonStyle(FleetPrimaryButtonStyle())
            }
            .padding(16)
            .frame(width: width, alignment: .topLeading)
            .background(FleetTheme.canvas)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility3 : .large)
            .transaction { $0.disablesAnimations = true }
            let rendered = try image(gallery)
            #expect(rendered.width == Int(width))
            #expect(rendered.height > 300)
            try save(rendered, named: "surfaces-\(Int(width))-\(accessibility ? "a11y" : "normal")-\(scheme == .dark ? "dark" : "light")")
        }
    }

    #if os(iOS)
    /// ImageRenderer cannot flatten UIKit menus or the chart pager. Mount those
    /// production controls before judging their pixels, within the offline test host.
    @Test(arguments: ["390x844", "844x390", "768x1024", "320x812-a11y"])
    func mountedSurfacesRemainReadableAfterScrollingAndReturning(_ viewport: String) async throws {
        let dimensions = viewport.split(separator: "-")[0].split(separator: "x")
        let width = try #require(Double(dimensions[0]))
        let height = try #require(Double(dimensions[1]))
        let devices = DemoFleet.devices
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rounded surface spacing").fleetFont(.title2, weight: .bold)
                FleetStatusBadge(title: "Live reading", color: FleetTheme.positive)
                FleetSettingsCard {
                    FleetSettingsCardHeader(title: "Frequency & voltage", subtitle: "Review before applying", symbol: "slider.horizontal.3")
                    Text("Long descriptions wrap naturally inside the rounded panel, with space between the text and every curved edge.")
                        .fleetFont(.body).fixedSize(horizontal: false, vertical: true)
                }
                MinerControlsCard {
                    MinerControlsHeader(title: "Miner controls", subtitle: "Demo only. Nothing is sent.", symbol: "shield")
                    Text("525 MHz · 1150 mV").fleetFont(.body)
                }
                FleetHistoryCard(devices: devices, snapshots: DemoFleet.snapshots(for: devices),
                                 isDemo: true, initialRecentRange: .day)
                // Include lower production cards so every viewport actually has
                // scrollable content. A short gallery fits on phone and tablet,
                // which cannot exercise the required scroll-away/return check.
                ForEach(["Local network approval", "Discovered miners", "Successful additions", "Remaining devices"], id: \.self) { title in
                    FleetSettingsCard {
                        FleetSettingsCardHeader(title: title, subtitle: "Offline layout fixture", symbol: "network")
                        Text("""
                            This panel uses the shared production card and header. Its longer description must remain readable \
                            with natural line wrapping and clear space inside all four rounded edges.
                            """)
                            .fleetFont(.body).fixedSize(horizontal: false, vertical: true)
                        Text("No scan, saved-fleet change, or hardware operation is performed by this visual test.")
                            .fleetFont(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button("Review this change") {}.buttonStyle(FleetPrimaryButtonStyle())
            }
            .padding(16)
        }
        .background(FleetTheme.canvas)
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, viewport.contains("a11y") ? .accessibility3 : .large)
        .transaction { $0.disablesAnimations = true }
        _ = try await FleetViewRenderHarness.render(content, width: width, height: height,
            readiness: { $0.recognizes("Rounded surface spacing", allowingLineWraps: true) },
            inspection: { view in
                @MainActor func capture(_ suffix: String) async throws -> FleetRenderedView {
                    let name = "mounted-\(viewport)-\(suffix)"
                    let result = try await FleetViewRenderHarness.capture(view, named: "\(name).png")
                    try save(try #require(UIImage(data: result.pngData)?.cgImage), named: name)
                    return result
                }
                let first = try await capture("initial")
                #expect(first.recognizes("Live reading", allowingLineWraps: true))
                try await Task.sleep(for: .milliseconds(350))
                let idle = try await capture("idle")
                let firstWord = try #require(first.recognition.words.first { $0.text == "Rounded" })
                let idleWord = try #require(idle.recognition.words.first { $0.text == "Rounded" })
                #expect(abs(firstWord.bounds.minY - idleWord.bounds.minY) <= 2)
                let scroll = try #require(verticalScrollView(in: view))
                let initialOffset = scroll.contentOffset
                for _ in 0..<3 {
                    let bottom = max(-scroll.adjustedContentInset.top,
                                     scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                    view.layoutIfNeeded()
                    await Task.yield()
                }
                let bottom = try await capture("bottom")
                #expect(bottom.recognizes("Review this change", allowingLineWraps: true))
                scroll.setContentOffset(initialOffset, animated: false)
                view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                let returned = try await capture("returned")
                let returnedWord = try #require(returned.recognition.words.first { $0.text == "Rounded" })
                #expect(abs(firstWord.bounds.minY - returnedWord.bounds.minY) <= 2)
                #expect(abs(firstWord.bounds.minX - returnedWord.bounds.minX) <= 2)
            })
    }

    @Test func mountedAccessibleSettingsHeaderDoesNotTruncateItsCopy() async throws {
        let rendered = try await FleetViewRenderHarness.render(
            FleetSettingsCard {
                FleetSettingsCardHeader(title: "Frequency & voltage", subtitle: "Review before applying", symbol: "slider.horizontal.3")
            }
            .padding(16)
            .environment(\.dynamicTypeSize, .accessibility3), width: 320, height: 600)
        #expect(rendered.recognizes("Frequency & voltage", allowingLineWraps: true))
        #expect(rendered.recognizes("Review before applying", allowingLineWraps: true))
        try save(try #require(UIImage(data: rendered.pngData)?.cgImage), named: "mounted-settings-header-a11y")
    }

    private func verticalScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 1 {
            return scroll
        }
        return view.subviews.lazy.compactMap { verticalScrollView(in: $0) }.first
    }
    #endif
}
