import SwiftUI
import HashFleetCore

/// Firmware-specific settings verified in each firmware's upstream source
/// (see `MinerFirmwareExtras`). Writes go through the family's normal `.settings`
/// path with a fresh pre-read and identity check. Essentials applies immediately,
/// except changes marked `alwaysConfirm` (overclock, overheat cut-off).
struct MinerFirmwareExtrasPage: View {
    let device: MinerDevice
    @Bindable var store: FleetStore

    @State private var settingsDoc: [String: JSONValue] = [:]
    @State private var drafts: [String: Int] = [:]
    @State private var pending: Pending?
    @State private var isSending = false
    @State private var message: String?
    @State private var failure: String?

    struct Pending: Identifiable {
        let id = UUID()
        let control: MinerFirmwareExtra?
        let value: Int
        let title: String
    }

    private var info: MinerInfo? { store.snapshot(for: device.id)?.info }
    private var family: String {
        (device.firmwareFamily ?? info?.raw["firmwareFamily"]?.stringValue ?? "bitaxe").lowercased()
    }
    private var controls: [MinerFirmwareExtra] { MinerFirmwareExtras.controls(for: family) }
    private var essentials: Bool { store.preferences.dashboardMode == .essentials }
    private var raw: [String: JSONValue] {
        MinerFirmwareExtras.readsFromSettingsDocument(family) ? settingsDoc : (info?.raw ?? [:])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Firmware settings")
                    .fleetFont(.title2, weight: .bold)
                    .foregroundStyle(FleetTheme.ink)
                Text("Only settings verified in this firmware's source are shown. Each change is sent on its own and read back.")
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
                ForEach(controls) { control in
                    MinerControlsCard {
                        MinerControlsHeader(title: control.title, subtitle: control.detail, symbol: symbol(control))
                        editor(control)
                    }
                }
                if MinerFirmwareExtras.supportsRetune(family) {
                    MinerControlsCard {
                        MinerControlsHeader(
                            title: "Restart auto-tune",
                            subtitle: "Turns auto-tune on and starts a new search. A full search takes 1-2 hours.",
                            symbol: "arrow.triangle.2.circlepath"
                        )
                        Button("Restart auto-tune") {
                            request(Pending(control: nil, value: 0, title: "Restart auto-tune?"))
                        }
                        .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
                        .accessibilityIdentifier("extras.retune")
                    }
                }
            }
            .disabled(isSending || store.isDemo)
            .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .background(FleetTheme.canvas)
        .navigationTitle("Firmware")
        .task { await loadSettingsDocument() }
        .confirmationDialog(
            pending?.title ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { change in
            Button("Apply", role: change.control?.alwaysConfirm == true ? .destructive : nil) { send(change) }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { change in
            Text(change.control?.detail ?? "Sends POST /api/retune.")
        }
    }

    @ViewBuilder
    private func editor(_ control: MinerFirmwareExtra) -> some View {
        let current = control.currentValue(in: raw)
        switch control.kind {
        case .toggle:
            Toggle(isOn: Binding(
                get: { (current ?? 0) == 1 },
                set: { on in
                    request(Pending(control: control, value: on ? 1 : 0,
                                    title: "\(on ? "Turn on" : "Turn off") \(control.title.lowercased())?"))
                }
            )) {
                Text(current == nil ? "Not reported" : ((current ?? 0) == 1 ? "On" : "Off"))
                    .fleetFont(.subheadline)
            }
            .accessibilityIdentifier("extras.\(control.key)")
        case .choice(let options):
            Picker(control.title, selection: Binding(
                get: { current ?? -1 },
                set: { value in
                    guard value != current, let label = options.first(where: { $0.value == value })?.label else { return }
                    request(Pending(control: control, value: value, title: "Set \(control.title.lowercased()) to \(label)?"))
                }
            )) {
                if current == nil { Text("Not reported").tag(-1) }
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("extras.\(control.key)")
        case .number(let range, let unit):
            let draft = drafts[control.key] ?? current ?? range.lowerBound
            HStack {
                Stepper(value: Binding(get: { draft }, set: { drafts[control.key] = $0 }),
                        in: range, step: unit == "W" ? 5 : 1) {
                    Text("\(draft) \(unit)").fleetFont(.subheadline, design: .monospaced)
                }
                .accessibilityIdentifier("extras.\(control.key)")
                Button("Apply") {
                    request(Pending(control: control, value: draft,
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

    private func symbol(_ control: MinerFirmwareExtra) -> String {
        switch control.key {
        case "overclockEnabled", "overclock": "bolt.fill"
        case "useNTP": "clock"
        case "pidTargetTemp", "overheat_temp": "thermometer.medium"
        case "flipscreen", "autoscreenoff": "display"
        case "pcap": "powerplug"
        default: "dial.medium"
        }
    }

    private func request(_ change: Pending) {
        if essentials && change.control?.alwaysConfirm != true {
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

    private func loadSettingsDocument() async {
        guard MinerFirmwareExtras.readsFromSettingsDocument(family), !store.isDemo else { return }
        let adapter = MinerFirmwareAdapter(device: device, session: store.session)
        if let data = try? await adapter.execute(.asic),
           case .object(let dict)? = try? JSONDecoder().decode(JSONValue.self, from: data) {
            settingsDoc = dict
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
            if change.control == nil {
                do {
                    let adapter = MinerFirmwareAdapter(device: device, session: store.session)
                    _ = try await adapter.retune()
                    message = "Auto-tune restarted"
                } catch {
                    failure = "Not applied: \(error.localizedDescription)"
                }
                return
            }
            guard let control = change.control, let payload = control.payload(change.value),
                  let body = try? JSONEncoder().encode(JSONValue.object(payload)) else {
                failure = "That value is out of range. Nothing was sent."
                return
            }
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
            await loadSettingsDocument()
            drafts[control.key] = nil
            let readBack = control.currentValue(in: raw)
            message = readBack == change.value
                ? "\(control.title) set and confirmed"
                : "\(control.title) sent · readback \(readBack.map(String.init) ?? "not reported")"
        }
    }
}
