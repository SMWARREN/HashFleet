import SwiftUI
import QuartzCore
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Per-screen callback cadence diagnostics monitor.
/// iOS observes CADisplayLink callbacks. Native macOS observes main-run-loop timer callbacks.
/// Note: Never claims true GPU render time, compositor presentation time, or dropped render frames.
@MainActor @Observable
public final class FleetPerformanceMonitor {
    public static let shared = FleetPerformanceMonitor()

    // MARK: - Observable Properties

    /// Whether callback cadence monitoring is active.
    public var enabled: Bool = false {
        didSet {
            guard enabled != oldValue else { return }
            if enabled {
                setupDisplayLinkIfNeeded()
                resetBaseline()
            } else {
                teardownDisplayLink()
                resetBaseline()
                displayMetrics = nil
            }
        }
    }

    /// Current active screen name based on top-of-stack token claims.
    public private(set) var activeScreen: String = "Unknown"

    /// Current metrics published at most once per second.
    public private(set) var displayMetrics: DisplayMetrics?

    /// Rolling reports per screen, retained in memory for this diagnostic session.
    public private(set) var screenReports: [String: ScreenReport] = [:]

    // MARK: - Diagnostics Models

    public struct DisplayMetrics: Sendable, Equatable {
        public let screen: String
        public let callbackFPS: Double
        public let averageFrameMs: Double
        public let p95GapMs: Double
        public let maxGapMs: Double
        public let slowGapsCount: Int
        public let totalSamples: Int

        public init(
            screen: String,
            callbackFPS: Double,
            averageFrameMs: Double,
            p95GapMs: Double,
            maxGapMs: Double,
            slowGapsCount: Int,
            totalSamples: Int
        ) {
            self.screen = screen
            self.callbackFPS = callbackFPS
            self.averageFrameMs = averageFrameMs
            self.p95GapMs = p95GapMs
            self.maxGapMs = maxGapMs
            self.slowGapsCount = slowGapsCount
            self.totalSamples = totalSamples
        }
    }

    public struct ScreenReport: Sendable, Identifiable, Equatable {
        public var id: String { screen }
        public let screen: String
        public var callbackFPS: Double
        public var averageFrameMs: Double
        public var p95GapMs: Double
        public var maxGapMs: Double
        public var slowGapsCount: Int
        public var totalSamples: Int
        public var lastUpdated: CFTimeInterval

        public init(
            screen: String,
            callbackFPS: Double,
            averageFrameMs: Double,
            p95GapMs: Double,
            maxGapMs: Double,
            slowGapsCount: Int,
            totalSamples: Int,
            lastUpdated: CFTimeInterval
        ) {
            self.screen = screen
            self.callbackFPS = callbackFPS
            self.averageFrameMs = averageFrameMs
            self.p95GapMs = p95GapMs
            self.maxGapMs = maxGapMs
            self.slowGapsCount = slowGapsCount
            self.totalSamples = totalSamples
            self.lastUpdated = lastUpdated
        }
    }

    // MARK: - Private State

    #if canImport(UIKit)
    @ObservationIgnored nonisolated(unsafe) private var displayLink: CADisplayLink?
    @ObservationIgnored private var displayLinkTarget: DisplayLinkTarget?
    #elseif os(macOS)
    @ObservationIgnored private var cadenceTimer: Timer?
    #endif
    @ObservationIgnored private var isSceneActive: Bool = true

    /// Screen stack managing token-based lifetimes.
    @ObservationIgnored private var screenStack: [ScreenToken] = []
    @ObservationIgnored private var activeScreenToken: ScreenToken?

    /// Internal calculation accumulator.
    @ObservationIgnored var accumulator = CadenceAccumulator()
    @ObservationIgnored private var savedAccumulators: [String: CadenceAccumulator] = [:]
    @ObservationIgnored private let drivesDisplayLink: Bool
    @ObservationIgnored private var lastPublishedTime: CFTimeInterval = 0

    public init(processArguments: [String] = ProcessInfo.processInfo.arguments, drivesDisplayLink: Bool = true) {
        self.drivesDisplayLink = drivesDisplayLink
        let launchArgEnabled = processArguments.contains("--frame-pacing")
        self.enabled = launchArgEnabled
        if launchArgEnabled {
            setupDisplayLinkIfNeeded()
        }
    }

    // MARK: - Scene State API

    /// Call when the host scene phase changes (e.g. active vs background/inactive).
    public func setActive(_ active: Bool) {
        guard isSceneActive != active else { return }
        isSceneActive = active
        if isSceneActive && enabled {
            setupDisplayLinkIfNeeded()
            resetBaseline()
        } else {
            teardownDisplayLink()
            resetBaseline()
        }
    }

    // MARK: - Reset

    /// Clears all accumulated session reports and active accumulator samples.
    public func reset() {
        screenReports.removeAll()
        savedAccumulators.removeAll()
        displayMetrics = nil
        accumulator.reset()
        lastPublishedTime = 0
    }

    /// Resets the timing baseline without discarding historical screen reports.
    public func resetBaseline() {
        accumulator.resetBaseline()
        lastPublishedTime = 0
    }

    // MARK: - Screen Lifecycle Management

    public struct ScreenToken: Equatable, Hashable {
        public let id: UUID
        public let screenName: String

        public init(screenName: String) {
            self.id = UUID()
            self.screenName = screenName
        }
    }

    /// Claim screen ownership when a screen appears. Returns a unique token to be released on disappear.
    public func claimScreen(_ screenName: String) -> ScreenToken {
        let token = ScreenToken(screenName: screenName)
        screenStack.append(token)
        updateActiveScreenFromStack()
        return token
    }

    /// Release screen ownership when a screen disappears using the token acquired on claim.
    public func releaseScreen(_ token: ScreenToken) {
        screenStack.removeAll { $0.id == token.id }
        updateActiveScreenFromStack()
    }

    private func updateActiveScreenFromStack() {
        let nextToken = screenStack.last
        guard nextToken != activeScreenToken else { return }
        if enabled, activeScreenToken != nil {
            publishCurrentMetrics(now: lastPublishedTime, screen: activeScreen)
            savedAccumulators[activeScreen] = accumulator
        }
        activeScreenToken = nextToken
        let nextName = nextToken?.screenName ?? "Unknown"
        activeScreen = nextName
        accumulator = savedAccumulators[nextName] ?? CadenceAccumulator()

        // Reset baseline on screen change so gaps between screen transitions do not skew metrics
        accumulator.resetBaseline()
        lastPublishedTime = 0
        displayMetrics = nil
    }

    // MARK: - Platform Callback Lifecycle

    private func teardownDisplayLink() {
        #if canImport(UIKit)
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
        #elseif os(macOS)
        cadenceTimer?.invalidate()
        cadenceTimer = nil
        #endif
    }

    #if canImport(UIKit)
    private func setupDisplayLinkIfNeeded() {
        guard drivesDisplayLink, displayLink == nil, enabled, isSceneActive else { return }
        let target = DisplayLinkTarget { [weak self] displayLink in
            self?.handleDisplayLinkCallback(displayLink)
        }
        displayLinkTarget = target
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.onTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        accumulator.resetBaseline()
    }

    private func handleDisplayLinkCallback(_ link: CADisplayLink) {
        guard enabled, isSceneActive else { return }
        recordFrame(
            timestamp: link.timestamp,
            targetTimestamp: link.targetTimestamp,
            duration: link.duration
        )
    }
    #elseif os(macOS)
    private func setupDisplayLinkIfNeeded() {
        guard drivesDisplayLink, cadenceTimer == nil, enabled, isSceneActive else { return }
        let interval = 1.0 / 60.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let timestamp = ProcessInfo.processInfo.systemUptime
                self?.recordFrame(
                    timestamp: timestamp,
                    targetTimestamp: timestamp + interval,
                    duration: interval
                )
            }
        }
        timer.tolerance = interval * 0.1
        cadenceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        accumulator.resetBaseline()
    }
    #endif

    /// Pure driver method exposed internally for tests and display link ticks.
    func recordFrame(timestamp: CFTimeInterval, targetTimestamp: CFTimeInterval, duration: CFTimeInterval) {
        guard enabled, isSceneActive, activeScreenToken != nil else { return }
        let screen = activeScreen
        accumulator.recordFrame(
            timestamp: timestamp,
            targetTimestamp: targetTimestamp,
            duration: duration
        )

        // Throttle UI publication to max once per second
        if lastPublishedTime == 0 || (timestamp - lastPublishedTime >= 1.0) {
            publishCurrentMetrics(now: timestamp, screen: screen)
        }
    }

    private func publishCurrentMetrics(now: CFTimeInterval, screen: String) {
        guard let summary = accumulator.computeSummary() else { return }
        lastPublishedTime = now

        let metrics = DisplayMetrics(
            screen: screen,
            callbackFPS: summary.callbackFPS,
            averageFrameMs: summary.averageFrameMs,
            p95GapMs: summary.p95GapMs,
            maxGapMs: summary.maxGapMs,
            slowGapsCount: summary.slowGapsCount,
            totalSamples: summary.totalSamples
        )
        self.displayMetrics = metrics

        var report = screenReports[screen] ?? ScreenReport(
            screen: screen,
            callbackFPS: summary.callbackFPS,
            averageFrameMs: summary.averageFrameMs,
            p95GapMs: summary.p95GapMs,
            maxGapMs: summary.maxGapMs,
            slowGapsCount: 0,
            totalSamples: 0,
            lastUpdated: now
        )
        report.callbackFPS = summary.callbackFPS
        report.averageFrameMs = summary.averageFrameMs
        report.p95GapMs = summary.p95GapMs
        report.maxGapMs = summary.maxGapMs
        report.slowGapsCount = summary.slowGapsCount
        report.totalSamples = summary.totalSamples
        report.lastUpdated = now
        screenReports[screen] = report
    }

    isolated deinit {
        #if canImport(UIKit)
        displayLink?.invalidate()
        #elseif os(macOS)
        cadenceTimer?.invalidate()
        #endif
    }
}

#if canImport(UIKit)
// MARK: - Weak Target Helper for CADisplayLink
@MainActor private final class DisplayLinkTarget: NSObject {
    private let onTickHandler: (CADisplayLink) -> Void

    init(onTick: @escaping (CADisplayLink) -> Void) {
        self.onTickHandler = onTick
        super.init()
    }

    @objc func onTick(_ displayLink: CADisplayLink) {
        onTickHandler(displayLink)
    }
}
#endif

// MARK: - Per-Screen ViewModifier

public struct FleetPerformanceScreenModifier: ViewModifier {
    let screenName: String
    @State private var token: FleetPerformanceMonitor.ScreenToken?

    public init(screenName: String) {
        self.screenName = screenName
    }

    public func body(content: Content) -> some View {
        content
            .onAppear {
                if token == nil {
                    token = FleetPerformanceMonitor.shared.claimScreen(screenName)
                }
            }
            .onDisappear {
                if let activeToken = token {
                    FleetPerformanceMonitor.shared.releaseScreen(activeToken)
                    token = nil
                }
            }
    }
}

extension View {
    /// Tracks platform callback cadence for this screen when diagnostics are enabled.
    /// Uses token lifecycle so nested or stacked screens with identical names cleanly register and unregister.
    public func fleetPerformanceScreen(_ name: String) -> some View {
        modifier(FleetPerformanceScreenModifier(screenName: name))
    }
}

// MARK: - Isolated Overlay View

/// Floating HUD showing current screen and cadence statistics only while enabled.
/// Observations are isolated so that monitor frame updates do not trigger redraws in parent views.
public struct FleetPerformanceOverlay: View {
    @Bindable private var monitor = FleetPerformanceMonitor.shared

    public init() {}

    public var body: some View {
        if monitor.enabled, let metrics = monitor.displayMetrics {
            overlayContent(metrics)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("performance.overlay")
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func overlayContent(_ metrics: FleetPerformanceMonitor.DisplayMetrics) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(metrics.screen) \u{00B7} callback FPS \u{2248}\(metrics.callbackFPS, specifier: "%.0f")")
                .accessibilityIdentifier("performance.currentScreen")
            Text("p95 \(metrics.p95GapMs, specifier: "%.1f") ms \u{00B7} max \(metrics.maxGapMs, specifier: "%.1f") ms")
        }
        .fleetFont(.caption2, design: .monospaced)
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))

    }
}
