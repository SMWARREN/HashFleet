import Foundation
import SwiftUI
import Charts
import Testing
import Observation
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

/// Observable data feed providing snapshot updates to a mounted FleetHistoryCard.
/// Drives the card natively through its installed SwiftUI State and Environment,
/// evaluating actual page data aggregation and chart rendering without helper-off-unmounted-card warnings.
@Observable @MainActor
final class MountedFleetHistoryFeed {
    var devices: [MinerDevice] = []
    var snapshots: [UUID: MinerSnapshot] = [:]
}

/// Real container view that mounts FleetHistoryCard directly in an installed view hierarchy.
struct MountedFleetHistoryContainer: View {
    let feed: MountedFleetHistoryFeed

    var body: some View {
        FleetHistoryCard(
            devices: feed.devices,
            snapshots: feed.snapshots,
            isDemo: true,
            initialDisplay: .fleet,
            initialRecentRange: .hour,
            database: nil,
            isMinerDetail: false,
            isCompactDashboard: false
        )
        .frame(width: 360)
    }
}

/// End-to-end mounted card churn test verifying real AttributeGraph execution under 20-device telemetry.
/// Replaces cold reconstruction with continuous state mutation on a single persistent non-key host window.
@Suite("Mounted FleetHistoryCard Churn", .serialized)
@MainActor
struct FleetHistoryMountedChurnTests {

    @MainActor
    private final class MountedCardTestHost {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 240)
        #if os(macOS)
        let window: NonKeyNSWindow
        let hostView: NSHostingView<MountedFleetHistoryContainer>

        init(feed: MountedFleetHistoryFeed) {
            let root = MountedFleetHistoryContainer(feed: feed)
            hostView = NSHostingView(rootView: root)
            hostView.frame = NSRect(x: 0, y: 0, width: 360, height: 240)
            window = NonKeyNSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
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

        func step(requireContent: Bool) async -> (rendered: Bool, pixelVariation: Int, digest: UInt64) {
            await Task.yield()
            hostView.needsLayout = true
            hostView.layoutSubtreeIfNeeded()
            await Task.yield()

            let size = hostView.fittingSize
            guard let rep = hostView.bitmapImageRepForCachingDisplay(in: NSRect(origin: .zero, size: size)) else {
                return (hostView.window != nil && size.width > 0, 0, 0)
            }
            hostView.cacheDisplay(in: NSRect(origin: .zero, size: size), to: rep)
            guard let cgImage = rep.cgImage else {
                return (hostView.window != nil && size.width > 0, 0, 0)
            }
            let (variation, digest) = sampleVariationAndDigest(in: cgImage)
            let isRendered = hostView.window != nil && size.width > 0
            if requireContent {
                return (isRendered && variation > 1, variation, digest)
            } else {
                return (isRendered, variation, digest)
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
        let controller: TrackingHostingController<MountedFleetHistoryContainer>

        init(feed: MountedFleetHistoryFeed) throws {
            let rawScene = try #require(UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first)
            self.scene = rawScene
            self.originalKeyWindow = rawScene.keyWindow

            let root = MountedFleetHistoryContainer(feed: feed)
            controller = TrackingHostingController(rootView: root)
            controller.overrideUserInterfaceStyle = .dark
            let bounds = CGRect(x: 0, y: 0, width: 360, height: 240)
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

        func step(requireContent: Bool) async throws -> (rendered: Bool, pixelVariation: Int, digest: UInt64) {
            await Task.yield()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            await Task.yield()

            let format = UIGraphicsImageRendererFormat()
            format.scale = controller.view.traitCollection.displayScale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
            // Request the committed UIKit hierarchy, not a CALayer snapshot that
            // can precede SwiftUI/Charts screen updates. The previous layer-render
            // run remains preserved as a failed raster-change observation.
            var hierarchyDrawSucceeded = false
            let image = renderer.image { _ in
                hierarchyDrawSucceeded = controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
            }

            guard let cgImage = image.cgImage else {
                return (false, 0, 0)
            }
            let (variation, digest) = sampleVariationAndDigest(in: cgImage)
            let isRendered = hierarchyDrawSucceeded && controller.view.window != nil && controller.isViewLoaded
            if requireContent {
                return (isRendered && variation > 1, variation, digest)
            } else {
                return (isRendered, variation, digest)
            }
        }

        func teardown() {
            #expect(scene.keyWindow === originalKeyWindow, "Original key window must remain unchanged")
            window.isHidden = true
            window.rootViewController = nil
        }
        #endif

        private func sampleVariationAndDigest(in image: CGImage) -> (Int, UInt64) {
            let sampleW = 40
            let sampleH = 20
            var pixels = [UInt8](repeating: 0, count: sampleW * sampleH * 4)
            return pixels.withUnsafeMutableBytes { bytes -> (Int, UInt64) in
                guard let ctx = CGContext(
                    data: bytes.baseAddress,
                    width: sampleW,
                    height: sampleH,
                    bitsPerComponent: 8,
                    bytesPerRow: sampleW * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return (0, 0) }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))

                var distinct = Set<UInt32>()
                let buffer = bytes.bindMemory(to: UInt32.self)
                for i in 0..<(sampleW * sampleH) {
                    distinct.insert(buffer[i])
                    if distinct.count > 10 { break }
                }

                // 64-bit FNV-1a digest over sampled raster pixels to detect visual updates
                var hash: UInt64 = 14695981039346656037
                let rawBytes = bytes.bindMemory(to: UInt8.self)
                for i in 0..<(sampleW * sampleH * 4) {
                    hash ^= UInt64(rawBytes[i])
                    hash = hash &* 1099511628211
                }
                return (distinct.count, hash)
            }
        }
    }

    /// Shared execution harness driving continuous mounted card updates.
    /// Replaces cold reconstruction with continuous state mutation on a single persistent non-key host window.
    private static func runMountedChurn(
        totalSteps: Int,
        timeBudget: TimeInterval,
        minUnitFlips: Int,
        minDigestChanges: Int,
        progressInterval: Int
    ) async throws {
        let feed = MountedFleetHistoryFeed()

        // 20 devices with valid distinct UUIDs, intentionally repeating 4 display names
        let devices = (1...20).map { idx in
            MinerDevice(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", idx))!,
                name: "Miner \(idx % 4)",
                address: "192.168.1.\(100 + idx)"
            )
        }
        feed.devices = devices

        #if os(macOS)
        let host = MountedCardTestHost(feed: feed)
        defer { host.teardown() }
        await host.awaitAppearance()
        #else
        let host = try MountedCardTestHost(feed: feed)
        defer { host.teardown() }
        try await host.awaitAppearance()
        #endif

        let startedAt = Date()
        var renderReceiptCount = 0
        var digestChangeCount = 0
        var unitStateChanges = 0
        var previousDigest: UInt64 = 0
        var previousUnit: HashrateUnit?
        var totalPointsGenerated = 0
        var inputChecksum: UInt64 = 20261107

        // Each sample uses its actual observation time. Advancing synthetic time by
        // step * 10 would put the long stress run in the future and bypass the chart.
        let windowCapacity = 5

        var snapshots: [UUID: MinerSnapshot] = [:]
        for dev in devices {
            snapshots[dev.id] = MinerSnapshot()
        }

        for step in 0..<totalSteps {
            let pointTimestamp = Date()

            // 5-point sliding window with alternating 6-step low/high burst pattern:
            // Low phase (steps 0..5, 12..17, etc.): 20.0 GH/s per device -> 20 * 20 = 400 GH/s aggregate (GH/s unit)
            // High phase (steps 6..11, 18..23, etc.): 60.0 GH/s per device -> 20 * 60 = 1,200 GH/s aggregate (TH/s unit)
            // As points roll through the 5-point buffer, the aggregate max transitions repeatedly across 1000 GH/s
            let isHighPhase = ((step / 6) % 2 == 1)
            let perDeviceRate = isHighPhase ? 60.0 : 20.0

            for dev in devices {
                inputChecksum = (inputChecksum &* 31) &+ UInt64(perDeviceRate.bitPattern)
                var snap = snapshots[dev.id] ?? MinerSnapshot()
                snap.history.append(HashratePoint(date: pointTimestamp, value: perDeviceRate))
                if snap.history.count > windowCapacity {
                    snap.history = Array(snap.history.suffix(windowCapacity))
                }
                snapshots[dev.id] = snap
                totalPointsGenerated += 1
            }

            // Compute expected aggregate historical max using production aggregation logic
            let activeSeries = devices.compactMap { dev -> MinerHistorySeries? in
                guard let pts = snapshots[dev.id]?.history, !pts.isEmpty else { return nil }
                return MinerHistorySeries(id: dev.id, name: dev.name, points: pts)
            }
            let segments = FleetHistoryAggregation.segments(histories: activeSeries, expectedIDs: devices.map(\.id))
            let aggregateValues = segments.flatMap(\.points).map(\.value)
            let aggregateMax = aggregateValues.max() ?? 0
            let currentUnit = FleetFormat.hashrateDisplayUnit(forGHs: aggregateMax)

            if let prev = previousUnit, currentUnit != prev {
                unitStateChanges += 1
            }
            previousUnit = currentUnit

            // Update feed model to trigger native SwiftUI body invalidation on installed card
            feed.snapshots = snapshots

            #if os(macOS)
            let result = await host.step(requireContent: step >= windowCapacity)
            #else
            let result = try await host.step(requireContent: step >= windowCapacity)
            #endif

            #expect(result.rendered, "Mounted card must layout and render at step \(step)")
            if step >= windowCapacity {
                #expect(result.pixelVariation > 1, "Rendered mounted card must produce non-uniform pixels at step \(step)")
                if result.digest != previousDigest {
                    digestChangeCount += 1
                }
                previousDigest = result.digest
            }

            renderReceiptCount += 1
            if step % 15 == 0 { await Task.yield() }

            if progressInterval > 0, step > 0, step % progressInterval == 0 {
                let currentElapsed = Date().timeIntervalSince(startedAt)
                print("Mounted churn checkpoint [step \(step)/\(totalSteps)]: renderCount=\(renderReceiptCount), digestChanges=\(digestChangeCount), unitFlips=\(unitStateChanges), elapsed=\(currentElapsed)s")
            }
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        print("Final mounted churn receipts [\(totalSteps) steps]: renderCount=\(renderReceiptCount), digestChanges=\(digestChangeCount), unitFlips=\(unitStateChanges), generatedPoints=\(totalPointsGenerated), elapsed=\(elapsed)s")

        #expect(renderReceiptCount == totalSteps, "Must complete all \(totalSteps) mounted card updates")
        #expect(unitStateChanges >= minUnitFlips, "Must observe at least \(minUnitFlips) real alternating unit transitions (observed \(unitStateChanges))")
        #expect(digestChangeCount >= minDigestChanges, "Rendered pixel digest must change on data updates (observed \(digestChangeCount) changes)")
        #expect(totalPointsGenerated >= totalSteps * 20, "Total generated points count must match input workload")
        #expect(elapsed < timeBudget, "\(totalSteps) mounted card churn updates must complete in under \(timeBudget)s (took \(elapsed)s)")
        #expect(inputChecksum != 0, "Input checksum must be non-zero")
    }

    /// Baseline 120-step continuous churn test (completes in under 30s).
    @Test func mountedFleetHistoryCardTwentyDeviceContinuousChurn() async throws {
        try await Self.runMountedChurn(
            totalSteps: 120,
            timeBudget: 30.0,
            minUnitFlips: 8,
            minDigestChanges: 80,
            progressInterval: 60
        )
    }

    /// Aggressive 2,400-step continuous churn stress test (completes in under 90s).
    @Test func mountedFleetHistoryCardAggressiveTwentyFourHundredUpdatesChurn() async throws {
        try await Self.runMountedChurn(
            totalSteps: 2400,
            timeBudget: 90.0,
            minUnitFlips: 200,
            minDigestChanges: 1600,
            progressInterval: 300
        )
    }
}
