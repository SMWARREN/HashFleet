import SwiftUI
import Observation
import HashFleetCore

struct MinerLiveFrame: Identifiable {
    let id = UUID()
    let receivedAt = Date()
    let text: String
}

@Observable @MainActor
final class MinerLiveModel {
    var frames: [MinerLiveFrame] = []
    var latestFields: [String: JSONValue] = [:]
    var isConnected = false
    var status = "Disconnected"
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func connect(
        device: MinerDevice,
        endpoint: MinerEndpoint,
        isDemo: Bool
    ) {
        disconnect()
        guard !isDemo else {
            status =
                "Demo mode: no socket opened."
                + " Connect a real miner to receive live data."
            return
        }
        let generation = UUID()
        self.generation = generation
        latestFields = [:]
        status = "Connecting\u{2026}"
        isConnected = true
        task = Task { [weak self] in
            await self?.receiveLoop(
                device: device,
                endpoint: endpoint,
                generation: generation
            )
        }
    }

    private func receiveLoop(
        device: MinerDevice,
        endpoint: MinerEndpoint,
        generation: UUID
    ) async {
        do {
            let stream = try MinerAPIClient(
                device: device
            ).webSocketStream(endpoint)
            for try await message in stream {
                try Task.checkCancellation()
                guard self.generation == generation
                else { return }
                handleMessage(
                    message,
                    endpoint: endpoint
                )
            }
            guard self.generation == generation
            else { return }
            status = "Stream closed by device"
            isConnected = false
            task = nil
        } catch {
            guard self.generation == generation
            else { return }
            status =
                Task.isCancelled
                ? "Disconnected"
                : "Connection failed:"
                    + " \(error.localizedDescription)."
                    + " This firmware may not support"
                    + " this stream."
            isConnected = false
            task = nil
        }
    }

    private func handleMessage(
        _ message: MinerWebSocketMessage,
        endpoint: MinerEndpoint
    ) {
        let data = message.data
        status = "Receiving \u{00B7} \(endpoint.path)"
        let text = MinerRequestSafety.pretty(data)
        frames.append(
            MinerLiveFrame(
                text: String(text.prefix(16_000))
            )
        )
        if frames.count > 200 {
            frames.removeFirst(frames.count - 200)
        }
        if endpoint == .liveWebSocket,
            let object = try? JSONDecoder().decode(
                JSONValue.self,
                from: data
            ).objectValue,
            let update = object["data"]?.objectValue {
            latestFields = JSONValue.object(
                latestFields
            ).merging(update)
        }
    }

    func disconnect() {
        generation = UUID()
        task?.cancel()
        task = nil
        isConnected = false
        status = "Disconnected"
    }

    func clear() { frames.removeAll(keepingCapacity: true) }
}

struct MinerLiveView: View {
    let device: MinerDevice
    let isDemo: Bool
    let navigationIdentity: MinerNavigationIdentity?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var endpoint: MinerEndpoint
    @State private var model = MinerLiveModel()

    init(
        device: MinerDevice,
        isDemo: Bool,
        initialEndpoint: MinerEndpoint = .liveWebSocket,
        navigationIdentity: MinerNavigationIdentity? = nil
    ) {
        self.device = device
        self.isDemo = isDemo
        self.navigationIdentity = navigationIdentity
        _endpoint = State(initialValue: initialEndpoint)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    FleetSectionLabel(
                        title: "Live console",
                        subtitle: device.address
                    )
                    Picker("Stream", selection: $endpoint) {
                        Text("Telemetry")
                            .tag(MinerEndpoint.liveWebSocket)
                        Text("Logs")
                            .tag(MinerEndpoint.logWebSocket)
                    }.pickerStyle(.segmented)
                    Text(endpoint.path)
                        .font(FleetTheme.mono(12))
                        .textSelection(.enabled)
                    Label(
                        model.status,
                        systemImage: model.isConnected
                            ? "dot.radiowaves.left.and.right"
                            : "network.slash"
                    )
                    .fleetFont(.footnote)
                    .foregroundStyle(
                        model.isConnected
                            ? FleetTheme.positive
                            : FleetTheme.secondary
                    )
                    HStack {
                        Button(
                            model.isConnected
                                ? "Disconnect" : "Connect",
                            systemImage: model.isConnected
                                ? "stop.circle"
                                : "play.circle"
                        ) {
                            if model.isConnected {
                                model.disconnect()
                            } else {
                                model.connect(
                                    device: device,
                                    endpoint: endpoint,
                                    isDemo: isDemo
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(FleetTheme.buttonInk)
                        .disabled(isDemo)
                        Button("Clear", systemImage: "trash") {
                            model.clear()
                        }.buttonStyle(.bordered)
                        Spacer()
                    }
                    Text(
                        isDemo
                            ? "Demo mode does not open WebSocket"
                                + " connections."
                            : "Read-only stream. Availability"
                                + " depends on firmware. The connection"
                                + " closes when this view disappears"
                                + " or the app becomes inactive."
                                + " Reconnect manually when you return."
                    )
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                }.fleetCard()
                if endpoint == .liveWebSocket,
                    !model.latestFields.isEmpty {
                    telemetry
                }
                HStack {
                    Text("RECENT FRAMES")
                        .font(FleetTheme.mono())
                        .tracking(1.5)
                    Spacer()
                    let frameCountText =
                        "\(model.frames.count) / 200"
                    Text(frameCountText)
                        .font(FleetTheme.mono())
                        .monospacedDigit()
                        .fleetNumericUpdate(
                            frameCountText,
                            reduceMotion: reduceMotion
                        )
                }.foregroundStyle(FleetTheme.secondary)
                if model.frames.isEmpty {
                    ContentUnavailableView(
                        "No frames yet",
                        systemImage: "waveform.path",
                        description: Text(
                            "Choose a stream and connect."
                                + " No messages are sent to change"
                                + " miner settings."
                        )
                    )
                } else {
                    LazyVStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(
                            model.frames.reversed()
                        ) { frame in
                            VStack(
                                alignment: .leading,
                                spacing: 8
                            ) {
                                Text(
                                    frame.receivedAt,
                                    format: .dateTime
                                        .hour().minute()
                                        .second()
                                )
                                .font(FleetTheme.mono(10))
                                .foregroundStyle(
                                    FleetTheme.panelSecondary
                                )
                                Text(frame.text)
                                    .fleetFont(.caption, design: .monospaced)
                                    .foregroundStyle(
                                        FleetTheme.panelInk
                                    )
                                    .textSelection(.enabled)
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .fleetCard(
                                padding: 14,
                                fill: FleetTheme.charcoal
                            )
                        }
                    }
                    Text(
                        "Newest first. Each displayed frame"
                            + " is limited to 16,000 characters"
                            + " and the most recent 200 frames"
                            + " are retained. Use the logs download"
                            + " endpoint for a shareable device"
                            + " log file."
                    )
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                }
            }
            .fleetPageContainer()
        }
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .navigationTitle("Live console")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                MinerNavigationTitle(
                    pageTitle: "Live console"
                )
            }
        }
        .environment(
            \.minerNavigationIdentity,
            navigationIdentity
        )
        .onDisappear { model.disconnect() }
        .onChange(of: endpoint) { _, _ in
            model.disconnect()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.disconnect() }
        }
        .onChange(of: isDemo) { _, demo in
            if demo { model.disconnect() }
        }
    }

    private var telemetry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MERGED TELEMETRY DIFFS")
                .font(FleetTheme.mono())
                .foregroundStyle(FleetTheme.secondary)
            let telemetryKeys = [
                "hashRate", "power", "temp",
                "fanspeed", "sharesAccepted"
            ]
            ForEach(telemetryKeys, id: \.self) { key in
                if let value = model.latestFields[key] {
                    let text =
                        (try? value.prettyPrinted())
                        ?? "Unknown"
                    LabeledContent(key) {
                        Text(text)
                            .monospacedDigit()
                            .fleetNumericUpdate(
                                text,
                                reduceMotion: reduceMotion
                            )
                    }
                    .fleetFont(.callout, design: .monospaced)
                }
            }
            Text(
                "Only fields received in this connection"
                    + " are shown. A live diff is not a"
                    + " complete system snapshot."
            )
            .fleetFont(.caption)
            .foregroundStyle(FleetTheme.secondary)
        }.fleetCard()
    }
}

#Preview("Live console \u{00B7} demo") {
    let store = FleetStore(
        defaults: UserDefaults(
            suiteName: "app.hashfleet.live-preview"
        )!
    )
    store.loadDemo()
    return NavigationStack {
        MinerLiveView(
            device: store.devices[0],
            isDemo: true
        )
    }
}
