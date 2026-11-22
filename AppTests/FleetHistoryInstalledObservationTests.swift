import Foundation
import SwiftUI
import Charts
import Testing
import Accessibility
import HashFleetCore
#if !os(macOS)
import UIKit
@testable import HashFleet

private final class InstalledObservationTestWindow: UIWindow {
    override var canBecomeKey: Bool { false }
}

private final class InstalledObservationHostingController<Content: View>: UIHostingController<Content> {
    private(set) var didAppear = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppear = true
    }
}

/// Verification suite for real installed Swift Charts accessibility and hierarchy updates.
/// Exercises 12 consecutive alternating-unit telemetry bursts on a single mounted UIWindow
/// without synthetic data dropping, future timestamps, or unmounted-card warnings.
@Suite("Installed Chart Observation", .serialized)
@MainActor
struct FleetHistoryInstalledObservationTests {
    @Test(arguments: [true, false])
    func previewTimestampLabelsUpdateWithoutMoving(essentials: Bool) async throws {
        let feed = MountedFleetHistoryFeed()
        let device = MinerDevice(name: "Chart fixture", address: "chart-fixture.invalid")
        feed.devices = [device]
        let hour = try #require(Calendar.current.dateInterval(of: .hour, for: .now))
        let anchor = hour.start.addingTimeInterval(-45 * 60 + 15)
        let offsets: [TimeInterval] = [-55, -40, -25, -10, 0]
        let axisFormat = Date.FormatStyle.dateTime.hour().minute().second()

        func publish(step: Int) -> (first: Date, last: Date) {
            let last = anchor.addingTimeInterval(Double(step * 7))
            let points = offsets.enumerated().map { index, offset in
                HashratePoint(date: last.addingTimeInterval(offset), value: 900 + Double(index * 21 + step * 8))
            }
            feed.snapshots = [device.id: MinerSnapshot(updatedAt: last, history: points)]
            return (last.addingTimeInterval(offsets[0]), last)
        }

        func clockDigits(_ text: String) -> String { text.filter { $0.isNumber || $0 == ":" } }
        func timestamp(_ date: Date, in capture: FleetRenderedView) throws -> CGRect {
            let digits = clockDigits(date.formatted(axisFormat))
            return try #require(capture.recognition.words.first {
                clockDigits($0.text) == digits
            }, "The plotted sample time \(digits) must be visible; read \(capture.visibleText)").bounds
        }

        let initial = publish(step: 0)
        _ = try await FleetViewRenderHarness.render(
            PreviewHistoryTimestampFixture(feed: feed, essentials: essentials), width: 375, height: 268,
            readiness: { capture in
                capture.recognition.words.contains { clockDigits($0.text) == clockDigits(initial.last.formatted(axisFormat)) }
            }, inspection: { view in
                let initialCapture = try await FleetViewRenderHarness.capture(view, named: "chart-times-start.png")
                let initialFirst = try timestamp(initial.first, in: initialCapture)
                let initialLast = try timestamp(initial.last, in: initialCapture)
                #expect(initialFirst.maxX < initialLast.minX)
                let tolerance = 3 * view.traitCollection.displayScale
                // Vision can recognize the exact digits but sometimes return a box for only
                // part of a word. Use the source pixels for the position and visibility checks.
                let row = initialFirst.union(initialLast).insetBy(dx: 0, dy: -tolerance * 2).integral
                let firstInk = try Self.timestampInk(in: initialCapture, row: row, trailing: false)
                let lastInk = try Self.timestampInk(in: initialCapture, row: row, trailing: true)
                for step in 1...4 {
                    let current = withAnimation(.easeInOut(duration: 0.65)) { publish(step: step) }
                    // Capture after layout, while an inherited 650ms animation could still be active.
                    try await Task.sleep(for: .milliseconds(115))
                    let frame = try await FleetViewRenderHarness.capture(view, named: "chart-times-tick-\(step).png")
                    _ = try timestamp(current.first, in: frame)
                    _ = try timestamp(current.last, in: frame)
                    let first = try Self.timestampInk(in: frame, row: row, trailing: false)
                    let last = try Self.timestampInk(in: frame, row: row, trailing: true)
                    #expect(abs(first.minX - firstInk.minX) <= tolerance)
                    #expect(abs(last.maxX - lastInk.maxX) <= tolerance)
                    #expect(abs(first.midY - firstInk.midY) <= tolerance)
                    #expect(abs(last.midY - lastInk.midY) <= tolerance)
                }
            }
        )
    }

    private static func timestampInk(in capture: FleetRenderedView, row: CGRect, trailing: Bool) throws -> CGRect {
        let image = try #require(UIImage(data: capture.pngData)?.cgImage)
        let minX = trailing ? image.width / 2 : image.width / 6
        let maxX = trailing ? image.width : image.width / 2
        let region = CGRect(x: CGFloat(minX), y: row.minY, width: CGFloat(maxX - minX), height: row.height)
        let crop = try #require(image.cropping(to: region))
        return try #require(timestampInkBounds(in: crop), "Timestamp must remain visibly painted during the update")
    }

    private static func timestampInkBounds(in image: CGImage) -> CGRect? {
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        return rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = bytes.bindMemory(to: UInt8.self)
            var bounds = CGRect.null
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let index = (y * image.width + x) * 4
                    let (red, green, blue) = (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
                    // Neutral, readable caption ink, not the dim grid or gold series.
                    if red >= 115, max(red, green, blue) - min(red, green, blue) < 42 {
                        bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
            }
            return bounds.isNull ? nil : bounds
        }
    }

    private static func observationDevices() -> [MinerDevice] {
        (1...20).map { idx in
            MinerDevice(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", idx))!,
                name: "Miner \(idx % 4)",
                address: "192.168.1.\(100 + idx)"
            )
        }
    }

    private static let shapeProfiles: [[Double]] = [
        [0.85, 0.90, 1.00, 1.05, 1.10],
        [1.15, 1.10, 1.00, 0.95, 0.90],
        [0.90, 1.10, 0.95, 1.08, 1.02],
        [1.00, 1.06, 1.12, 1.08, 1.00],
        [1.10, 0.94, 0.90, 0.96, 1.08],
        [0.80, 0.90, 1.00, 1.12, 1.18],
        [1.20, 1.10, 1.00, 0.92, 0.82],
        [0.94, 1.00, 1.06, 1.02, 0.96],
        [1.06, 0.94, 1.06, 0.94, 1.04],
        [0.88, 0.94, 1.00, 1.06, 1.12],
        [1.08, 1.00, 0.92, 0.98, 1.06],
        [0.92, 1.04, 0.96, 1.08, 1.00]
    ]

    private static let baseRates: [(isHigh: Bool, baseRate: Double)] = [
        (false, 20.0), (true, 60.0), (false, 18.0), (true, 55.0),
        (false, 24.0), (true, 68.0), (false, 15.0), (true, 62.0),
        (false, 22.0), (true, 58.0), (false, 19.0), (true, 64.0)
    ]

    private static func makeSnapshots(
        devices: [MinerDevice],
        baseRate: Double,
        shape: [Double],
        timestamps: [Date]
    ) -> (snapshots: [UUID: MinerSnapshot], aggregates: [Double]) {
        var snapshots: [UUID: MinerSnapshot] = [:]
        var aggregates = [Double](repeating: 0.0, count: 5)
        for (deviceIndex, device) in devices.enumerated() {
            // Subtle deterministic per-device spread (±4%) to preserve unique series data
            let deviceFactor = 1.0 + Double((deviceIndex % 5) - 2) * 0.02
            var points: [HashratePoint] = []
            for pointIndex in 0..<5 {
                let pointRate = baseRate * shape[pointIndex] * deviceFactor
                points.append(HashratePoint(date: timestamps[pointIndex], value: pointRate))
                aggregates[pointIndex] += pointRate
            }
            var snapshot = MinerSnapshot()
            snapshot.history = points
            snapshots[device.id] = snapshot
        }
        return (snapshots, aggregates)
    }

    private static func matchesCurrentStep(
        _ observation: MountedChartAXProbe.Observation,
        expectedYAxisTitle: String,
        expectedTimestamp: Double,
        expectedValue: Double
    ) -> Bool {
        guard observation.descriptorAvailable,
              observation.series.count == 1,
              let series = observation.series.first,
              series.pointCount == 5,
              observation.yAxisTitle == expectedYAxisTitle,
              series.latestPoints.count == 1,
              let latest = series.latestPoints.first,
              let value = latest.value else {
            return false
        }
        return abs(latest.timestamp - expectedTimestamp) < 0.05
            && abs(value - expectedValue) < 0.01
    }

    private static func expectPhaseUnit(_ unit: HashrateUnit, isHighPhase: Bool, step: Int) {
        if isHighPhase {
            #expect(unit == .teraHashesPerSecond, "Step \(step): High phase must produce .terahash unit")
        } else {
            #expect(unit == .gigaHashesPerSecond, "Step \(step): Low phase must produce .gigahash unit")
        }
    }

    private static func latestChartValue(
        in observation: MountedChartAXProbe.Observation,
        step: Int
    ) throws -> (timestamp: Double, value: Double) {
        let series = try #require(observation.series.first, "Step \(step): Aggregated series must be present")
        #expect(series.pointCount == 5, "Step \(step): Series must contain 5 data points (got \(series.pointCount))")
        #expect(series.latestPoints.count == 1, "Step \(step): Series must contain exactly 1 latest point (got \(series.latestPoints.count))")
        let latestPoint = try #require(series.latestPoints.first, "Step \(step): Latest point must exist")
        let value = try #require(latestPoint.value, "Step \(step): Latest point value must not be nil")
        return (latestPoint.timestamp, value)
    }

    private struct DiagnosticInput {
        let step: Int
        let isHighPhase: Bool
        let expectedUnit: String
        let latestAggregateGHs: Double
        let expectedLatestY: Double
        let expectedTimestamp: Double
        let observation: MountedChartAXProbe.Observation
        let drawSuccess: Bool
        let imageDimensions: String
        let pollDuration: Double
    }

    private static func makeDiagnostic(_ input: DiagnosticInput) -> StepDiagnostic {
        let observation = input.observation
        let observedSeries = observation.series.first
        let observedLatestPoints = observedSeries?.latestPoints ?? []
        let latestPoint = observedLatestPoints.first
        return StepDiagnostic(
            step: input.step,
            isHighPhase: input.isHighPhase,
            expectedUnit: input.expectedUnit,
            expectedLatestAggregateGHs: input.latestAggregateGHs,
            expectedLatestYValue: input.expectedLatestY,
            expectedLatestTimestamp: input.expectedTimestamp,
            expectedDateEncodingRationale: "Unix seconds: FleetAXChartDescriptorProvider maps point.date.timeIntervalSince1970 to AXDataPoint.x",
            observedTargetFound: observation.targetFound,
            observedConformsToAXChart: observation.conformsToAXChart,
            observedDescriptorAvailable: observation.descriptorAvailable,
            observedDescriptorTitle: observation.descriptorTitle,
            observedYAxisTitle: observation.yAxisTitle,
            observedSeriesCount: observation.series.count,
            observedSeriesName: observedSeries?.name,
            observedPointCount: observedSeries?.pointCount ?? 0,
            observedLatestPointsCount: observedLatestPoints.count,
            observedLatestTimestamp: latestPoint?.timestamp,
            observedLatestValue: latestPoint?.value ?? nil,
            visitedNodes: observation.visited,
            exhaustedVisitBudget: observation.exhaustedVisitBudget,
            truncatedDepthOrChildren: observation.truncatedDepthOrChildren,
            drawHierarchySuccess: input.drawSuccess,
            imageDimensions: input.imageDimensions,
            pollDurationSeconds: input.pollDuration
        )
    }

    struct StepDiagnostic: Codable, Sendable {
        let step: Int
        let isHighPhase: Bool
        let expectedUnit: String
        let expectedLatestAggregateGHs: Double
        let expectedLatestYValue: Double
        let expectedLatestTimestamp: Double
        let expectedDateEncodingRationale: String
        let observedTargetFound: Bool
        let observedConformsToAXChart: Bool
        let observedDescriptorAvailable: Bool
        let observedDescriptorTitle: String?
        let observedYAxisTitle: String?
        let observedSeriesCount: Int
        let observedSeriesName: String?
        let observedPointCount: Int
        let observedLatestPointsCount: Int
        let observedLatestTimestamp: Double?
        let observedLatestValue: Double?
        let visitedNodes: Int
        let exhaustedVisitBudget: Bool
        let truncatedDepthOrChildren: Bool
        let drawHierarchySuccess: Bool
        let imageDimensions: String
        let pollDurationSeconds: Double
    }

    @MainActor
    private final class InstalledObservationHost {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 240)
        let scene: UIWindowScene
        let originalKeyWindow: UIWindow?
        let window: InstalledObservationTestWindow
        let controller: InstalledObservationHostingController<MountedFleetHistoryContainer>

        init(feed: MountedFleetHistoryFeed) throws {
            let rawScene = try #require(UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first)
            self.scene = rawScene
            self.originalKeyWindow = rawScene.keyWindow

            let root = MountedFleetHistoryContainer(feed: feed)
            controller = InstalledObservationHostingController(rootView: root)
            controller.overrideUserInterfaceStyle = .dark
            window = InstalledObservationTestWindow(windowScene: rawScene)
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

        func captureHierarchy() -> (success: Bool, image: UIImage) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = controller.view.traitCollection.displayScale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
            var drawSuccess = false
            let image = renderer.image { _ in
                drawSuccess = controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
            }
            return (drawSuccess, image)
        }

        func teardown() {
            #expect(scene.keyWindow === originalKeyWindow, "Original key window must remain unchanged")
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    @Test("Installed FleetHistoryCard descriptor updates across 12 alternating unit bursts")
    func installedFleetHistoryCardTwelveStepAlternatingObservation() async throws {
        let feed = MountedFleetHistoryFeed()

        // 20 devices with distinct valid UUIDs, intentionally repeating 4 display names
        let devices = Self.observationDevices()
        feed.devices = devices

        let host = try InstalledObservationHost(feed: feed)

        var diagnostics: [StepDiagnostic] = []

        defer {
            print("=== FLEET_HISTORY_INSTALLED_OBSERVATION_DIAGNOSTICS ===")
            for diag in diagnostics {
                print(
                    "STEP \(diag.step): high=\(diag.isHighPhase) unit=\(diag.expectedUnit) " +
                    "expectedY=\(diag.expectedLatestYValue) observedY=\(diag.observedLatestValue ?? -1) " +
                    "AXTitle=\(diag.observedYAxisTitle ?? "nil") descAvail=\(diag.observedDescriptorAvailable) " +
                    "draw=\(diag.drawHierarchySuccess) poll=\(diag.pollDurationSeconds)s visited=\(diag.visitedNodes)"
                )
            }
            if let jsonData = try? JSONEncoder().encode(diagnostics),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("FLEET_HISTORY_INSTALLED_OBSERVATION_JSON \(jsonString)")
                Attachment.record(jsonString, named: "fleet-history-installed-observation.json")
            }
            host.teardown()
        }

        try await host.awaitAppearance()

        for step in 0..<12 {
            let (isHighPhase, baseRate) = Self.baseRates[step]
            let shape = Self.shapeProfiles[step]

            // 5 chronological points strictly in recent 5 minutes: -240s, -180s, -120s, -60s, 0s
            let stepAnchor = Date()
            let timestamps = (0..<5).map { idx in
                stepAnchor.addingTimeInterval(-Double(4 - idx) * 60.0)
            }

            let generated = Self.makeSnapshots(
                devices: devices,
                baseRate: baseRate,
                shape: shape,
                timestamps: timestamps
            )
            let perPointAggregates = generated.aggregates

            let aggregateMaxGHs = perPointAggregates.max() ?? 0.0
            let expectedUnit = FleetFormat.hashrateDisplayUnit(forGHs: aggregateMaxGHs)

            // Assert that the expected unit strictly matches the predeclared phase
            Self.expectPhaseUnit(expectedUnit, isHighPhase: isHighPhase, step: step)

            let latestAggregateGHs = perPointAggregates[4]
            let expectedLatestY = expectedUnit.value(fromGHs: latestAggregateGHs)
            // Rationale: FleetAXChartDescriptorProvider maps point.date.timeIntervalSince1970 directly to AXDataPoint.x (Double)
            let expectedLatestTimestamp = timestamps[4].timeIntervalSince1970
            let expectedYAxisTitle = "Hashrate in \(expectedUnit.rawValue)"

            // Push snapshots to feed model to trigger SwiftUI body and AttributeGraph update
            feed.snapshots = generated.snapshots

            // Force initial layout
            host.controller.view.setNeedsLayout()
            host.controller.view.layoutIfNeeded()

            // Predicate: Polling must require expected unit, point count, single latest point,
            // and expected timestamp/value to avoid falsely matching a stale descriptor from a previous step.
            // Poll bounded <= 1.0s for current step's installed accessibility descriptor
            let pollStart = Date()
            let pollDeadline = pollStart.addingTimeInterval(1.0)
            var observation = MountedChartAXProbe.inspect(root: host.controller.view)

            while !Self.matchesCurrentStep(
                observation,
                expectedYAxisTitle: expectedYAxisTitle,
                expectedTimestamp: expectedLatestTimestamp,
                expectedValue: expectedLatestY
            ) && Date() < pollDeadline {
                try await Task.sleep(for: .milliseconds(25))
                host.controller.view.setNeedsLayout()
                host.controller.view.layoutIfNeeded()
                await Task.yield()
                observation = MountedChartAXProbe.inspect(root: host.controller.view)
            }

            let pollDuration = Date().timeIntervalSince(pollStart)

            // Capture hierarchy with afterScreenUpdates: true
            let (drawSuccess, capturedImage) = host.captureHierarchy()
            let imageDimensions = "\(Int(capturedImage.size.width))x\(Int(capturedImage.size.height))"

            // Attach actual rendered image for first and last steps to demonstrate drawing
            if step == 0, let png = capturedImage.pngData() {
                Attachment.record(png, named: "installed-chart-step-0-first.png")
            } else if step == 11, let png = capturedImage.pngData() {
                Attachment.record(png, named: "installed-chart-step-11-last.png")
            }

            let diag = Self.makeDiagnostic(DiagnosticInput(
                step: step,
                isHighPhase: isHighPhase,
                expectedUnit: expectedUnit.rawValue,
                latestAggregateGHs: latestAggregateGHs,
                expectedLatestY: expectedLatestY,
                expectedTimestamp: expectedLatestTimestamp,
                observation: observation,
                drawSuccess: drawSuccess,
                imageDimensions: imageDimensions,
                pollDuration: pollDuration
            ))
            diagnostics.append(diag)

            // Strict required assertions: no conditional if-let that skips assertions
            #expect(observation.targetFound, "Step \(step): Chart with identifier dashboard.historyChart must be found in view hierarchy")
            #expect(observation.conformsToAXChart, "Step \(step): Chart element must conform to AXChart")
            #expect(observation.descriptorAvailable, "Step \(step): accessibilityChartDescriptor must be available within 1s")
            #expect(observation.series.count == 1, "Step \(step): Fleet chart must produce exactly 1 aggregated series (observed \(observation.series.count))")
            #expect(observation.yAxisTitle == expectedYAxisTitle, "Step \(step): yAxis.title must match expected unit (expected '\(expectedYAxisTitle)', got '\(observation.yAxisTitle ?? "nil")')")

            let latest = try Self.latestChartValue(in: observation, step: step)

            #expect(
                abs(latest.timestamp - expectedLatestTimestamp) < 0.05,
                """
                Step \(step): Latest point timestamp must match expected anchor \
                (expected \(expectedLatestTimestamp), got \(latest.timestamp))
                """
            )
            #expect(abs(latest.value - expectedLatestY) < 0.01, "Step \(step): Latest point value must match expected aggregate \(expectedLatestY) (got \(latest.value))")
            #expect(drawSuccess, "Step \(step): drawHierarchy(afterScreenUpdates: true) must succeed")
        }

        #expect(diagnostics.count == 12, "Must complete all 12 observation steps")
    }
}

private struct PreviewHistoryTimestampFixture: View {
    let feed: MountedFleetHistoryFeed
    let essentials: Bool

    var body: some View {
        FleetHistoryCard(
            devices: feed.devices, snapshots: feed.snapshots, isDemo: true,
            initialRecentRange: .oneMinute, isCompactDashboard: true,
            dashboardMode: essentials ? .essentials : .full, numberFirst: true
        )
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(FleetTheme.canvas)
        .environment(\.dynamicTypeSize, essentials ? .large : .xLarge)
    }
}
#endif
