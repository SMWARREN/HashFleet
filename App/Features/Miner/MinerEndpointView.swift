import SwiftUI
import UniformTypeIdentifiers
import Observation
import HashFleetCore

struct MinerCompletionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let didWrite: Bool

    init(title: String, message: String, didWrite: Bool = false) {
        self.title = title
        self.message = message
        self.didWrite = didWrite
    }
}

struct MinerEndpointView: View {
    let device: MinerDevice
    @Bindable var store: FleetStore
    let endpoint: MinerEndpoint
    var insights: MiningInsightsStore?
    let onWriteCompleted: (() -> Void)?
    @State var model = MinerOperationModel()
    @State var jsonText: String
    @State var columns = ""
    @State var extraQuery = ""
    @State var poolSlot: Int
    @State var selectedData: Data?
    @State var selectedFilename: String?
    @State var importing = false
    @State private(set) var pending: PendingMinerWrite?
    @State private var confirmedRequest: PendingMinerWrite?
    @State private var isSendingWrite = false
    @State var completionAlert: MinerCompletionAlert?
    enum EditingField { case columns, query, json }
    @FocusState private var editingField: EditingField?
    var editingFocus: FocusState<EditingField?>.Binding { $editingField }

    var canWrite: Bool {
        MinerWriteAvailability.allows(
            store.snapshot(for: device.id), device: device,
            currentDevices: store.visibleDevices, isDemo: store.isDemo
        )
    }

    var simpleCommandEffect: String? {
        guard store.preferences.dashboardMode == .essentials, MinerRequestSafety.isWrite(endpoint) else { return nil }
        return endpoint.plainCommandEffect
    }

    init(
        device: MinerDevice,
        store: FleetStore,
        endpoint: MinerEndpoint,
        initialJSON: String? = nil,
        insights: MiningInsightsStore? = nil,
        onWriteCompleted: (() -> Void)? = nil
    ) {
        self.device = device
        self.store = store
        self.endpoint = endpoint
        self.insights = insights
        self.onWriteCompleted = onWriteCompleted
        _jsonText = State(initialValue: initialJSON ?? Self.template(for: endpoint))
        switch endpoint {
        case .updatePool(let slot), .deletePool(let slot):
            _poolSlot = State(initialValue: slot)
        default:
            _poolSlot = State(initialValue: 0)
        }
    }

    var resolvedEndpoint: MinerEndpoint {
        switch endpoint {
        case .updatePool: return .updatePool(poolSlot)
        case .deletePool: return .deletePool(poolSlot)
        default: return endpoint
        }
    }
    var isBinary: Bool { endpoint == .otaFirmware || endpoint == .otaWWW }
    var needsJSON: Bool {
        switch endpoint {
        case .settings, .boot, .updatePool, .updateTheme: true
        default: false
        }
    }
    var isPool: Bool {
        switch endpoint {
        case .updatePool, .deletePool:
            return true
        default:
            return false
        }
    }

    var navigationIdentity: MinerNavigationIdentity {
        let context = MinerMiningContext.resolve(
            info: store.snapshot(for: device.id)?.info
        )
        let coin = context.pool?.coin
        return MinerNavigationIdentity(
            deviceName: device.name,
            poolName: context.pool == nil ? nil : context.providerLabel,
            coin: coin,
            market: coin.flatMap { insights?.coinMarkets[$0] }
        )
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: MinerSnapshotFreshness.refreshInterval)) { _ in
            timedContent
        }
        // A device write is a modal review, not a second push in the workspace's stack.
        // Keep its presenter outside the periodic telemetry subtree on every platform.
        .sheet(item: $pending, onDismiss: sendAfterReviewDismisses) { request in
            TimelineView(.periodic(from: .now, by: MinerSnapshotFreshness.refreshInterval)) { _ in
                confirmationSheet(request)
            }
        }
        .alert(item: $completionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    if alert.didWrite {
                        onWriteCompleted?()
                    }
                }
            )
        }
        .onDisappear { model.clearExport() }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false,
            onCompletion: importFile
        )
    }

    private var timedContent: some View {
        FleetSettingsForm {
            overview
            if !store.isDemo && !canWrite {
                FleetSettingsSection { MinerOfflineSettingsNotice(snapshot: store.snapshot(for: device.id)) }
            }
            if isPool { poolSection }
            if endpoint == .statistics { statisticsSection }
            if !isBinary { querySection }
            if needsJSON { jsonSection }
            if isBinary { binarySection }
            FleetSettingsSection {
                Button(action: prepare) {
                    HStack {
                        Label(
                            simpleCommandEffect != nil ? "Review \(endpoint.title.lowercased())…" :
                                (MinerRequestSafety.isWrite(endpoint) ? "Review request…" : "Send read request"),
                            systemImage: MinerRequestSafety.isWrite(endpoint) ? "hand.raised" : "arrow.down.circle"
                        )
                        Spacer()
                        if model.isRunning { ProgressView() }
                    }
                }.disabled(model.isRunning || isSendingWrite || confirmedRequest != nil
                    || (!canWrite && MinerRequestSafety.isWrite(endpoint)))
                    .accessibilityIdentifier("endpoint.send")
                if store.isDemo {
                    Text("Demo mode: writes are locked and explorer requests never contact a device.")
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                }
                if model.isRunning && isBinary {
                    Text(
                        "Uploading raw image. Keep this screen open, remain on Wi-Fi and do not "
                            + "disconnect miner power. A firmware update can take several minutes."
                    )
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.warning)
                }
            }
            .listRowBackground(FleetTheme.surface)
            resultSection
        }
        .fleetRevealEditingField(editingField)
        .navigationTitle(endpoint.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSendingWrite)
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .fleetEditingDone(editingField != nil, identifier: "endpoint.keyboardDone") { editingField = nil }
        .toolbar {
            ToolbarItem(placement: .principal) {
                MinerNavigationTitle(pageTitle: endpoint.title)
            }
        }
        .environment(\.minerNavigationIdentity, navigationIdentity)
    }

    func confirmationSheet(_ request: PendingMinerWrite) -> some View {
        MinerWriteConfirmation(
            device: device,
            request: request,
            isDemo: store.isDemo,
            isOffline: !canWrite,
        ) {
            guard pending?.id == request.id, confirmedRequest == nil, canWrite else { return }
            confirmedRequest = request
            pending = nil
        }
        .environment(\.minerNavigationIdentity, navigationIdentity)
    }

    func sendAfterReviewDismisses() {
        // Cancel and interactive dismissal never stage an authorized request. A confirmed
        // request is consumed once and the lower-level write service rechecks availability.
        guard let request = confirmedRequest else { return }
        isSendingWrite = true
        confirmedRequest = nil
        Task {
            defer { isSendingWrite = false }
            await run(request.endpoint, body: request.body, query: request.query)
        }
    }

    func prepare() {
        guard pending == nil, confirmedRequest == nil, !isSendingWrite, !model.isRunning else { return }
        do {
            let query = try queryItems()
            let body: Data?
            if isBinary {
                guard let data = selectedData, !data.isEmpty else {
                    throw MinerToolError.message("Choose a valid .bin file first.")
                }
                body = data
            } else if needsJSON {
                body = try MinerRequestSafety.jsonData(jsonText)
            } else {
                body = nil
            }
            if MinerRequestSafety.isWrite(resolvedEndpoint) {
                guard !store.isDemo else {
                    throw MinerToolError.message("Writes are disabled in demo mode.")
                }
                guard canWrite else {
                    throw MinerToolError.message(
                        "Offline settings are read only. Reconnect and refresh first."
                    )
                }
                editingField = nil
                pending = PendingMinerWrite(
                    endpoint: resolvedEndpoint,
                    body: body,
                    query: query,
                    filename: selectedFilename,
                    opensExactRequest: store.preferences.dashboardMode == .full
                )
            } else {
                Task { await run(resolvedEndpoint, body: body, query: query) }
            }
        } catch { model.error = error.localizedDescription }
    }

    func run(_ endpoint: MinerEndpoint, body: Data?, query: [URLQueryItem]) async {
        let isWrite = MinerRequestSafety.isWrite(endpoint)
        await model.execute(
            device: device,
            endpoint: endpoint,
            body: body,
            query: query,
            isDemo: store.isDemo,
            writeAuthorized: { canWrite }
        )
        guard isWrite else { return }
        let alert: MinerCompletionAlert
        if let failure = model.error {
            alert = MinerCompletionAlert(
                title: "Change not completed",
                message: failure
            )
        } else {
            await store.refresh()
            alert = MinerCompletionAlert(
                title: "Request accepted",
                message: "\(endpoint.title) was accepted by \(device.name). The latest miner readings were refreshed; verify the requested values before treating the change as applied.",
                didWrite: true
            )
        }
        // The native review is already dismissed, even for a fast request or error.
        completionAlert = alert
    }

    func queryItems(columns: String? = nil, extraQuery: String? = nil) throws -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        let columnsVal = (columns ?? self.columns).trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint == .statistics, !columnsVal.isEmpty { items.append(URLQueryItem(name: "columns", value: columnsVal)) }
        let extraQueryVal = extraQuery ?? self.extraQuery
        for line in extraQueryVal.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard parts.count == 2, !name.isEmpty else {
                throw MinerToolError.message("Query parameters must use name=value, one per line.")
            }
            guard !items.contains(where: { $0.name == name }) else {
                throw MinerToolError.message("Duplicate query parameter: \(name)")
            }
            items.append(URLQueryItem(name: name, value: String(parts[1])))
        }
        return items
    }

    func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            guard url.pathExtension.lowercased() == "bin" else {
                throw MinerToolError.message(
                    "Select a raw .bin image. Other file types are not accepted."
                )
            }
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize, size > 0,
                size <= MinerRequestSafety.maximumUploadBytes
            else {
                throw MinerToolError.message("Image must be a nonempty regular file no larger than 16 MiB.")
            }
            let data = try Data(contentsOf: url)
            guard !data.isEmpty, data.count <= MinerRequestSafety.maximumUploadBytes else {
                throw MinerToolError.message("Image size changed or exceeds the 16 MiB limit.")
            }
            selectedData = data
            selectedFilename = url.lastPathComponent
            model.error = nil
        } catch {
            selectedData = nil
            selectedFilename = nil
            model.error = error.localizedDescription
        }
    }
}

#Preview("Endpoint request · demo") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.preview.endpoint")!)
    store.loadDemo()
    return NavigationStack {
        if let device = store.devices.first {
            MinerEndpointView(device: device, store: store, endpoint: .settings, insights: MiningInsightsStore())
        } else {
            ContentUnavailableView("No demo miner", systemImage: "cpu")
        }
    }
}
