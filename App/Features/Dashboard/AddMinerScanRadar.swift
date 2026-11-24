//
//  AddMinerScanRadar.swift
//  HashFleet
//
//  Adapted from ShipSwift (MIT)
//  Ideas adapted from SWScanningOverlay (scan sweep) and SWRingChart (progress ring).
//

import SwiftUI

/// Pure math and formatting helpers for AddMinerScanRadar, isolated for unit testing.
enum AddMinerScanRadarModel {
    /// Returns progress fraction clamped to 0.0 ... 1.0.
    /// Returns 0.0 safely when `hostCount <= 0`.
    static func progressFraction(probedHosts: Int, hostCount: Int) -> Double {
        guard hostCount > 0 else { return 0.0 }
        let fraction = Double(probedHosts) / Double(hostCount)
        return min(max(fraction, 0.0), 1.0)
    }

    /// Primary progress text: e.g. "Checked 42 of 254 addresses"
    static func progressText(probedHosts: Int, hostCount: Int) -> String {
        "Checked \(probedHosts) of \(hostCount) addresses"
    }

    /// Candidate count badge text: e.g. "3 found" or "0 found"
    static func foundCountText(candidatesCount: Int) -> String {
        "\(candidatesCount) found"
    }

    /// Percent text for display, e.g. "45%"
    static func percentText(fraction: Double) -> String {
        let clamped = min(max(fraction, 0.0), 1.0)
        let percent = Int((clamped * 100.0).rounded())
        return "\(percent)%"
    }
}

/// The single scan progress row: radar visual, checked count, found count and Cancel.
/// Replaces the header spinner, the "Checking up to" row and the separate progress line.
///
/// CPU & Accessibility rules:
/// - The radar is decorative; the row exposes one stable VoiceOver phrase instead of a
///   changing counter.
/// - The sweep runs only while `isScanning == true`, at most 30 fps, and not at all with Reduce Motion.
struct AddMinerScanRadar: View {
    let probedHosts: Int
    let hostCount: Int
    let candidatesCount: Int
    let isScanning: Bool
    var onCancel: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date.now

    // Dimensions
    private let radarSize: CGFloat = 52
    private let ringWidth: CGFloat = 4

    private var progress: Double {
        AddMinerScanRadarModel.progressFraction(probedHosts: probedHosts, hostCount: hostCount)
    }

    private var accessibilitySummary: String {
        let phase = checkingLateReplies ? "Checking for late replies" : "Scanning nearby network"
        return candidatesCount == 0
            ? phase
            : "\(phase), \(candidatesCount) \(candidatesCount == 1 ? "miner" : "miners") found so far"
    }

    private var checkingLateReplies: Bool { isScanning && hostCount > 0 && probedHosts >= hostCount }

    var body: some View {
        HStack(spacing: 14) {
            radarVisual
                .frame(width: radarSize, height: radarSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(checkingLateReplies ? "Checking for late replies…"
                     : AddMinerScanRadarModel.progressText(probedHosts: probedHosts, hostCount: hostCount))
                    .fleetFont(.subheadline, weight: .semibold)
                    .foregroundStyle(FleetTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Circle()
                        .fill(candidatesCount > 0 ? FleetTheme.positive : FleetTheme.secondary.opacity(0.6))
                        .frame(width: 6, height: 6)
                    Text(AddMinerScanRadarModel.foundCountText(candidatesCount: candidatesCount))
                        .foregroundStyle(candidatesCount > 0 ? FleetTheme.positive : FleetTheme.secondary)
                    if !checkingLateReplies {
                        Text("· " + AddMinerScanRadarModel.percentText(fraction: progress))
                            .foregroundStyle(FleetTheme.secondary)
                    }
                }
                .fleetFont(.caption, design: .monospaced)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityIdentifier("addMiner.discoveryProgress")

            if let onCancel {
                Button("Cancel", action: onCancel)
                    .fleetFont(.footnote, weight: .semibold)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("addMiner.discoveryCancel")
            }
        }
    }

    // MARK: - Radar Visual

    @ViewBuilder
    private var radarVisual: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(
                    FleetTheme.separator.opacity(0.4),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )

            // Inner radar grid rings
            Circle()
                .stroke(FleetTheme.accent.opacity(0.12), lineWidth: 1)
                .frame(width: radarSize * 0.65, height: radarSize * 0.65)

            Circle()
                .stroke(FleetTheme.accent.opacity(0.08), lineWidth: 1)
                .frame(width: radarSize * 0.35, height: radarSize * 0.35)

            // Radar sweep (active only when scanning and motion not reduced)
            if isScanning && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isScanning)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(startDate)
                    // 1 revolution every 2.4 seconds
                    let angle = Angle.degrees((elapsed * (360.0 / 2.4)).truncatingRemainder(dividingBy: 360.0))
                    radarSweepCone
                        .rotationEffect(angle)
                }
                .clipShape(Circle())
            }

            // Outer progress ring (trim animated with easeOut on progress changes)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    FleetTheme.accent,
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: progress)

            // Center beacon dot
            Circle()
                .fill(candidatesCount > 0 ? FleetTheme.positive : FleetTheme.accent)
                .frame(width: 6, height: 6)
        }
    }

    /// Sweeping radar cone with fading tail (angular gradient)
    private var radarSweepCone: some View {
        AngularGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.65),
                .init(color: FleetTheme.accent.opacity(0.08), location: 0.8),
                .init(color: FleetTheme.accent.opacity(0.35), location: 0.99),
                .init(color: .clear, location: 1.0)
            ],
            center: .center
        )
    }
}

/// Full-screen scan shown while discovery runs. It takes over the Add Miner sheet so the
/// scan has the whole display, lists miners as they answer, and dismisses itself when the
/// scan finishes so the person lands on the regular results list with Add/Add all.
struct AddMinerFullScreenScan: View {
    let probedHosts: Int
    let hostCount: Int
    let candidates: [MinerDiscoveryCandidate]
    let onCancel: () -> Void

    @AppStorage("addMiner.discoveryDesignStyle") private var selectedStyle: MinerDiscoveryDesignStyle = .sonarGrid

    var body: some View {
        VStack(spacing: 0) {
            // Live Style Switcher
            VStack(spacing: 4) {
                Picker("Discovery Style", selection: $selectedStyle) {
                    ForEach(MinerDiscoveryDesignStyle.allCases) { style in
                        Label(style.rawValue, systemImage: style.iconName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text(selectedStyle.subtitle)
                    .fleetFont(.caption2, design: .monospaced)
                    .foregroundStyle(FleetTheme.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(FleetTheme.surface)

            ZStack {
                switch selectedStyle {
                case .sonarGrid:
                    SonarGridScanView(
                        probedHosts: probedHosts,
                        hostCount: hostCount,
                        candidates: candidates,
                        onCancel: onCancel
                    )
                case .airDrop:
                    AirDropFleetScanView(
                        probedHosts: probedHosts,
                        hostCount: hostCount,
                        candidates: candidates,
                        onCancel: onCancel
                    )
                case .unifiedSheet:
                    UnifiedSheetScanView(
                        probedHosts: probedHosts,
                        hostCount: hostCount,
                        candidates: candidates,
                        onCancel: onCancel
                    )
                }
            }
            .animation(.easeInOut(duration: 0.25), value: selectedStyle)
        }
        .background(FleetTheme.canvas.ignoresSafeArea())
        .accessibilityIdentifier("addMiner.fullScreenScan")
    }

    /// Deterministic per-address seed (Swift's `hashValue` is randomized per launch).
    static func stableSeed(_ address: String) -> Int {
        address.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    }
}
