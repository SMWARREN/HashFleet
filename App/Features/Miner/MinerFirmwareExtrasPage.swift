import SwiftUI
import HashFleetCore

/// Firmware-specific settings and actions verified in each firmware's source
/// (see `MinerFirmwareExtras`). Each write is preceded by a fresh identity check and
/// followed by a readback. Essentials applies immediately, except changes marked
/// `alwaysConfirm` (overclock, thermal shutdown limits).
struct MinerFirmwareExtrasPage: View {
    let device: MinerDevice
    @Bindable var store: FleetStore

    /// Documents keyed by read path ("" = live info).
    @State private var documents: [String: [String: JSONValue]] = [:]
    @State private var drafts: [String: Int] = [:]
    @State private var pending: Pending?
    @State private var isSending = false
    @State private var message: String?
    @State private var failure: String?

    struct Pending: Identifiable {
        let id = UUID()
        let control: MinerFirmwareExtra?
        let action: MinerFirmwareAction?
        let value: Int
        let title: String
        var detail: String { control?.detail ?? action?.detail ?? "" }
        var risky: Bool { control?.alwaysConfirm == true }
    }

    private var info: MinerInfo? { store.snapshot(for: device.id)?.info }
    private var family: String {
        (device.firmwareFamily ?? info?.raw["firmwareFamily"]?.stringValue ?? "bitaxe").lowercased()
    }
    private var controls: [MinerFirmwareExtra] { MinerFirmwareExtras.controls(for: family) }
    private var actions: [MinerFirmwareAction] {
        MinerFirmwareExtras.actions(for: family).filter { $0.isVisible(in: info?.raw ?? [:]) }
    }
    private var essentials: Bool { store.preferences.dashboardMode == .essentials }

    private func document(for control: MinerFirmwareExtra) -> [String: JSONValue] {
        control.readPath.map { documents[$0] ?? [:] } ?? (info?.raw ?? [:])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Firmware settings")
                    .fleetFont(.title2, weight: .bold)
                    .foregroundStyle(FleetTheme.ink)
                Text("Only settings verified in this firmware are shown. Each change is sent on its own and read back.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .fleetFont(.footnote).foregroundStyle(FleetTheme.positive)
                        .accessibilityIdentifier("extras.result")
                }
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                        .accessibilityIdentifier("extras.error")
                }
                if let title = info?.raw["fault_notice_title"]?.stringValue, actions.contains(where: { $0.id == "faultAck" }) {
                    Label("\(title): \(info?.raw["fault_notice_reason"]?.stringValue ?? "")",
                          systemImage: "exclamationmark.octagon.fill")
                        .fleetFont(.footnote, weight: .semibold).foregroundStyle(FleetTheme.warning)
                }
                ForEach(controls) { control in
                    MinerControlsCard {
                        MinerControlsHeader(title: control.title, subtitle: control.detail, symbol: symbol(control.key))
                        editor(control)
                    }
                }
                ForEach(actions) { action in
                    MinerControlsCard {
                        MinerControlsHeader(title: action.title, subtitle: action.detail, symbol: symbol(action.id))
                        Button(action.title) {
                            request(Pending(control: nil, action: action, value: 0, title: "\(action.title)?"))
                        }
                        .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
                        .accessibilityIdentifier("extras.action.\(action.id)")
                    }
                }
            }
            .disabled(isSending || store.isDemo)
            .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .background(FleetTheme.canvas)
        .navigationTitle("Firmware")
        .task { await loadDocuments() }
        .refreshable { await loadDocuments() }
        .confirmationDialog(
            pending?.title ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { change in
            Button("Apply", role: change.risky ? .destructive : nil) { send(change) }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { change in
            Text(change.detail)
        }
    }

    @ViewBuilder
    private func editor(_ control: MinerFirmwareExtra) -> some View {
        let current = control.currentValue(in: document(for: control))
        switch control.kind {
        case .toggle:
            Toggle(isOn: Binding(
                get: { (current ?? 0) == 1 },
                set: { on in
                    FleetHaptics.light()
                    request(Pending(control: control, action: nil, value: on ? 1 : 0,
                                    title: "\(on ? "Turn on" : "Turn off") \(control.title.lowercased())?"))
                }
            )) {
                Text(current == nil ? "Not reported" : ((current ?? 0) == 1 ? "On" : "Off"))
                    .fleetFont(.subheadline)
            }
            .accessibilityIdentifier("extras.\(control.key)")
        case .choice(let options):
            choicePicker(control, current: current, options: options.map { ($0.value, $0.label) })
        case .textChoice(let options):
            choicePicker(control, current: current, options: options.enumerated().map { ($0.offset, $0.element.label) })
        case .number(let range, let unit):
            let draft = drafts[control.key] ?? current ?? range.lowerBound
            HStack {
                Stepper(value: Binding(get: { draft }, set: {
                    FleetHaptics.light()
                    drafts[control.key] = $0
                }),
                        in: range, step: unit == "W" ? 5 : 1) {
                    Text("\(draft) \(unit)").fleetFont(.subheadline, design: .monospaced)
                }
                .accessibilityIdentifier("extras.\(control.key)")
                Button("Apply") {
                    request(Pending(control: control, action: nil, value: draft,
                                    title: "Set \(control.title.lowercased()) to \(draft) \(unit)?"))
                }
                .buttonStyle(FleetPrimaryButtonStyle(size: .compact))
                .disabled(draft == current)
                .accessibilityIdentifier("extras.\(control.key).apply")
            }
            Text(current.map { "Reported: \($0) \(unit)" } ?? "Not reported")
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
        }
    }

    private func choicePicker(_ control: MinerFirmwareExtra, current: Int?, options: [(Int, String)]) -> some View {
        Picker(control.title, selection: Binding(
            get: { current ?? -1 },
            set: { value in
                guard value != current, let label = options.first(where: { $0.0 == value })?.1 else { return }
                FleetHaptics.light()
                request(Pending(control: control, action: nil, value: value,
                                title: "Set \(control.title.lowercased()) to \(label)?"))
            }
        )) {
            if current == nil { Text("Not reported").tag(-1) }
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("extras.\(control.key)")
    }

    private func symbol(_ key: String) -> String {
        switch key {
        case "overclockEnabled", "overclock": "bolt.fill"
        case "useNTP": "clock"
        case "pidTargetTemp", "overheat_temp", "asic_fan_c", "asic_shutdown_c", "vr_fan_c", "vr_shutdown_c", "unit":
            "thermometer.medium"
        case "flipscreen", "autoscreenoff", "mode": "display"
        case "pcap", "rating_w": "powerplug"
        case "enabled": "chart.bar"
        case "faultAck": "exclamationmark.octagon"
        case "updateCheck": "arrow.down.circle"
        case "retune": "arrow.triangle.2.circlepath"
        default: "dial.medium"
        }
    }

    private func request(_ change: Pending) {
        if essentials && !change.risky {
            send(change)
        } else {
            pending = change
        }
    }

    private var canWrite: Bool {
        !store.isDemo && MinerWriteAvailability.allows(
            store.snapshot(for: device.id), device: device, currentDevices: store.visibleDevices, isDemo: store.isDemo
        )
    }

    private func loadDocuments() async {
        guard !store.isDemo else { return }
        let adapter = MinerFirmwareAdapter(device: device, session: store.session)
        var seen = Set<String>()
        for control in controls {
            guard let path = control.readPath, seen.insert(path).inserted else { continue }
            if let doc = try? await adapter.readExtraDocument(control) { documents[path] = doc }
        }
    }

    private func send(_ change: Pending) {
        pending = nil
        message = nil
        failure = nil
        guard canWrite, let identity = info.flatMap(MinerInlineActionState.identity(from:)) else {
            failure = "Miner offline or stale. Refresh first. Nothing was sent."
            return
        }
        isSending = true
        Task { @MainActor in
            defer { isSending = false }
            let adapter = MinerFirmwareAdapter(device: device, session: store.session)
            do {
                // Fresh identity check right before the write.
                let fresh = try await adapter.info()
                guard MinerInlineActionState.identity(from: fresh) == identity else {
                    failure = "The miner identity changed. Nothing was sent."
                    return
                }
                if let action = change.action {
                    try await adapter.runFirmwareAction(action, live: fresh.raw)
                    _ = await store.refreshAfterWrite(for: device)
                    message = "\(action.title) · sent"
                    return
                }
                guard let control = change.control else { return }
                let doc = control.readPath == nil ? fresh.raw : try await adapter.readExtraDocument(control)
                guard let payload = control.payload(change.value, document: doc) else {
                    failure = "That value is out of range or conflicts with another limit. Nothing was sent."
                    return
                }
                try await adapter.writeExtra(control, payload: payload)
                _ = await store.refreshAfterWrite(for: device)
                await loadDocuments()
                drafts[control.key] = nil
                let readBack = control.currentValue(in: document(for: control))
                message = readBack == change.value
                    ? "\(control.title) set and confirmed"
                    : "\(control.title) sent · readback \(readBack.map(String.init) ?? "not reported")"
            } catch {
                failure = "Not applied: \(error.localizedDescription)"
            }
        }
    }
}
