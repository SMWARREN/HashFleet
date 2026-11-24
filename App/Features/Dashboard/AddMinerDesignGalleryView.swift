//
//  AddMinerDesignGalleryView.swift
//  HashFleet
//
//  Live interactive studio to compare the 3 miner discovery designs:
//  - Option A: Sonar Grid (Tactile ASIC / Cyber Radar)
//  - Option B: AirDrop Fleet (Apple HIG / Orbital Constellation)
//  - Option C: Unified Sheet (Zero-Cover Inline Flow)
//

import SwiftUI
import HashFleetCore

public enum MinerDiscoveryDesignStyle: String, CaseIterable, Identifiable, Sendable {
    case sonarGrid = "Sonar Grid"
    case airDrop = "AirDrop Fleet"
    case unifiedSheet = "Unified Sheet"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .sonarGrid: "scope"
        case .airDrop: "airdrop"
        case .unifiedSheet: "rectangle.stack"
        }
    }

    public var subtitle: String {
        switch self {
        case .sonarGrid: "Tactile ASIC / Flowing Grid"
        case .airDrop: "Apple HIG / Orbital Constellation"
        case .unifiedSheet: "Zero-Cover Inline Sheet"
        }
    }
}

/// Helper to associate mock or discovered miners with their verified coin identities.
extension MinerDiscoveryCandidate {
    var inferredCoin: MiningPoolCoin? {
        if address.contains("201") || address.contains("205") || address.contains("207") { return .btc }
        if address.contains("202") { return .bch }
        if address.contains("203") { return .dgb }
        if address.contains("204") { return .xec }
        if address.contains("206") { return .bc2 }
        if let model = model?.lowercased() {
            if model.contains("bitfortun") { return .btc }
            if model.contains("nerd") { return .dgb }
            if model.contains("warp") { return .xec }
            if model.contains("nano") { return .btc }
        }
        return .btc
    }

    var hardwareChip: String {
        if address.contains("201") || address.contains("202") { return "BM1373" }
        if address.contains("203") { return "BM1368 · 4x" }
        if address.contains("204") { return "BM1370 · 2x" }
        if address.contains("205") { return "BM1370 · Hex" }
        if address.contains("206") { return "BM1370" }
        if address.contains("207") { return "Avalon A10" }
        return "BM13xx"
    }

    var speedEstimate: String {
        if address.contains("201") { return "850 GH/s" }
        if address.contains("202") { return "1.35 TH/s" }
        if address.contains("203") { return "1.20 TH/s" }
        if address.contains("204") { return "1.40 TH/s" }
        if address.contains("205") { return "1.80 TH/s" }
        if address.contains("206") { return "1.07 TH/s" }
        if address.contains("207") { return "540 GH/s" }
        return "1.0 TH/s"
    }
}

// MARK: - Main Design Studio View

public struct AddMinerDesignGalleryView: View {
    @AppStorage("addMiner.discoveryDesignStyle") private var selectedStyle: MinerDiscoveryDesignStyle = .sonarGrid
    @Environment(\.dismiss) private var dismiss

    // Simulated scan state
    @State private var isSimulating = false
    @State private var probedHosts = 0
    @State private var hostCount = 254
    @State private var candidates: [MinerDiscoveryCandidate] = []
    @State private var timerTask: Task<Void, Never>?

    // Seed mock virtual fleet
    private let mockMiners: [MinerDiscoveryCandidate] = [
        MinerDiscoveryCandidate(address: "192.168.86.201", name: "Bitfortun BS-1", model: "Bitfortun BS-1", detectedFamily: "bitfortun"),
        MinerDiscoveryCandidate(address: "192.168.86.202", name: "Bitfortun BS-2", model: "Bitfortun BS-2", detectedFamily: "bitfortun"),
        MinerDiscoveryCandidate(address: "192.168.86.203", name: "NerdQAxe+ Lab", model: "NerdQAxe+", detectedFamily: "nerdqaxe"),
        MinerDiscoveryCandidate(address: "192.168.86.204", name: "WarpAxe Duo", model: "Bitaxe Gamma Duo", detectedFamily: "warpAxe"),
        MinerDiscoveryCandidate(address: "192.168.86.205", name: "AxeForge Hex", model: "Bitaxe Gamma Hex", detectedFamily: "axeForge"),
        MinerDiscoveryCandidate(address: "192.168.86.206", name: "Harlo OS 601", model: "Gamma 601", detectedFamily: "harloOS"),
        MinerDiscoveryCandidate(address: "192.168.86.207:4028", name: "Avalon Nano 3S", model: "Nano 3s", detectedFamily: "canaan")
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Live Style Switcher
                stylePickerHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(FleetTheme.surface)

                // The Selected Active Design
                ZStack {
                    switch selectedStyle {
                    case .sonarGrid:
                        SonarGridScanView(
                            probedHosts: probedHosts,
                            hostCount: hostCount,
                            candidates: candidates,
                            onCancel: { stopSimulation() }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    case .airDrop:
                        AirDropFleetScanView(
                            probedHosts: probedHosts,
                            hostCount: hostCount,
                            candidates: candidates,
                            onCancel: { stopSimulation() }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    case .unifiedSheet:
                        UnifiedSheetScanView(
                            probedHosts: probedHosts,
                            hostCount: hostCount,
                            candidates: candidates,
                            onCancel: { stopSimulation() }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: selectedStyle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom Simulation Control Bar
                simulationControlBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(FleetTheme.surface)
            }
            .navigationTitle("Discovery Design Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        stopSimulation()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if candidates.isEmpty {
                startSimulation()
            }
        }
        .onDisappear {
            stopSimulation()
        }
    }

    private var stylePickerHeader: some View {
        VStack(spacing: 6) {
            Picker("Design Style", selection: $selectedStyle) {
                ForEach(MinerDiscoveryDesignStyle.allCases) { style in
                    Label(style.rawValue, systemImage: style.iconName).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedStyle.subtitle)
                .fleetFont(.caption2, design: .monospaced)
                .foregroundStyle(FleetTheme.secondary)
        }
    }

    private var simulationControlBar: some View {
        HStack(spacing: 12) {
            Button {
                if isSimulating {
                    stopSimulation()
                } else {
                    startSimulation()
                }
            } label: {
                Label(isSimulating ? "Pause Discovery" : "Replay Simulation",
                      systemImage: isSimulating ? "pause.fill" : "play.fill")
                    .fleetFont(.footnote, weight: .semibold)
            }
            .buttonStyle(FleetPrimaryButtonStyle(tone: isSimulating ? .secondary : .accent, size: .compact))

            Button(role: .destructive) {
                resetSimulation()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .fleetFont(.footnote, weight: .semibold)
            }
            .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
        }
    }

    private func startSimulation() {
        stopSimulation()
        isSimulating = true
        probedHosts = 0
        candidates = []

        timerTask = Task { @MainActor in
            var currentProbed = 0
            var minerIndex = 0

            while currentProbed < hostCount && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { break }
                currentProbed = min(hostCount, currentProbed + Int.random(in: 4...12))
                probedHosts = currentProbed

                // Periodically discover a miner
                if minerIndex < mockMiners.count && currentProbed > (minerIndex + 1) * 30 {
                    let newMiner = mockMiners[minerIndex]
                    candidates.append(newMiner)
                    minerIndex += 1
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                }
            }
            isSimulating = false
        }
    }

    private func stopSimulation() {
        timerTask?.cancel()
        timerTask = nil
        isSimulating = false
    }

    private func resetSimulation() {
        stopSimulation()
        probedHosts = 0
        candidates = []
    }
}

// MARK: - Option A: Sonar Grid (Tactile ASIC / Cyber Radar)

public struct SonarGridScanView: View {
    let probedHosts: Int
    let hostCount: Int
    let candidates: [MinerDiscoveryCandidate]
    let onCancel: () -> Void

    @State private var startDate = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        AddMinerScanRadarModel.progressFraction(probedHosts: probedHosts, hostCount: hostCount)
    }

    public var body: some View {
        SWScanningOverlay(gridOpacity: 0.12, bandOpacity: 0.22, speed: 2.0) {
            VStack(spacing: 16) {
                // Header status
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(FleetTheme.positive)
                            .frame(width: 8, height: 8)
                        Text(probedHosts >= hostCount ? "Subnet Sweep Complete" : "Scanning Local Subnet (192.168.86.x)")
                            .fleetFont(.caption, weight: .semibold, design: .monospaced)
                            .foregroundStyle(FleetTheme.ink)
                    }
                    Text(AddMinerScanRadarModel.progressText(probedHosts: probedHosts, hostCount: hostCount) + " · " + AddMinerScanRadarModel.percentText(fraction: progress))
                        .fleetFont(.caption2, design: .monospaced)
                        .foregroundStyle(FleetTheme.secondary)
                }
                .padding(.top, 12)

                // High-Tech Radar View
                ZStack {
                    // Concentric Range Rings with cyan glow
                    ForEach([0.35, 0.65, 0.95], id: \.self) { scale in
                        Circle()
                            .stroke(Color.cyan.opacity(0.18), lineWidth: 1)
                            .scaleEffect(scale)
                    }

                    // Crosshairs
                    Rectangle()
                        .fill(Color.cyan.opacity(0.12))
                        .frame(width: 1, height: 210)
                    Rectangle()
                        .fill(Color.cyan.opacity(0.12))
                        .frame(width: 210, height: 1)

                    // Sweeping radar beam
                    if !reduceMotion {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                            let elapsed = timeline.date.timeIntervalSince(startDate)
                            AngularGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .clear, location: 0.65),
                                    .init(color: Color.cyan.opacity(0.15), location: 0.85),
                                    .init(color: Color.cyan.opacity(0.6), location: 0.99),
                                    .init(color: .clear, location: 1.0)
                                ],
                                center: .center
                            )
                            .rotationEffect(.degrees((elapsed * 130).truncatingRemainder(dividingBy: 360)))
                        }
                        .clipShape(Circle())
                    }

                    // Progress boundary
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.25), value: progress)

                    // Blips for discovered miners with glowing auras
                    ForEach(candidates) { candidate in
                        let seed = AddMinerFullScreenScan.stableSeed(candidate.address)
                        let angle = Double(seed * 137 % 360)
                        let radius = 45.0 + Double(seed * 31 % 45)
                        ZStack {
                            Circle()
                                .fill(FleetTheme.positive.opacity(0.35))
                                .frame(width: 18, height: 18)
                            Circle()
                                .fill(FleetTheme.positive)
                                .frame(width: 9, height: 9)
                        }
                        .offset(x: cos(angle * .pi / 180) * radius, y: sin(angle * .pi / 180) * radius)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }

                    // Central Count Pill
                    VStack(spacing: 2) {
                        Text("\(candidates.count)")
                            .fleetFont(.title, weight: .bold, design: .monospaced)
                            .foregroundStyle(candidates.isEmpty ? FleetTheme.secondary : FleetTheme.positive)
                        Text(candidates.count == 1 ? "MINER" : "MINERS")
                            .fleetFont(.caption2, weight: .bold, design: .monospaced)
                            .foregroundStyle(FleetTheme.secondary)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                }
                .frame(width: 220, height: 220)

                // Discovered Miners Feed
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("DISCOVERED ASICs (\(candidates.count))")
                            .fleetFont(.caption2, weight: .bold, design: .monospaced)
                            .foregroundStyle(FleetTheme.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    if candidates.isEmpty {
                        Text("Listening for broadcast replies from Bitaxe, NerdQAxe, Canaan...")
                            .fleetFont(.footnote)
                            .foregroundStyle(FleetTheme.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(candidates) { candidate in
                                    HStack(spacing: 12) {
                                        // Coin Icon
                                        CoinGeckoIcon(
                                            coin: candidate.inferredCoin,
                                            fallbackTicker: candidate.inferredCoin?.ticker ?? "BTC",
                                            size: 26
                                        )
                                        .frame(width: 26, height: 26)

                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(candidate.name)
                                                    .fleetFont(.subheadline, weight: .semibold)
                                                    .foregroundStyle(FleetTheme.ink)
                                                if let fam = candidate.detectedFamily {
                                                    Text(fam)
                                                        .fleetFont(.caption2, weight: .medium, design: .monospaced)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1)
                                                        .background(FleetTheme.accent.opacity(0.12), in: Capsule())
                                                        .foregroundStyle(FleetTheme.accent)
                                                }
                                            }
                                            HStack(spacing: 6) {
                                                Text(candidate.address)
                                                    .fleetFont(.caption, design: .monospaced)
                                                    .foregroundStyle(FleetTheme.secondary)
                                                Text("·")
                                                    .foregroundStyle(FleetTheme.secondary)
                                                Text(candidate.hardwareChip)
                                                    .fleetFont(.caption2, weight: .medium, design: .monospaced)
                                                    .foregroundStyle(FleetTheme.ink)
                                                Spacer()
                                                Text(candidate.speedEstimate)
                                                    .fleetFont(.caption2, weight: .bold, design: .monospaced)
                                                    .foregroundStyle(FleetTheme.positive)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                                    )
                                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 16)
                            .animation(.spring(duration: 0.35, bounce: 0.25), value: candidates.count)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Action
                Button {
                    onCancel()
                } label: {
                    Text(candidates.isEmpty ? "Cancel Scan" : "Add All Discovered (\(candidates.count))")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(FleetPrimaryButtonStyle(tone: candidates.isEmpty ? .secondary : .accent, size: .compact))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(FleetTheme.canvas.ignoresSafeArea())
    }
}

// MARK: - Option B: AirDrop Fleet (Apple HIG / Orbital Constellation)

public struct AirDropFleetScanView: View {
    let probedHosts: Int
    let hostCount: Int
    let candidates: [MinerDiscoveryCandidate]
    let onCancel: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var selectedCandidate: MinerDiscoveryCandidate?

    public var body: some View {
        VStack(spacing: 0) {
            // AirDrop Constellation Canvas
            ZStack {
                // Expanding Soft Pulse Waves
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(FleetTheme.accent.opacity(0.12 - Double(i) * 0.03), lineWidth: 1.5)
                        .scaleEffect(pulseScale + CGFloat(i) * 0.35)
                        .opacity(2.0 - Double(pulseScale))
                }

                // Center Beacon
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 76, height: 76)
                        .shadow(color: FleetTheme.accent.opacity(0.15), radius: 10)

                    Image(systemName: "wifi")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(FleetTheme.accent)
                }

                // Orbital Discovered Miner Nodes
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, miner in
                    let total = max(candidates.count, 1)
                    let angle = (Double(index) / Double(total)) * 2 * .pi - (.pi / 2)
                    let radius: CGFloat = 120

                    Button {
                        selectedCandidate = miner
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(FleetTheme.raised)
                                    .frame(width: 52, height: 52)
                                    .shadow(color: Color.black.opacity(0.08), radius: 6, y: 3)

                                Circle()
                                    .stroke(selectedCandidate?.id == miner.id ? FleetTheme.accent : FleetTheme.positive, lineWidth: 2)
                                    .frame(width: 52, height: 52)

                                CoinGeckoIcon(
                                    coin: miner.inferredCoin,
                                    fallbackTicker: miner.inferredCoin?.ticker ?? "BTC",
                                    size: 24
                                )
                                .frame(width: 24, height: 24)
                            }

                            Text(miner.name)
                                .fleetFont(.caption2, weight: .bold)
                                .foregroundStyle(FleetTheme.ink)
                                .lineLimit(1)
                                .frame(maxWidth: 80)
                        }
                    }
                    .buttonStyle(.plain)
                    .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 340)
            .padding(.top, 20)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false)) {
                    pulseScale = 1.7
                }
            }

            // Info headline
            VStack(spacing: 4) {
                Text("\(candidates.count) Miners Found Nearby")
                    .fleetFont(.headline, weight: .semibold)
                    .foregroundStyle(FleetTheme.ink)
                Text("Tap any hardware node to inspect specifications.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
            }
            .padding(.vertical, 8)

            Spacer(minLength: 0)

            // Bottom Review Tray
            VStack(spacing: 12) {
                if let selected = selectedCandidate ?? candidates.first {
                    HStack(spacing: 12) {
                        CoinGeckoIcon(coin: selected.inferredCoin, fallbackTicker: "BTC", size: 30)
                            .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.name)
                                .fleetFont(.subheadline, weight: .semibold)
                                .foregroundStyle(FleetTheme.ink)
                            Text("\(selected.address) · \(selected.hardwareChip)")
                                .fleetFont(.caption, design: .monospaced)
                                .foregroundStyle(FleetTheme.secondary)
                        }
                        Spacer()
                        Text(selected.speedEstimate)
                            .fleetFont(.caption, weight: .bold, design: .monospaced)
                            .foregroundStyle(FleetTheme.positive)
                    }
                    .padding(12)
                    .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Button {
                    onCancel()
                } label: {
                    Text(candidates.isEmpty ? "Cancel Scan" : "Add All to Fleet (\(candidates.count))")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(FleetPrimaryButtonStyle(size: .compact))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background(FleetTheme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: -2)
        }
        .background(FleetTheme.canvas.ignoresSafeArea())
    }
}

// MARK: - Option C: Unified Sheet (Zero-Cover Inline Flow)

public struct UnifiedSheetScanView: View {
    let probedHosts: Int
    let hostCount: Int
    let candidates: [MinerDiscoveryCandidate]
    let onCancel: () -> Void

    @State private var isManualExpanded = false
    @State private var manualIP = ""

    private var progress: Double {
        AddMinerScanRadarModel.progressFraction(probedHosts: probedHosts, hostCount: hostCount)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Expanding Discovery Header Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(FleetTheme.accent.opacity(0.2), lineWidth: 3)
                                .frame(width: 42, height: 42)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(FleetTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 42, height: 42)
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(FleetTheme.accent)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scanning Wi-Fi Fleet")
                                .fleetFont(.subheadline, weight: .semibold)
                                .foregroundStyle(FleetTheme.ink)
                            Text("\(probedHosts) of \(hostCount) addresses checked (\(Int(progress * 100))%)")
                                .fleetFont(.caption, design: .monospaced)
                                .foregroundStyle(FleetTheme.secondary)
                        }
                        Spacer()
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(FleetTheme.separator.opacity(0.3))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(FleetTheme.accent)
                                .frame(width: geo.size.width * CGFloat(progress), height: 6)
                                .animation(.easeOut(duration: 0.2), value: progress)
                        }
                    }
                    .frame(height: 6)

                    // Quick Actions inside card
                    HStack(spacing: 10) {
                        Button {
                            onCancel()
                        } label: {
                            Label(candidates.isEmpty ? "Stop Scan" : "Add All (\(candidates.count))",
                                  systemImage: candidates.isEmpty ? "stop.fill" : "plus.circle.fill")
                                .frame(maxWidth: .infinity, minHeight: 24)
                        }
                        .buttonStyle(FleetPrimaryButtonStyle(tone: candidates.isEmpty ? .secondary : .accent, size: .compact))

                        if !candidates.isEmpty {
                            Button(role: .cancel) {
                                onCancel()
                            } label: {
                                Text("Dismiss")
                                    .frame(minHeight: 24)
                            }
                            .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
                        }
                    }
                }
                .padding(14)
                .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(FleetTheme.separator.opacity(0.5), lineWidth: 1)
                )

                // Discovered Miners List
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("COMPATIBLE HARDWARE FOUND")
                            .fleetFont(.caption2, weight: .bold, design: .monospaced)
                            .foregroundStyle(FleetTheme.secondary)
                        Spacer()
                        Text("\(candidates.count) miners")
                            .fleetFont(.caption2, weight: .semibold, design: .monospaced)
                            .foregroundStyle(FleetTheme.positive)
                    }

                    if candidates.isEmpty {
                        Text("Looking for Bitaxe, NerdQAxe, AxeForge, Avalon...")
                            .fleetFont(.footnote)
                            .foregroundStyle(FleetTheme.secondary)
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                    } else {
                        ForEach(candidates) { candidate in
                            HStack(spacing: 12) {
                                CoinGeckoIcon(coin: candidate.inferredCoin, fallbackTicker: "BTC", size: 24)
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.name)
                                        .fleetFont(.subheadline, weight: .semibold)
                                        .foregroundStyle(FleetTheme.ink)
                                    Text("\(candidate.address) · \(candidate.hardwareChip)")
                                        .fleetFont(.caption, design: .monospaced)
                                        .foregroundStyle(FleetTheme.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(FleetTheme.accent)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                // Collapsible Manual Fallback
                DisclosureGroup(isExpanded: $isManualExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter the IP address of an unadvertised miner:")
                            .fleetFont(.footnote)
                            .foregroundStyle(FleetTheme.secondary)
                        TextField("e.g. 192.168.86.240", text: $manualIP)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Add Manually by IP & Port")
                        .fleetFont(.footnote, weight: .semibold)
                        .foregroundStyle(FleetTheme.secondary)
                }
                .padding(.top, 10)
            }
            .padding(16)
        }
        .background(FleetTheme.canvas.ignoresSafeArea())
    }
}
