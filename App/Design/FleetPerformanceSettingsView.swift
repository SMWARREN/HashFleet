import SwiftUI

// MARK: - Settings View

public struct FleetPerformanceSettingsView: View {
    @Bindable private var monitor = FleetPerformanceMonitor.shared

    public init() {}

    /// Only published while the diagnostic is running, so the card never presents a stale reading as live.
    private var liveMetrics: FleetPerformanceMonitor.DisplayMetrics? {
        monitor.enabled ? monitor.displayMetrics : nil
    }

    public var body: some View {
        List {
            Section {
                Toggle("Frame Pacing Diagnostics", isOn: $monitor.enabled)
                    .accessibilityIdentifier("performance.enabled")
            } footer: {
                Text(
                    "Local only. Nothing is uploaded or saved."
                    + " Reports use the latest 600 callback gaps per screen."
                    + " This diagnostic itself adds work and may affect refresh cadence."
                )
            }

            Section(header: Text("Callback metrics")) {
                let liveCallbackFPS = liveMetrics.map { String(format: "%.1f", $0.callbackFPS) } ?? "--"
                let liveP95 = liveMetrics.map { String(format: "%.1f", $0.p95GapMs) } ?? "--"
                let liveSlowGaps = liveMetrics.map { "\($0.slowGapsCount)" } ?? "--"

                InsightsMetricColumns(metrics: [
                    .init(title: "Callback FPS", value: liveCallbackFPS),
                    .init(title: "p95 interval", value: liveP95, unit: "ms"),
                    .init(title: "Slow gaps", value: liveSlowGaps)
                ])
                .accessibilityIdentifier("performance.callbackMetrics")
                if liveMetrics == nil {
                    Text("Enable diagnostics to record timings while using the app.")
                        .fleetFont(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text("Measurement Limitations")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notice on Timing Limitations")
                        .fleetFont(.subheadline, weight: .semibold)

                    Text(
                        "The monitor measures callback cadence only, not rendered frames or GPU time."
                        + " It does not measure GPU render time, compositor presentation time,"
                        + " or true dropped frames."
                    )
                        .fleetFont(.footnote)
                        .foregroundStyle(.secondary)

                    Text(
                        "The system can dynamically adjust callback cadences due to thermal"
                        + " state, battery saver, ProMotion, or background load. Target"
                        + " iOS uses display-link callbacks; macOS uses main-run-loop timer callbacks."
                    )
                        .fleetFont(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if monitor.enabled {
                Section(header: Text("Per-Screen Diagnostic Reports")) {
                    if monitor.screenReports.isEmpty {
                        Text("No screen reports accumulated yet.")
                            .fleetFont(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        // Keep the identity explicit. SwiftUI can otherwise infer a collection
                        // identity while the observable dictionary is being refreshed, which can
                        // trap in its internal key table during an unrelated view update.
                        ForEach(
                            monitor.screenReports.values.sorted(by: { $0.screen < $1.screen }),
                            id: \.screen
                        ) { report in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(report.screen)
                                        .fleetFont(.headline)
                                    Spacer()
                                    Text("Callback ≈\(report.callbackFPS, specifier: "%.1f") FPS")
                                        .fleetDisplayFont(role: .hero32, weight: .semibold, design: .monospaced)
                                }

                                HStack(spacing: 12) {
                                    Text("Avg: \(report.averageFrameMs, specifier: "%.1f")ms")
                                    Text("p95: \(report.p95GapMs, specifier: "%.1f")ms")
                                    Text("Max: \(report.maxGapMs, specifier: "%.1f")ms")
                                }
                                .fleetFont(.caption, design: .monospaced)
                                .foregroundStyle(.secondary)

                                HStack(spacing: 12) {
                                    Text("Slow gaps: \(report.slowGapsCount)")
                                    Text("Samples: \(report.totalSamples)")
                                }
                                .fleetFont(.caption2, design: .monospaced)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("performance.report.\(report.screen)")
                        }
                    }

                    Button("Reset Diagnostics", role: .destructive) {
                        monitor.reset()
                    }
                    .accessibilityIdentifier("performance.reset")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .navigationTitle("Frame Pacing")
        // The board uses the compact inline header on every sub-page rather than an iOS large title.
        .navigationBarTitleDisplayMode(.inline)
        .fleetPerformanceScreen("Performance")
    }
}
