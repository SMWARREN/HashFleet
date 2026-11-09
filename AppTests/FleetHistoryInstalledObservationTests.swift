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
        let devices = (1...20).map { idx in
            MinerDevice(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", idx))!,
                name: "Miner \(idx % 4)",
                address: "192.168.1.\(100 + idx)"
            )
        }
        feed.devices = devices

        let host = try InstalledObservationHost(feed: feed)

        var diagnostics: [StepDiagnostic] = []

        defer {
            print("=== FLEET_HISTORY_INSTALLED_OBSERVATION_DIAGNOSTICS ===")
            for diag in diagnostics {
                print("STEP \(diag.step): high=\(diag.isHighPhase) unit=\(diag.expectedUnit) expectedY=\(diag.expectedLatestYValue) observedY=\(diag.observedLatestValue ?? -1) AXTitle=\(diag.observedYAxisTitle ?? "nil") descAvail=\(diag.observedDescriptorAvailable) draw=\(diag.drawHierarchySuccess) poll=\(diag.pollDurationSeconds)s visited=\(diag.visitedNodes)")
            }
            if let jsonData = try? JSONEncoder().encode(diagnostics),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("FLEET_HISTORY_INSTALLED_OBSERVATION_JSON \(jsonString)")
                Attachment.record(jsonString, named: "fleet-history-installed-observation.json")
            }
            host.teardown()
        }

        try await host.awaitAppearance()

        // 12 steps: alternating low (GH/s) and high (TH/s) phases
        // Each step has 5 chronological points in the recent 5 minutes (strictly <= Date(), no future dates)
        // With meaningful varying shape profiles per step.
        let shapeProfiles: [[Double]] = [
            [0.85, 0.90, 1.00, 1.05, 1.10], // step 0 (low): rising
            [1.15, 1.10, 1.00, 0.95, 0.90], // step 1 (high): falling
            [0.90, 1.10, 0.95, 1.08, 1.02], // step 2 (low): oscillating
            [1.00, 1.06, 1.12, 1.08, 1.00], // step 3 (high): convex
            [1.10, 0.94, 0.90, 0.96, 1.08], // step 4 (low): concave
            [0.80, 0.90, 1.00, 1.12, 1.18], // step 5 (high): steep ramp
            [1.20, 1.10, 1.00, 0.92, 0.82], // step 6 (low): steep drop
            [0.94, 1.00, 1.06, 1.02, 0.96], // step 7 (high): gentle hump
            [1.06, 0.94, 1.06, 0.94, 1.04], // step 8 (low): zigzag
            [0.88, 0.94, 1.00, 1.06, 1.12], // step 9 (high): steady climb
            [1.08, 1.00, 0.92, 0.98, 1.06], // step 10 (low): trough
            [0.92, 1.04, 0.96, 1.08, 1.00]  // step 11 (high): flutter
        ]

        let baseRates: [(isHigh: Bool, baseRate: Double)] = [
            (false, 20.0), // 20 * 20 = 400 GH/s -> GH/s
            (true,  60.0), // 20 * 60 = 1,200 GH/s -> TH/s
            (false, 18.0), // 20 * 18 = 360 GH/s -> GH/s
            (true,  55.0), // 20 * 55 = 1,100 GH/s -> TH/s
            (false, 24.0), // 20 * 24 = 480 GH/s -> GH/s
            (true,  68.0), // 20 * 68 = 1,360 GH/s -> TH/s
            (false, 15.0), // 20 * 15 = 300 GH/s -> GH/s
            (true,  62.0), // 20 * 62 = 1,240 GH/s -> TH/s
            (false, 22.0), // 20 * 22 = 440 GH/s -> GH/s
            (true,  58.0), // 20 * 58 = 1,160 GH/s -> TH/s
            (false, 19.0), // 20 * 19 = 380 GH/s -> GH/s
            (true,  64.0)  // 20 * 64 = 1,280 GH/s -> TH/s
        ]

        for step in 0..<12 {
            let (isHighPhase, baseRate) = baseRates[step]
            let shape = shapeProfiles[step]

            // 5 chronological points strictly in recent 5 minutes: -240s, -180s, -120s, -60s, 0s
            let stepAnchor = Date()
            let timestamps = (0..<5).map { idx in
                stepAnchor.addingTimeInterval(-Double(4 - idx) * 60.0)
            }

            var snapshots: [UUID: MinerSnapshot] = [:]
            var perPointAggregates = [Double](repeating: 0.0, count: 5)

            for (devIdx, dev) in devices.enumerated() {
                // Subtle deterministic per-device spread (±4%) to preserve unique series data
                let deviceFactor = 1.0 + Double((devIdx % 5) - 2) * 0.02
                var points: [HashratePoint] = []
                for ptIdx in 0..<5 {
                    let pointRate = baseRate * shape[ptIdx] * deviceFactor
                    points.append(HashratePoint(date: timestamps[ptIdx], value: pointRate))
                    perPointAggregates[ptIdx] += pointRate
                }
                var snap = MinerSnapshot()
                snap.history = points
                snapshots[dev.id] = snap
            }

            let aggregateMaxGHs = perPointAggregates.max() ?? 0.0
            let expectedUnit = FleetFormat.hashrateDisplayUnit(forGHs: aggregateMaxGHs)

            // Assert that the expected unit strictly matches the predeclared phase
            if isHighPhase {
                #expect(expectedUnit == .teraHashesPerSecond, "Step \(step): High phase must produce .terahash unit")
            } else {
                #expect(expectedUnit == .gigaHashesPerSecond, "Step \(step): Low phase must produce .gigahash unit")
            }

            let latestAggregateGHs = perPointAggregates[4]
            let expectedLatestY = expectedUnit.value(fromGHs: latestAggregateGHs)
            // Rationale: FleetAXChartDescriptorProvider maps point.date.timeIntervalSince1970 directly to AXDataPoint.x (Double)
            let expectedLatestTimestamp = timestamps[4].timeIntervalSince1970
            let expectedYAxisTitle = "Hashrate in \(expectedUnit.rawValue)"

            // Push snapshots to feed model to trigger SwiftUI body and AttributeGraph update
            feed.snapshots = snapshots

            // Force initial layout
            host.controller.view.setNeedsLayout()
            host.controller.view.layoutIfNeeded()

            // Predicate: Polling must require expected unit, point count, single latest point,
            // and expected timestamp/value to avoid falsely matching a stale descriptor from a previous step.
            func matchesCurrentStep(_ obs: MountedChartAXProbe.Observation) -> Bool {
                guard obs.descriptorAvailable,
                      obs.series.count == 1,
                      let series = obs.series.first,
                      series.pointCount == 5,
                      obs.yAxisTitle == expectedYAxisTitle,
                      series.latestPoints.count == 1,
                      let latest = series.latestPoints.first,
                      let val = latest.value else {
                    return false
                }
                return abs(latest.timestamp - expectedLatestTimestamp) < 0.05
                    && abs(val - expectedLatestY) < 0.01
            }

            // Poll bounded <= 1.0s for current step's installed accessibility descriptor
            let pollStart = Date()
            let pollDeadline = pollStart.addingTimeInterval(1.0)
            var observation = MountedChartAXProbe.inspect(root: host.controller.view)

            while !matchesCurrentStep(observation) && Date() < pollDeadline {
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

            let observedSeries = observation.series.first
            let observedLatestPoints = observedSeries?.latestPoints ?? []
            let latestPoint = observedLatestPoints.first

            let diag = StepDiagnostic(
                step: step,
                isHighPhase: isHighPhase,
                expectedUnit: expectedUnit.rawValue,
                expectedLatestAggregateGHs: latestAggregateGHs,
                expectedLatestYValue: expectedLatestY,
                expectedLatestTimestamp: expectedLatestTimestamp,
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
                drawHierarchySuccess: drawSuccess,
                imageDimensions: imageDimensions,
                pollDurationSeconds: pollDuration
            )
            diagnostics.append(diag)

            // Strict required assertions: no conditional if-let that skips assertions
            #expect(observation.targetFound, "Step \(step): Chart with identifier dashboard.historyChart must be found in view hierarchy")
            #expect(observation.conformsToAXChart, "Step \(step): Chart element must conform to AXChart")
            #expect(observation.descriptorAvailable, "Step \(step): accessibilityChartDescriptor must be available within 1s")
            #expect(observation.series.count == 1, "Step \(step): Fleet chart must produce exactly 1 aggregated series (observed \(observation.series.count))")
            #expect(observation.yAxisTitle == expectedYAxisTitle, "Step \(step): yAxis.title must match expected unit (expected '\(expectedYAxisTitle)', got '\(observation.yAxisTitle ?? "nil")')")

            let series = try #require(observation.series.first, "Step \(step): Aggregated series must be present")
            #expect(series.pointCount == 5, "Step \(step): Series must contain 5 data points (got \(series.pointCount))")
            #expect(series.latestPoints.count == 1, "Step \(step): Series must contain exactly 1 latest point (got \(series.latestPoints.count))")

            let latestPt = try #require(series.latestPoints.first, "Step \(step): Latest point must exist")
            let observedVal = try #require(latestPt.value, "Step \(step): Latest point value must not be nil")

            #expect(abs(latestPt.timestamp - expectedLatestTimestamp) < 0.05, "Step \(step): Latest point timestamp must match expected anchor (expected \(expectedLatestTimestamp), got \(latestPt.timestamp))")
            #expect(abs(observedVal - expectedLatestY) < 0.01, "Step \(step): Latest point value must match expected aggregate \(expectedLatestY) (got \(observedVal))")
            #expect(drawSuccess, "Step \(step): drawHierarchy(afterScreenUpdates: true) must succeed")
        }

        #expect(diagnostics.count == 12, "Must complete all 12 observation steps")
    }
}
#endif
