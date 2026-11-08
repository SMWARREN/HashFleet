import Foundation
import SwiftUI
import Charts
import Testing
import HashFleetCore
#if os(macOS)
import AppKit
@testable import HashFleetMac
#else
import UIKit
@testable import HashFleet
#endif

#if !os(macOS)
private final class NonKeyTestWindow: UIWindow {
    override var canBecomeKey: Bool { false }
}

private final class TrackingHostingController<Content: View>: UIHostingController<Content> {
    private(set) var didAppear = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppear = true
    }
}
#else
private final class NonKeyNSWindow: NSWindow {
    override var canBecomeKey: Bool { false }
}
#endif

/// Tests real Swift Charts update churn on a single persistent mounted host window.
/// Replaces rootView on the same host through consecutive step updates, verifying that
/// AttributeGraph layout, scale updates, mark generation, and real pixel rasterization complete without crash.
@Suite("Fleet chart churn and stability", .serialized)
@MainActor
struct FleetChartChurnTests {
    private let baseDate = Date(timeIntervalSince1970: 1_794_088_980)

    private func makeCard(devices: [MinerDevice], snapshots: [UUID: MinerSnapshot] = [:]) -> FleetHistoryCard {
        FleetHistoryCard(
            devices: devices,
            snapshots: snapshots,
            isDemo: true,
            initialDisplay: .fleet,
            initialRecentRange: .hour,
            database: nil,
            isMinerDetail: false,
            isCompactDashboard: false
        )
    }

    /// Persistent test host that mounts in a non-key window and receives consecutive root view updates,
    /// exercising actual graph updates on the same mounted host rather than cold reconstruction.
    @MainActor
    private final class PersistentChartHost {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 64)
        #if os(macOS)
        let window: NonKeyNSWindow
        let hostView: NSHostingView<AnyView>

        init() {
            let initial = AnyView(EmptyView())
            hostView = NSHostingView(rootView: initial)
            hostView.frame = NSRect(x: 0, y: 0, width: 320, height: 64)
            window = NonKeyNSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostView
        }

        func awaitAppearance() async {
            hostView.needsLayout = true
            hostView.layoutSubtreeIfNeeded()
            await Task.yield()
        }

        func update<V: View>(_ view: V, requireContent: Bool) async -> (rendered: Bool, pixelVariation: Int) {
            hostView.rootView = AnyView(view)
            await Task.yield()
            hostView.needsLayout = true
            hostView.layoutSubtreeIfNeeded()
            await Task.yield()
            let size = hostView.fittingSize

            guard let rep = hostView.bitmapImageRepForCachingDisplay(in: NSRect(origin: .zero, size: size)) else {
                return (hostView.window != nil && size.width > 0, 0)
            }
            hostView.cacheDisplay(in: NSRect(origin: .zero, size: size), to: rep)
            guard let cgImage = rep.cgImage else {
                return (hostView.window != nil && size.width > 0, 0)
            }
            let variation = sampleVariation(in: cgImage)
            let isRendered = hostView.window != nil && size.width > 0
            if requireContent {
                return (isRendered && variation > 1, variation)
            } else {
                return (isRendered, variation)
            }
        }

        func teardown() {
            window.contentView = nil
            window.close()
        }
        #else
        let scene: UIWindowScene
        let originalKeyWindow: UIWindow?
        let window: NonKeyTestWindow
        let controller: TrackingHostingController<AnyView>

        init() throws {
            let rawScene = try #require(UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first)
            self.scene = rawScene
            self.originalKeyWindow = rawScene.keyWindow

            let initial = AnyView(EmptyView())
            controller = TrackingHostingController(rootView: initial)
            controller.overrideUserInterfaceStyle = .dark
            let bounds = CGRect(x: 0, y: 0, width: 320, height: 64)
            window = NonKeyTestWindow(windowScene: rawScene)
            window.frame = bounds
            window.windowLevel = .normal + 1
            window.rootViewController = controller
            window.isHidden = false
            controller.loadViewIfNeeded()
            controller.view.frame = bounds
        }

        func awaitAppearance() async throws {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            for _ in 0..<50 where !controller.didAppear {
                try await Task.sleep(for: .milliseconds(10))
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
            }
            try #require(controller.didAppear, "UIKit host view must finish actual appearance transition")
        }

        func update<V: View>(_ view: V, requireContent: Bool) async throws -> (rendered: Bool, pixelVariation: Int) {
            controller.rootView = AnyView(view)
            await Task.yield()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            await Task.yield()

            let format = UIGraphicsImageRendererFormat()
            format.scale = controller.view.traitCollection.displayScale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
            let image = renderer.image { context in
                controller.view.layer.render(in: context.cgContext)
            }

            guard let cgImage = image.cgImage else {
                return (false, 0)
            }
            let variation = sampleVariation(in: cgImage)
            let isRendered = controller.view.window != nil && controller.isViewLoaded
            if requireContent {
                return (isRendered && variation > 1, variation)
            } else {
                return (isRendered, variation)
            }
        }

        func teardown() {
            #expect(scene.keyWindow === originalKeyWindow, "Original key window must remain unchanged")
            window.isHidden = true
            window.rootViewController = nil
        }
        #endif

        private func sampleVariation(in image: CGImage) -> Int {
            let sampleW = 40
            let sampleH = 20
            var pixels = [UInt8](repeating: 0, count: sampleW * sampleH * 4)
            return pixels.withUnsafeMutableBytes { bytes -> Int in
                guard let ctx = CGContext(
                    data: bytes.baseAddress,
                    width: sampleW,
                    height: sampleH,
                    bitsPerComponent: 8,
                    bytesPerRow: sampleW * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return 0 }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))
                var distinct = Set<UInt32>()
                let buffer = bytes.bindMemory(to: UInt32.self)
                for i in 0..<(sampleW * sampleH) {
                    distinct.insert(buffer[i])
                    if distinct.count > 10 { break }
                }
                return distinct.count
            }
        }
    }

    @Test func actualChartRampsFromEmptyToSingleAndMultiPoints() async throws {
        let deviceID = UUID()
        let device = MinerDevice(id: deviceID, name: "Rig 1", address: "192.168.1.100")
        let card = makeCard(devices: [device])
        #if os(macOS)
        let host = PersistentChartHost()
        defer { host.teardown() }
        await host.awaitAppearance()
        #else
        let host = try PersistentChartHost()
        defer { host.teardown() }
        try await host.awaitAppearance()
        #endif

        var renderedIterations = 0
        for count in 0...20 {
            let points = (0..<count).map {
                HashratePoint(
                    date: baseDate.addingTimeInterval(Double($0) * 10),
                    value: 800.0 + Double($0 * 25)
                )
            }
            let series = MinerHistorySeries(id: deviceID, name: device.name, points: points)
            let segments = FleetHistoryPresentation.segments(points)

            let selection: FleetChartSelection?
            if let first = points.first {
                selection = FleetChartSelection.resolve(at: first.date, in: [series], tolerance: 1800)
            } else {
                selection = nil
            }

            let chartView = card.historyChart([series], window: .daily, selection: selection, segments: segments)
            #if os(macOS)
            let result = await host.update(chartView, requireContent: count > 0)
            #else
            let result = try await host.update(chartView, requireContent: count > 0)
            #endif
            #expect(result.rendered, "Persistent host must render chart pass at count \(count)")
            if count > 0 {
                #expect(result.pixelVariation > 1, "Rendered chart must have non-uniform pixels at count \(count)")
            }

            renderedIterations += 1
            await Task.yield()
        }

        #expect(renderedIterations == 21)
    }

    @Test func actualChartOscillatesAcrossUnitThresholdWithActiveSelection() async throws {
        let deviceID = UUID()
        let device = MinerDevice(id: deviceID, name: "Antminer", address: "192.168.1.101")
        let card = makeCard(devices: [device])
        #if os(macOS)
        let host = PersistentChartHost()
        defer { host.teardown() }
        await host.awaitAppearance()
        #else
        let host = try PersistentChartHost()
        defer { host.teardown() }
        try await host.awaitAppearance()
        #endif

        var renderedIterations = 0
        // Rapid oscillation across the 1,000 GH/s boundary (995 GH/s vs 1005 GH/s = 1.005 TH/s)
        for step in 0..<50 {
            let rate = (step % 2 == 0) ? 995.0 : 1005.0
            let pt = HashratePoint(date: baseDate.addingTimeInterval(Double(step) * 5), value: rate)
            let isSingle = (step % 3 == 0)
            let points = isSingle ? [pt] : [pt, HashratePoint(date: pt.date.addingTimeInterval(5), value: rate * 1.02)]
            let series = MinerHistorySeries(id: deviceID, name: device.name, points: points)
            let segments = FleetHistoryPresentation.segments(points)

            let selection = FleetChartSelection.resolve(at: pt.date, in: [series], tolerance: 1800)
            let chartView = card.historyChart([series], window: .daily, selection: selection, segments: segments)

            #if os(macOS)
            let result = await host.update(chartView, requireContent: true)
            #else
            let result = try await host.update(chartView, requireContent: true)
            #endif
            #expect(result.rendered, "Persistent host must rasterize oscillation step \(step)")
            #expect(result.pixelVariation > 1, "Oscillation step must produce non-uniform pixels at step \(step)")

            renderedIterations += 1
            if step % 10 == 0 { await Task.yield() }
        }

        #expect(renderedIterations == 50)
    }

    @Test func actualChartRendersTwentyMinersWithDuplicateDisplayNames() async throws {
        // Valid distinct UUIDs but intentionally duplicate display names
        let devices = (1...20).map { idx in
            MinerDevice(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", idx))!,
                name: "Miner \(idx % 4)", // 4 names shared among 20 miners
                address: "192.168.1.\(100 + idx)"
            )
        }
        let card = makeCard(devices: devices)
        #if os(macOS)
        let host = PersistentChartHost()
        defer { host.teardown() }
        await host.awaitAppearance()
        #else
        let host = try PersistentChartHost()
        defer { host.teardown() }
        try await host.awaitAppearance()
        #endif

        var renderedIterations = 0
        for step in 0..<20 {
            let seriesList = devices.enumerated().map { dIdx, dev in
                let pts = (0..<5).map { p in
                    HashratePoint(
                        date: baseDate.addingTimeInterval(Double(step * 10 + p * 2)),
                        value: 500.0 + Double(dIdx * 50 + p * 10)
                    )
                }
                return MinerHistorySeries(id: dev.id, name: dev.name, points: pts)
            }

            let selDate = baseDate.addingTimeInterval(Double(step * 10))
            let selection = FleetChartSelection.resolve(at: selDate, in: seriesList, tolerance: 1800)
            let chartView = card.historyChart(seriesList, window: .daily, selection: selection, segments: nil)

            #if os(macOS)
            let result = await host.update(chartView, requireContent: true)
            #else
            let result = try await host.update(chartView, requireContent: true)
            #endif
            #expect(result.rendered, "Persistent host must rasterize 20-miner step \(step)")
            #expect(result.pixelVariation > 1, "20-miner step must produce non-uniform pixels at step \(step)")

            renderedIterations += 1
            await Task.yield()
        }

        #expect(renderedIterations == 20)
    }

    @Test func actualChartSimulatedSelectionResolverChurn() async throws {
        let deviceID = UUID()
        let device = MinerDevice(id: deviceID, name: "Interactive Rig", address: "192.168.1.200")
        let card = makeCard(devices: [device])
        #if os(macOS)
        let host = PersistentChartHost()
        defer { host.teardown() }
        await host.awaitAppearance()
        #else
        let host = try PersistentChartHost()
        defer { host.teardown() }
        try await host.awaitAppearance()
        #endif

        let points = (0..<30).map {
            HashratePoint(
                date: baseDate.addingTimeInterval(Double($0) * 10),
                value: 1200.0 + sin(Double($0)) * 200.0
            )
        }
        let series = MinerHistorySeries(id: deviceID, name: device.name, points: points)
        let segments = FleetHistoryPresentation.segments(points)

        var renderedIterations = 0
        // Simulated selection resolver churn across discrete sample points and out-of-tolerance bounds
        for idx in 0..<35 {
            let scrubTarget = baseDate.addingTimeInterval(Double(idx) * 9.5)
            let selection = FleetChartSelection.resolve(at: scrubTarget, in: [series], tolerance: 1800)
            let chartView = card.historyChart([series], window: .daily, selection: selection, segments: segments)

            #if os(macOS)
            let result = await host.update(chartView, requireContent: true)
            #else
            let result = try await host.update(chartView, requireContent: true)
            #endif
            #expect(result.rendered, "Persistent host must rasterize simulated selection step \(idx)")
            #expect(result.pixelVariation > 1, "Selection step must produce non-uniform pixels at step \(idx)")

            renderedIterations += 1
            if idx % 10 == 0 { await Task.yield() }
        }

        #expect(renderedIterations == 35)
    }
}
