import AppKit
import SwiftUI
import Testing
@testable import HashFleetMac

@Suite("Native status item branding")
struct FleetNativeBrandingTests {
    @Test func statusItemOmitsNameWithoutDiscardingDemoOrStaleState() {
        for compact in ["4/4 22.00 TH/s", "DEMO 3/3 3.02 TH/s", "DEMO 3/3 3.02 TH/s !", "0/0 Not reported"] {
            #expect(FleetMacChrome.statusTitle(compactTitle: compact) == compact)
        }
    }

    @MainActor
    @Test func toolbarBrandIsTheStandaloneSharedIPadTitleIndependentlyOfSidebarState() throws {
        let image = try #require(ImageRenderer(content: FleetMacToolbarBrand()).nsImage)
        let reference = try #require(ImageRenderer(content:
            FleetHeaderTitle().frame(minHeight: 44).fixedSize(horizontal: true, vertical: false)
        ).nsImage)
        #expect(image.size == reference.size)
        #expect(image.size.height == FleetMacChrome.targetSize)
    }

    @MainActor
    @Test func centeredWordmarkRetainsOriginalHeadlineWhileDesktopArtworkFillsItsTarget() throws {
        let actual = try #require(ImageRenderer(content: FleetMacToolbarBrand()).nsImage)
        let reference = try #require(ImageRenderer(content:
            Text("Hash Fleet").fleetFont(.headline).lineLimit(1)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(minHeight: 44)
            .fixedSize(horizontal: true, vertical: false)
        ).nsImage)
        #expect(actual.size == reference.size)
        let artwork = try #require(ImageRenderer(content: FleetHeaderArtwork()).nsImage)
        #expect(artwork.size == CGSize(width: 44, height: 44))
    }

    @MainActor
    @Test func actualToolbarMenuKeepsItsTargetWithoutAnInnerPlainOverride() {
        let menu = Menu { Button("Settings") {} } label: {
            Image(systemName: "gearshape").font(.system(size: 14, weight: .medium))
        }.fleetToolbarMenu()
        let host = NSHostingView(rootView: menu)
        #expect(host.fittingSize.width >= 44)
        #expect(host.fittingSize.height == 44)
    }

    @MainActor
    @Test func opaqueChromeConfigurationPreservesSystemControlsAndWindowGeometry() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_028, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let frame = window.frame
        let styleMask = window.styleMask
        let close = try #require(window.standardWindowButton(.closeButton))
        let minimize = try #require(window.standardWindowButton(.miniaturizeButton))
        let zoom = try #require(window.standardWindowButton(.zoomButton))
        for _ in 0..<3 { FleetMacChrome.configure(window) }
        #expect(window.frame == frame)
        #expect(window.styleMask == styleMask)
        #expect(window.standardWindowButton(.closeButton) === close)
        #expect(window.standardWindowButton(.miniaturizeButton) === minimize)
        #expect(window.standardWindowButton(.zoomButton) === zoom)
        #expect(window.toolbarStyle == .unified)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titlebarSeparatorStyle == .none)
        #expect(!window.isVisible)
        window.close()
    }

    @MainActor
    @Test func statusItemUsesOriginalTransparentPortraitIcon() {
        let source = NSImage(named: NSImage.Name("HashFleetStatusIcon"))
        #expect(source != nil)

        let image = FleetMacStatusItemController.makeStatusImage(height: 22)
        #expect(image != nil)
        guard let source, let image else { return }

        #expect(source.size.width < source.size.height)
        #expect(source.representations.contains {
            ($0 as? NSBitmapImageRep)?.hasAlpha == true
        })
        let expectedWidth = 22 * source.size.width / source.size.height
        #expect(abs(image.size.width - expectedWidth) < 0.001)
        #expect(abs(image.size.height - 22) < 0.001)
        #expect(!image.isTemplate)

        let headerImage = FleetMacStatusItemController.makeStatusImage(height: 36)
        #expect(headerImage != nil)
        guard let headerImage else { return }
        let expectedHeaderWidth = 36 * source.size.width / source.size.height
        #expect(abs(headerImage.size.width - expectedHeaderWidth) < 0.001)
        #expect(abs(headerImage.size.height - 36) < 0.001)
        #expect(!headerImage.isTemplate)
    }
}
