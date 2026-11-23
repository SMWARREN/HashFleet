import SwiftUI
import HashFleetCore

/// Canaan Avalon controls over the cgminer 4028 API.
///
/// Every control maps to a command documented in Canaan's Avalon API manual (A10 v0.4) or
/// implemented by MinerWatch's verified Canaan driver:
/// - Work mode: `ascset|0,workmode,set,<0-2>` (Nano 3s), falling back to `workmode,<n>` (A10).
///   The original Nano 3 uses `worklevel,set,<n>`.
/// - Fan: `ascset|0,fan-spd,<15-100>`, automatic `fan-spd,-1`.
/// - Frequency: `ascset|0,frequency,<f>:<f>:<f>:<f>-0-0-0`.
/// - Front LED locator: `ascset|0,led,1-1` / `1-0`.
/// - Hash power off: `ascset|0,hashpower,0` (a reboot resumes hashing).
/// Each change is a single reviewed write with a fresh pre-read and identity check.
struct MinerAvalonControlsPage: View {
    let device: MinerDevice
    @Bindable var store: FleetStore

    @State private var fanPercent: Double = 60
    @State private var frequency: String = ""
    @State private var pending: PendingChange?
    @State private var isSending = false
    @State private var message: String?
    @State private var failure: String?
    @State private var loaded = false

    private var info: MinerInfo? { store.snapshot(for: device.id)?.info }
    /// Essentials applies each change immediately. Full mode keeps the confirmation step.
    private var confirmsChanges: Bool { store.preferences.dashboardMode != .essentials }
    private var family: String {
        (device.firmwareFamily ?? info?.raw["firmwareFamily"]?.stringValue ?? "canaan").lowercased()
    }
    private var capabilities: MinerDriverCapabilities { .forFamily(family, info: info) }
    private var isNano3: Bool { family == "canaannano3" }

    struct PendingChange: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let payload: [String: JSONValue]
        let destructive: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(isNano3 ? "Avalon Nano 3" : "Avalon controls")
                    .fleetFont(.title2, weight: .bold)
                    .foregroundStyle(FleetTheme.ink)
                Text(confirmsChanges
                     ? "Each change is sent as one command to the miner's cgminer API after you confirm it. Nothing is sent while you adjust."
                     : "Each change is sent as one command to the miner's cgminer API as soon as you tap it.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .fleetFont(.footnote).foregroundStyle(FleetTheme.positive)
                        .accessibilityIdentifier("avalon.result")
                }
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                        .accessibilityIdentifier("avalon.error")
                }
                if let fault = info?.raw["power_fault"]?.stringValue {
                    Label(fault, systemImage: "bolt.trianglebadge.exclamationmark")
                        .fleetFont(.footnote, weight: .semibold).foregroundStyle(FleetTheme.warning)
                }
                if capabilities.canSetWorkmode { workModeCard }
                if capabilities.canSetFan { fanCard }
                if capabilities.canSetFrequency { frequencyCard }
                if capabilities.canIdentify || capabilities.canShutdown { hardwareCard }
            }
            .disabled(isSending || store.isDemo)
            .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .background(FleetTheme.canvas)
        .navigationTitle("Avalon")
        .onAppear(perform: load)
        .onChange(of: pending?.id) { _, _ in
            if let change = pending, !confirmsChanges { send(change) }
        }
        .confirmationDialog(
            pending?.title ?? "",
            isPresented: Binding(get: { pending != nil && confirmsChanges }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { change in
            Button(change.destructive ? "Send" : "Apply", role: change.destructive ? .destructive : nil) {
                send(change)
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { change in
            Text(change.detail)
        }
    }

    // MARK: Cards

    private var workModeCard: some View {
        let current = info?.raw["workmode"]?.intValue
        return card("Work mode", subtitle: isNano3
                    ? "Work level. Low saves power; High maximises hashrate."
                    : "Performance preset. The new mode applies after the miner restarts.",
                    symbol: "speedometer") {
            Picker("Work mode", selection: Binding(
                get: { current ?? -1 },
                set: { mode in
                    guard mode != current, (0...2).contains(mode) else { return }
                    pending = PendingChange(
                        title: "Set work mode to \(Self.modeName(mode))?",
                        detail: isNano3
                            ? "Sends ascset worklevel,set,\(mode)."
                            : "Sends ascset workmode,set,\(mode). Restart the miner for it to take effect.",
                        payload: ["workmode": .integer(Int64(mode))],
                        destructive: false
                    )
                }
            )) {
                if current == nil { Text("Not reported").tag(-1) }
                ForEach(0...2, id: \.self) { Text(Self.modeName($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("avalon.workmode")
        }
    }

    private var fanCard: some View {
        let reported = info?.raw["fanspeed"]?.intValue
        return card("Fan", subtitle: "Manual speed from \(capabilities.fanMinPct)% to 100%, or automatic.",
                    symbol: "fan") {
            HStack {
                Slider(value: $fanPercent, in: Double(capabilities.fanMinPct)...100, step: 5)
                    .accessibilityIdentifier("avalon.fan")
                Text("\(Int(fanPercent))%")
                    .fleetFont(.subheadline, design: .monospaced)
                    .frame(minWidth: 48, alignment: .trailing)
            }
            if let reported {
                Text("Reported: \(reported)%").fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
            HStack {
                Button("Apply \(Int(fanPercent))%") {
                    pending = PendingChange(
                        title: "Set fan to \(Int(fanPercent))%?",
                        detail: "Sends ascset fan-spd,\(Int(fanPercent)). Automatic fan control turns off.",
                        payload: ["manualFanSpeed": .integer(Int64(fanPercent))], destructive: false
                    )
                }
                .buttonStyle(FleetPrimaryButtonStyle(size: .compact))
                Button("Automatic") {
                    pending = PendingChange(
                        title: "Return fan to automatic?", detail: "Sends ascset fan-spd,-1.",
                        payload: ["autofanspeed": .integer(1)], destructive: false
                    )
                }
                .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
            }
        }
    }

    private var frequencyCard: some View {
        card("Frequency", subtitle: "Chip clock in MHz (200-1195). Higher clocks draw more power and heat.",
             symbol: "waveform.path.ecg") {
            HStack {
                TextField("MHz", text: $frequency)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("avalon.frequency")
                Button("Apply") {
                    guard let mhz = Int(frequency), (200...1195).contains(mhz) else {
                        failure = "Enter a frequency from 200 to 1195 MHz. Nothing was sent."
                        return
                    }
                    pending = PendingChange(
                        title: "Set frequency to \(mhz) MHz?",
                        detail: "Sends ascset frequency,\(mhz):\(mhz):\(mhz):\(mhz)-0-0-0.",
                        payload: ["frequency": .integer(Int64(mhz))], destructive: true
                    )
                }
                .buttonStyle(FleetPrimaryButtonStyle(size: .compact))
            }
            if let reported = info?.raw["frequency"]?.doubleValue {
                Text("Reported: \(Int(reported)) MHz").fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
        }
    }

    private var hardwareCard: some View {
        card("Hardware", subtitle: "Locate the unit or stop hashing without cutting power to the controller.",
             symbol: "cpu") {
            if capabilities.canIdentify {
                HStack {
                    Button("LED on") {
                        pending = PendingChange(title: "Turn the front LED on?", detail: "Sends ascset led,1-1.",
                                                payload: ["led": .integer(1)], destructive: false)
                    }
                    .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
                    .accessibilityIdentifier("avalon.ledOn")
                    Button("LED off") {
                        pending = PendingChange(title: "Turn the front LED off?", detail: "Sends ascset led,1-0.",
                                                payload: ["led": .integer(0)], destructive: false)
                    }
                    .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
                    .accessibilityIdentifier("avalon.ledOff")
                }
            }
            if capabilities.canShutdown {
                Button("Stop hashing (hash power off)") {
                    pending = PendingChange(
                        title: "Turn hash power off?",
                        detail: "Sends ascset hashpower,0. The hash boards stop; the controller and fans stay on. Restart the miner to resume hashing.",
                        payload: ["hashpower": .integer(0)], destructive: true
                    )
                }
                .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
                .accessibilityIdentifier("avalon.hashpowerOff")
            }
        }
    }

    // MARK: Helpers

    static func modeName(_ mode: Int) -> String {
        switch mode {
        case 0: "Low"
        case 1: "Mid"
        default: "High"
        }
    }

    private func card<Content: View>(
        _ title: String, subtitle: String, symbol: String, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        MinerControlsCard {
            MinerControlsHeader(title: title, subtitle: subtitle, symbol: symbol)
            content()
        }
    }

    private func load() {
        guard !loaded, let info else { return }
        loaded = true
        if let pct = info.raw["fanspeed"]?.doubleValue, pct >= 15 { fanPercent = min(100, pct) }
        if let mhz = info.raw["frequency"]?.doubleValue { frequency = String(Int(mhz)) }
    }

    private var canWrite: Bool {
        !store.isDemo && MinerWriteAvailability.allows(
            store.snapshot(for: device.id), device: device, currentDevices: store.visibleDevices, isDemo: store.isDemo
        )
    }

    private func send(_ change: PendingChange) {
        pending = nil
        message = nil
        failure = nil
        guard canWrite, let identity = info.flatMap(MinerInlineActionState.identity(from:)) else {
            failure = "Miner offline or stale. Refresh first. Nothing was sent."
            return
        }
        guard let body = try? JSONEncoder().encode(JSONValue.object(change.payload)) else { return }
        isSending = true
        Task { @MainActor in
            defer { isSending = false }
            let operation = MinerOperationModel(session: store.session)
            await operation.execute(
                device: device, endpoint: .settings, body: body, query: [], isDemo: store.isDemo,
                validatePreflight: { fresh in
                    guard MinerInlineActionState.identity(from: fresh) == identity else {
                        throw MinerToolError.message("The miner identity changed. Nothing was sent.")
                    }
                },
                writeAuthorized: { canWrite }
            )
            if let error = operation.error {
                failure = "Not applied: \(error)"
                return
            }
            _ = await store.refreshAfterWrite(for: device)
            message = "\(change.title.replacingOccurrences(of: "?", with: "")) · sent"
        }
    }
}
