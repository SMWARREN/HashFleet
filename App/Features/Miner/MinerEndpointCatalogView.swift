import SwiftUI
import HashFleetCore

struct MinerEndpointCatalogView: View {
    let device: MinerDevice
    @Bindable var store: FleetStore
    var insights: MiningInsightsStore?
    @State private var search = ""

    private var navigationIdentity: MinerNavigationIdentity {
        let context = MinerMiningContext.resolve(info: store.snapshot(for: device.id)?.info)
        let coin = context.pool?.coin
        return MinerNavigationIdentity(
            deviceName: device.name,
            poolName: context.pool == nil ? nil : context.providerLabel,
            coin: coin,
            market: coin.flatMap { insights?.coinMarkets[$0] }
        )
    }

    private var endpoints: [MinerEndpoint] {
        MinerEndpoint.catalog.filter {
            search.isEmpty || "\($0.title) \($0.path) \($0.method)".localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        FleetSettingsList {
            FleetSettingsSection {
                Label("Firmware-dependent capabilities", systemImage: "info.circle")
                Text(
                    "This catalog includes the upstream API and source-registered extensions. "
                        + "Listing an endpoint does not mean your firmware supports it. "
                        + "HTTP errors are shown without substituting another operation."
                )
                .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                if store.isDemo {
                    Label("Demo mode never contacts a miner or executes writes.", systemImage: "lock.fill")
                        .fleetFont(.footnote)
                }
            }
            .listRowBackground(FleetTheme.surface)
            if !writeEndpoints.isEmpty {
                FleetSettingsSection(surface: FleetTheme.accent.opacity(0.10)) {
                    Label("Writes always require exact review.", systemImage: "exclamationmark.triangle.fill")
                        .fleetFont(.headline)
                        .foregroundStyle(FleetTheme.accent)
                    Text("Use with care. Incorrect requests can change miner settings.")
                        .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                }
                .listRowBackground(FleetTheme.accent.opacity(0.10))
            }
            // Reads and writes are separated so a destructive operation is never one row
            // away from a harmless one. Every endpoint in the catalog is still listed.
            if !readEndpoints.isEmpty {
                FleetSettingsSection("Read endpoints · \(readEndpoints.count)") {
                    ForEach(readEndpoints) { endpointRow($0) }
                }
                .listRowBackground(FleetTheme.surface)
            }
            if !writeEndpoints.isEmpty {
                FleetSettingsSection("Write endpoints · \(writeEndpoints.count)") {
                    ForEach(writeEndpoints) { endpointRow($0) }
                }
                .listRowBackground(FleetTheme.surface)
            }
            FleetSettingsSection(surface: nil) {
                Text("\(endpoints.count) operations")
                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Endpoint explorer")
        .searchable(
            text: $search,
            placement: FleetToolbarLocation.search,
            prompt: "Find path or operation"
        )
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .toolbar {
            ToolbarItem(placement: .principal) {
                MinerNavigationTitle(pageTitle: "Endpoint explorer")
            }
        }
        .environment(\.minerNavigationIdentity, navigationIdentity)
    }

    private var readEndpoints: [MinerEndpoint] { endpoints.filter { !$0.isDestructive } }
    private var writeEndpoints: [MinerEndpoint] { endpoints.filter(\.isDestructive) }

    @ViewBuilder
    private func endpointRow(_ endpoint: MinerEndpoint) -> some View {
        if endpoint.isWebSocket {
            NavigationLink {
                MinerLiveView(
                    device: device,
                    isDemo: store.isDemo,
                    initialEndpoint: endpoint,
                    navigationIdentity: navigationIdentity
                )
            } label: {
                endpointLabel(endpoint)
            }
        } else {
            NavigationLink {
                MinerEndpointView(device: device, store: store, endpoint: endpoint, insights: insights)
            } label: {
                endpointLabel(endpoint)
            }
        }
    }

    private func endpointLabel(_ endpoint: MinerEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(endpoint.method).font(FleetTheme.mono(10)).foregroundStyle(
                    endpoint.isDestructive ? FleetTheme.accent : FleetTheme.positive
                )
                .fleetPillPadding().background(FleetTheme.canvas, in: Capsule())
                Text(endpoint.title).fleetFont(.headline)
            }
            Text(endpoint.path).font(FleetTheme.mono()).foregroundStyle(FleetTheme.secondary)
            if !store.isDemo, let report = store.capabilities.reports[device.id],
                let status = checkedStatus(endpoint, report: report) {
                Text("Detected: \(status.friendlyTitle)").fleetFont(.caption2).foregroundStyle(status.tint)
                Text(report.checkedAt, format: .dateTime.month().day().hour().minute())
                    .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            } else if !store.isDemo, store.capabilities.reports[device.id]?.infoStatus == .supported {
                Text("Detected ESP-Miner-compatible API · support unverified").fleetFont(.caption2).foregroundStyle(
                    FleetTheme.secondary
                )
            } else {
                Text(
                    endpoint.isLegacy
                        ? "Legacy-only endpoint · may return HTTP 404" : "Support: unverified on this firmware"
                ).fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            }
        }.padding(.vertical, 4)
    }

    private func checkedStatus(_ endpoint: MinerEndpoint, report: MinerCapabilityReport) -> MinerProbeStatus? {
        switch endpoint {
        case .info: report.infoStatus
        case .asic: report.asicStatus
        default: nil  // A successful read never establishes write or other endpoint support.
        }
    }
}

#Preview("Endpoint explorer · demo") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.endpoint-catalog-preview")!)
    store.loadDemo()
    return NavigationStack {
        MinerEndpointCatalogView(device: store.devices[0], store: store)
    }
}

/// Shared validation and formatting keeps every mutation on the same review path.
enum MinerRequestSafety {
    static let maximumUploadBytes = 16 * 1_024 * 1_024

    static func jsonData(_ text: String) throws -> Data {
        let data = Data(text.utf8)
        guard data.count <= 256 * 1_024 else {
            throw MinerToolError.message("JSON is limited to 256 KiB. Use the binary importer for OTA images.")
        }
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? [String: Any], !object.isEmpty else {
            throw MinerToolError.message("Enter a non-empty JSON object. Only the fields you include will be sent.")
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func pretty(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            ),
            let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? "Binary response: \(data.count.formatted()) bytes"
    }

    static func reviewedBody(_ data: Data?) -> String {
        guard let data else { return "No request body" }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return "Raw binary image · \(data.count.formatted()) bytes"
        }
        return JSONRedactor.prettyString(from: data)
    }

    static func isWrite(_ endpoint: MinerEndpoint) -> Bool {
        endpoint.isDestructive || !["GET", "OPTIONS"].contains(endpoint.method.uppercased())
    }

    static func isHighRisk(_ endpoint: MinerEndpoint, data: Data?) -> Bool {
        if [.otaFirmware, .otaWWW, .boot].contains(endpoint) { return true }
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        func containsHardwareField(_ value: Any) -> Bool {
            if let fields = value as? [String: Any] {
                return fields.contains { key, nested in
                    let field = key.lowercased()
                    let isHardware =
                        field != "statsfrequency"
                        && ["corevoltage", "frequency", "overheat", "overclock", "fanspeed", "temptarget"].contains {
                            field.contains($0)
                        }
                    return isHardware || containsHardwareField(nested)
                }
            }
            if let values = value as? [Any] { return values.contains(where: containsHardwareField) }
            return false
        }
        return containsHardwareField(object)
    }

    static func coreVoltage(in data: Data?) -> Double? {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) else { return nil }

        func find(_ value: Any) -> Double? {
            if let fields = value as? [String: Any] {
                if let number = fields.first(where: { $0.key.lowercased() == "corevoltage" })?.value,
                    let value = number as? NSNumber {
                    return value.doubleValue
                }
                for nested in fields.values {
                    if let value = find(nested) { return value }
                }
            } else if let values = value as? [Any] {
                for nested in values {
                    if let value = find(nested) { return value }
                }
            }
            return nil
        }

        return find(object)
    }
}

enum MinerToolError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}

struct PendingMinerWrite: Identifiable {
    let id = UUID()
    let endpoint: MinerEndpoint
    let body: Data?
    let query: [URLQueryItem]
    let filename: String?
    var highRisk: Bool { MinerRequestSafety.isHighRisk(endpoint, data: body) }
}

struct MinerWriteConfirmation: View {
    let device: MinerDevice
    let request: PendingMinerWrite
    let isDemo: Bool
    var isOffline: Bool = false
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var tokenFocused: Bool
    @State private var confirmation = ""
    @State private var understood = false
    @State private var submitted = false

    private var canConfirm: Bool {
        !submitted && !isDemo && !isOffline && understood && confirmation == "APPLY"
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                FleetSettingsForm {
                    FleetSettingsSection {
                        Label("Review", systemImage: "wrench.and.screwdriver.fill")
                            .fleetFont(.caption, weight: .semibold)
                            .foregroundStyle(FleetTheme.secondary)
                            .accessibilityIdentifier("confirmation.advancedBadge")
                        Label(
                            request.highRisk ? "High-risk device change" : "Confirm device change",
                            systemImage: request.highRisk ? "exclamationmark.triangle.fill" : "hand.raised.fill"
                        )
                        .fleetFont(.headline).foregroundStyle(FleetTheme.accent)
                        Text(
                            "You are about to send \(request.endpoint.method) to \(device.name) "
                            + "at \(device.address). This is a real device operation, not a preview."
                        )
                        Text(
                            "Nothing is sent while you edit this screen. Review the target, method and payload, "
                                + "then type APPLY to authorize this one request."
                        )
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                        Text(
                            request.highRisk
                                ? ("Voltage, cooling, clock, boot and firmware changes can stop mining, "
                                    + "overheat hardware or leave the device unbootable. Verify the exact board "
                                    + "and firmware image. Keep power and Wi-Fi stable. The app cannot verify "
                                    + "electrical safety or image compatibility.")
                                : ("This may interrupt mining, change persisted configuration or affect connectivity. "
                                    + "The app cannot automatically undo this operation.")
                        )
                        .fleetFont(.footnote)
                    }
                    .listRowBackground(FleetTheme.surface)
                    FleetSettingsSection("Exact request") {
                        Text("\(request.endpoint.method) \(request.endpoint.path)").fleetFont(.caption, design: .monospaced).textSelection(.enabled)
                        ForEach(Array(request.query.enumerated()), id: \.offset) { _, item in
                            LabeledContent("Query: \(item.name)", value: item.value ?? "")
                                .fleetFont(.caption, design: .monospaced)
                        }
                        if let filename = request.filename { LabeledContent("File", value: filename) }
                        Text(MinerRequestSafety.reviewedBody(request.body)).fleetFont(.caption, design: .monospaced).textSelection(.enabled)
                    }
                    .listRowBackground(FleetTheme.surface)
                    FleetSettingsSection {
                        Toggle("I reviewed the target, payload and risks", isOn: $understood).accessibilityIdentifier(
                            "confirmation.understood"
                        )
                        TextField("Type APPLY to authorize", text: $confirmation).textInputAutocapitalization(
                            .characters
                        ).autocorrectionDisabled().accessibilityIdentifier("confirmation.token")
                            .focused($tokenFocused)
                            .submitLabel(.done)
                            .onSubmit { tokenFocused = false }
                        Button(
                            "Send confirmed request",
                            role: .destructive
                        ) {
                            guard canConfirm else { return }
                            submitted = true
                            dismiss()
                            onConfirm()
                        }.disabled(!canConfirm)
                            .accessibilityIdentifier("confirmation.apply")
                            .id("confirmation.sendAction")
                        if isDemo { Text("Writes are locked in demo mode.").foregroundStyle(FleetTheme.secondary) }
                        if isOffline {
                            Text("Miner offline or stale. Reconnect before applying changes.").foregroundStyle(
                                FleetTheme.warning
                            )
                        }
                    }
                    .listRowBackground(FleetTheme.surface)
                }
                .scrollContentBackground(.hidden)
                .background(FleetTheme.canvas)
                .navigationTitle("Review before sending")
                .scrollDismissesKeyboard(.interactively)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        MinerNavigationTitle(pageTitle: "Review before sending")
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .tint(FleetTheme.accent)
                .task(id: confirmation == "APPLY") {
                    guard confirmation == "APPLY" else { return }
                    tokenFocused = false
                    do {
                        try await Task.sleep(for: .milliseconds(300))
                        try Task.checkCancellation()
                        guard confirmation == "APPLY", !tokenFocused else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            proxy.scrollTo("confirmation.sendAction", anchor: .bottom)
                        }
                    } catch { /* Editing or dismissing cancels the pending scroll. */  }
                }
            }
        }
        .presentationBackground(FleetTheme.canvas)
        .interactiveDismissDisabled(understood)
    }
}
