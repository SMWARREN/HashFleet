import Foundation
import SwiftUI
import Testing
import UIKit
import Vision
import ImageIO
import HashFleetCore
@testable import HashFleet

/// Every hosted screen gets a private preferences domain and a session which cannot reach a server.
/// Tests must not call `add`/`persist` on a non-demo store because those mirror the real App Group.
@MainActor
final class FleetRenderFixture {
    let suite: String
    let defaults: UserDefaults
    let session: URLSession
    let store: FleetStore
    let insights: MiningInsightsStore

    init(demo: Bool = true) throws {
        suite = "app.hashfleet.tests.render.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FleetRenderBlockedProtocol.self]
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 1
        session = URLSession(configuration: configuration)
        store = FleetStore(defaults: defaults, session: session)
        insights = MiningInsightsStore(session: session, cooldown: 0)
        if demo { store.loadDemo() }
        store.preferences.externalDataEnabled = false
        store.preferences.realtimeMonitoring = false
        insights.setDemo(demo)
    }

    func cleanup() {
        let probes = store.capabilities.cancelAll()
        store.cancelRefresh()
        insights.cancel()
        let session = session
        Task {
            for probe in probes { _ = await probe.result }
            session.invalidateAndCancel()
        }
        defaults.removePersistentDomain(forName: suite)
    }
}

private final class FleetRenderBlockedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

struct FleetRenderedView: Sendable {
    let pngData: Data
    /// Text recognized from the actual captured pixels, not accessibility labels or expected copy.
    /// This is a visual-copy observation. Native XCUI tests remain responsible for AX semantics.
    let recognition: FleetRecognizedText
    var visibleText: String { recognition.accurate }

    func recognizes(_ text: String, allowingLineWraps: Bool = false) -> Bool {
        recognition.contains(text, allowingLineWraps: allowingLineWraps)
    }
    func recognizesMetric(_ value: String, unit: String) -> Bool {
        recognition.containsMetric(value: value, unit: unit)
    }

    let pixelVariation: Int
    let size: CGSize
    /// Time of the real pixel capture, before potentially expensive Vision analysis.
    let capturedAt: ContinuousClock.Instant
}

struct FleetRenderReadinessWindow {
    let deadline: ContinuousClock.Instant

    init(startedAt: ContinuousClock.Instant) {
        deadline = startedAt.advanced(by: .seconds(3))
    }

    func isExhausted(by capturedAt: ContinuousClock.Instant) -> Bool {
        capturedAt >= deadline
    }
}

private enum FleetRenderReadinessError: Error, Equatable {
    case timedOut
}

struct FleetOCRStrip: Sendable {
    let crop: CGRect
    let coreX: Range<Int>
    let core: Range<Int>
}

nonisolated func recognitionStrips(width: Int, height: Int) -> [FleetOCRStrip] {
    stride(from: 0, to: height, by: 1_536).flatMap { coreTop in
        let coreBottom = min(height, coreTop + 1_536)
        let top = max(0, coreTop - 192)
        let bottom = min(height, coreBottom + 192)
        return stride(from: 0, to: width, by: 1_536).map { coreLeft in
            let coreRight = min(width, coreLeft + 1_536)
            let left = max(0, coreLeft - 256)
            let right = min(width, coreRight + 256)
            return FleetOCRStrip(
                crop: CGRect(x: left, y: top, width: right - left, height: bottom - top),
                coreX: coreLeft..<coreRight,
                core: coreTop..<coreBottom)
        }
    }
}

/// Mounts actual SwiftUI content, waits for appearance, and captures real pixels.
/// Public UIKit containers do not guarantee enumeration of SwiftUI's virtual AX descendants.
/// Visual copy is therefore observed with on-device Vision. No expected words are fed to Vision.
/// This does not establish accessibility, touch, permission, extension, or hardware behavior.
@MainActor
enum FleetViewRenderHarness {
    private static var busy = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    private static func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private static func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    static func render<Content: View>(
        _ content: Content,
        width: CGFloat = 390,
        height: CGFloat = 844,
        readiness: ((FleetRenderedView) -> Bool)? = nil,
        inspection: (@MainActor (UIView) async throws -> Void)? = nil
    ) async throws -> FleetRenderedView {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        try #require(width > 0 && height > 0 && width <= 4_096 && height <= 8_192 && width * height <= 8_000_000)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalKeyWindow = scene.keyWindow
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let window = FleetRenderWindow(windowScene: scene)
        window.frame = bounds
        window.windowLevel = .normal + 1
        let host = FleetRenderHostingController(rootView: content.environment(\.locale, Locale(identifier: "en_US")))
        host.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.loadViewIfNeeded()
        host.view.frame = bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        await Task.yield()
        await Task.yield()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        for _ in 0..<50 where !host.didAppear {
            try await Task.sleep(for: .milliseconds(20))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        try #require(host.didAppear, "UIKit must finish the actual appearance transition before capture")
        let readinessWindow = FleetRenderReadinessWindow(startedAt: .now)
        var captured = try await observation(in: host.view, bounds: bounds)
        // The predicate observes captured pixels only. It is never passed to Vision and
        // cannot invent, correct, or substitute text. An unmet predicate remains an error.
        while let readiness, !readiness(captured) {
            // OCR can finish after the deadline while describing an early frame.
            // Before failing, require an actual unmet capture at or beyond the
            // unchanged three-second window, not a stale entrance-animation PNG.
            if readinessWindow.isExhausted(by: captured.capturedAt) {
                Attachment.record(captured.pngData, named: "readiness-timeout.png")
                throw FleetRenderReadinessError.timedOut
            }
            try await Task.sleep(for: .milliseconds(20))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            captured = try await observation(in: host.view, bounds: bounds)
        }
        if let inspection {
            try await inspection(host.view)
            captured = try await observation(in: host.view, bounds: bounds)
        }
        Attachment.record(captured.pngData, named: "mounted-view-\(UUID().uuidString).png")
        #expect(window.rootViewController === host)
        #expect(host.view.window === window)
        #expect(!window.isKeyWindow)
        #expect(scene.keyWindow === originalKeyWindow, "Rendering must not change the original key window")
        return captured
    }

    /// Additional real captures from the same mounted view, not fresh renders.
    /// This lets scrolling and time-series checks observe lazy rows and movement.
    static func capture(_ view: UIView, named name: String) async throws -> FleetRenderedView {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let result = try await observation(in: view, bounds: view.bounds, presented: true)
        Attachment.record(result.pngData, named: name)
        return result
    }

    private static func observation(in view: UIView, bounds: CGRect, presented: Bool = false) async throws -> FleetRenderedView {
        let (image, variation) = try await drawnImage(in: view, bounds: bounds, presented: presented)
        let capturedAt = ContinuousClock.now
        let data = try #require(image.pngData())
        let recognition = try await Task.detached(priority: .userInitiated) {
            try FleetTextRecognition.recognize(data)
        }.value
        return FleetRenderedView(pngData: data, recognition: recognition,
                                 pixelVariation: variation, size: image.size, capturedAt: capturedAt)
    }

    private static func drawnImage(in view: UIView, bounds: CGRect, presented: Bool = false) async throws -> (UIImage, Int) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = view.traitCollection.displayScale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        func capture() throws -> (UIImage, Int) {
            var drewHierarchy = true
            let image = renderer.image { context in
                if presented {
                    // Unlike a model-layer render, this includes the presented
                    // hierarchy used by the same mounted, scrolling UIWindow.
                    drewHierarchy = view.drawHierarchy(in: bounds, afterScreenUpdates: true)
                } else {
                    view.layer.render(in: context.cgContext)
                }
            }
            try #require(drewHierarchy, "The presented hierarchy must really draw the screenshot")
            return (image, sampledColors(in: try #require(image.cgImage)))
        }
        var result = try capture()
        // Entrance animations may initially draw a uniform canvas. Poll observed pixels.
        for _ in 0..<100 where result.1 <= 1 {
            try await Task.sleep(for: .milliseconds(20))
            view.setNeedsLayout()
            view.layoutIfNeeded()
            result = try capture()
        }
        try #require(result.1 > 1, "The mounted production view must draw content, not a uniform canvas")
        return result
    }

    private static func sampledColors(in image: CGImage) -> Int {
        let sampleWidth = 80
        let sampleHeight = 160
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        return pixels.withUnsafeMutableBytes { bytes -> Int in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: sampleWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return 0 }
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
            let data = bytes.bindMemory(to: UInt8.self)
            var colors: Set<UInt32> = []
            for offset in stride(from: 0, to: data.count, by: 4) {
                colors.insert(UInt32(data[offset]) << 16 | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]))
            }
            return colors.count
        }
    }
}

@MainActor
/// UIKit must not automatically promote a long-lived screenshot window when its
/// scene activates. Captures are observers and must never take key-window focus.
private final class FleetRenderWindow: UIWindow {
    override var canBecomeKey: Bool { false }
}

private final class FleetRenderHostingController<Content: View>: UIHostingController<Content> {
    private(set) var didAppear = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppear = true
    }
}

@Suite(.serialized)
@MainActor
struct FleetViewRenderHarnessTests {
    @Test func realPixelsAndRecognizedCopyReflectChangedSwiftUIText() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalKeyWindow = scene.keyWindow
        let first = try await FleetViewRenderHarness.render(
            VStack {
                Text("Read-only fleet")
                Text("525 MHz")
            }.padding().background(Color.black))
        let second = try await FleetViewRenderHarness.render(
            VStack {
                Text("Read-only fleet")
                Text("675 MHz")
            }.padding().background(Color.black))
        #expect(first.size == CGSize(width: 390, height: 844))
        #expect(first.pixelVariation > 1)
        #expect(first.pngData != second.pngData, "Changed telemetry must change the actual rendered pixels")
        #expect(first.visibleText.contains("525 MHz"))
        #expect(second.visibleText.contains("675 MHz"))
        #expect(!second.visibleText.contains("525 MHz"))
        #expect(scene.keyWindow === originalKeyWindow)
    }

    @Test func concurrentRendersKeepTheirOwnActualPixelsAndCopy() async throws {
        let values = [525, 675, 800]
        let captures = try await withThrowingTaskGroup(of: (Int, FleetRenderedView).self) { group in
            for value in values {
                group.addTask { (value, try await Self.renderClock(value)) }
            }
            var results: [(Int, FleetRenderedView)] = []
            for try await capture in group { results.append(capture) }
            return results
        }
        #expect(captures.count == values.count)
        for (value, rendered) in captures {
            #expect(rendered.recognizes("Fixture clock \(value) MHz"))
            for other in values where other != value {
                #expect(!rendered.recognizes("Fixture clock \(other) MHz"))
            }
        }
        #expect(Set(captures.map { $0.1.pngData }).count == values.count)
    }

    private static func renderClock(_ value: Int) async throws -> FleetRenderedView {
        try await FleetViewRenderHarness.render(Text("Fixture clock \(value) MHz").padding().background(Color.black))
    }

    @Test func visibleCopyDoesNotInventMetadataOrHiddenValues() async throws {
        let rendered = try await FleetViewRenderHarness.render(
            VStack {
                Text("Actual visible fixture 525 MHz")
                    .accessibilityLabel("Metadata-only replacement 999 MHz")
                Text("Hidden fixture 675 MHz").hidden()
            }.padding().background(Color.black))
        #expect(rendered.visibleText.contains("Actual visible fixture 525 MHz"))
        #expect(!rendered.visibleText.contains("999 MHz"))
        #expect(!rendered.visibleText.contains("675 MHz"))
    }

    @Test func tallCapturesRetainTopBoundaryBottomAndRepeatedVisibleCopy() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let scale = scene.traitCollection.displayScale
        let height = max(2_700, ceil(8_000 / scale))
        // Exercise the same physical strip boundary and >7,000-pixel capture at 2x or 3x.
        let boundaryY = (1_536 - 12) / scale
        let first = try await FleetViewRenderHarness.render(
            longFixture(525, height: height, boundaryY: boundaryY), height: height)
        let second = try await FleetViewRenderHarness.render(
            longFixture(675, height: height, boundaryY: boundaryY), height: height)
        let firstImage = try #require(UIImage(data: first.pngData)?.cgImage)
        #expect(firstImage.height > 7_000)
        #expect(first.pngData != second.pngData)
        for (value, capture) in [(525, first), (675, second)] {
            #expect(capture.visibleText.contains("Tall fixture \(value) MHz"))
            #expect(capture.visibleText.contains("Across strip boundary"))
            #expect(capture.visibleText.components(separatedBy: "Across strip boundary").count - 1 == 1)
            #expect(capture.visibleText.contains("Bottom fixture \(value) MHz"))
            #expect(capture.visibleText.components(separatedBy: "Repeated visible row").count - 1 == 2)
            #expect(!capture.visibleText.contains("Metadata replacement"))
            #expect(!capture.visibleText.contains("Hidden long fixture"))
        }
        #expect(!second.visibleText.contains("525 MHz"))
        #expect(!first.visibleText.contains("675 MHz"))
    }

    private func longFixture(_ value: Int, height: CGFloat, boundaryY: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black
            Text("Tall fixture \(value) MHz").offset(x: 20, y: 32)
                .accessibilityLabel("Metadata replacement")
            Text("Repeated visible row").offset(x: 20, y: 168)
            Text("Across strip boundary").offset(x: 20, y: boundaryY)
            Text("Repeated visible row").offset(x: 20, y: height - 300)
            Text("Bottom fixture \(value) MHz").offset(x: 20, y: height - 100)
            Text("Hidden long fixture").hidden()
        }
        .font(.system(size: 22))
        .foregroundStyle(.white)
        .frame(width: 390, height: height, alignment: .topLeading)
    }

    @Test(arguments: [1, 1_535, 1_536, 1_537, 7_200, 23_400])
    func recognitionStripsCoverEveryPixelWithoutCoreOverlap(_ height: Int) {
        let strips = recognitionStrips(width: 1_170, height: height)
        #expect(strips.first?.core.lowerBound == 0)
        #expect(strips.last?.core.upperBound == height)
        for (index, strip) in strips.enumerated() {
            #expect(strip.crop.minX == 0 && strip.crop.width == 1_170)
            #expect(strip.crop.minY >= 0 && strip.crop.maxY <= CGFloat(height))
            #expect(strip.crop.minY <= CGFloat(strip.core.lowerBound))
            #expect(strip.crop.maxY >= CGFloat(strip.core.upperBound))
            #expect(strip.crop.height <= 1_920)
            if index > 0 {
                let previous = strips[index - 1]
                #expect(previous.core.upperBound == strip.core.lowerBound)
                #expect(previous.crop.maxY >= strip.crop.minY)
                #expect(strip.crop.minY == CGFloat(strip.core.lowerBound - 192))
            }
        }
    }

    @Test(arguments: [1, 1_535, 1_536, 1_537, 2_000, 4_096])
    func wideRecognitionTilesCoverBothAxesWithoutCoreOverlap(_ width: Int) {
        let height = 3_100
        let tiles = recognitionStrips(width: width, height: height)
        #expect(tiles.reduce(0) { $0 + $1.coreX.count * $1.core.count } == width * height)
        for (index, tile) in tiles.enumerated() {
            #expect(tile.crop.minX >= 0 && tile.crop.maxX <= CGFloat(width))
            #expect(tile.crop.minY >= 0 && tile.crop.maxY <= CGFloat(height))
            #expect(tile.crop.minX <= CGFloat(tile.coreX.lowerBound))
            #expect(tile.crop.maxX >= CGFloat(tile.coreX.upperBound))
            #expect(tile.crop.minY <= CGFloat(tile.core.lowerBound))
            #expect(tile.crop.maxY >= CGFloat(tile.core.upperBound))
            #expect(tile.crop.width <= 2_048 && tile.crop.height <= 1_920)
            for other in tiles.dropFirst(index + 1) {
                #expect(!tile.coreX.overlaps(other.coreX) || !tile.core.overlaps(other.core))
            }
        }
    }

    @Test func delayedVisibleCopyIsObservedBeforeReturningItsActualPNG() async throws {
        var observedWaitingFrame = false
        var observations = 0
        let captured = try await FleetViewRenderHarness.render(
            FleetDelayedCopyProbe(), readiness: {
                observations += 1
                observedWaitingFrame = observedWaitingFrame || $0.visibleText.contains("Waiting for a frame")
                return $0.visibleText.contains("Actual delayed copy")
            })
        #expect(observedWaitingFrame && observations >= 2)
        #expect(captured.visibleText.contains("Actual delayed copy"))
        #expect(!captured.visibleText.contains("Waiting for a frame"))
        #expect(!captured.pngData.isEmpty && captured.pixelVariation > 1)
    }

    @Test func unmetReadinessFailsAndReleasesTheHostForTheNextCapture() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalKeyWindow = scene.keyWindow
        await #expect(throws: FleetRenderReadinessError.timedOut) {
            try await FleetViewRenderHarness.render(Text("Never ready"), readiness: { _ in false })
        }
        #expect(scene.keyWindow === originalKeyWindow)
        let recovered = try await FleetViewRenderHarness.render(Text("Real recovery frame"))
        #expect(recovered.visibleText.contains("Real recovery frame"))
    }

    @Test func fixtureBlocksNetworkAndKeepsDemoLocal() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        #expect(fixture.store.isDemo)
        #expect(!fixture.store.devices.isEmpty)
        #expect(!fixture.store.preferences.externalDataEnabled)
        #expect(!fixture.store.preferences.realtimeMonitoring)
        do {
            _ = try await fixture.session.data(from: #require(URL(string: "https://fixture.invalid/read")))
            Issue.record("The fixture must reject every network request")
        } catch {
            #expect((error as? URLError)?.code == .notConnectedToInternet)
        }
    }
}

private struct FleetDelayedCopyProbe: View {
    @State private var ready = false
    var body: some View {
        Text(ready ? "Actual delayed copy" : "Waiting for a frame")
            .font(.system(size: 22))
            .foregroundStyle(.white)
            .padding()
            .background(Color.black)
            .task {
                try? await Task.sleep(for: .seconds(1))
                ready = true
            }
    }
}
