import SwiftUI
import HashFleetCore

/// Reviewed XMRig controls. This screen intentionally exposes only pause and resume.
struct XMRigControlView: View {
    let device: MinerDevice
    @Bindable var store: FleetStore

    @State private var pendingAction: Action?
    @State private var isSending = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var now = Date()
    @State private var commandTask: Task<Void, Never>?

    private var snapshot: MinerSnapshot? { store.snapshot(for: device.id) }
    private var isCurrent: Bool { MinerWriteAvailability.allows(snapshot, now: now) }

    static func stateLabel(snapshot: MinerSnapshot?, now: Date) -> String {
        guard MinerWriteAvailability.allows(snapshot, now: now) else { return "Offline or stale · last known state" }
        return snapshot?.info?.miningPaused == true ? "Paused" : "Mining"
    }

    private var canSend: Bool {
        FleetReleaseFeatures.includes(device.kind) && !store.isDemo
            && store.devices.contains { $0.id == device.id && $0.address == device.address && $0.kind == .xmrig }
            && MinerWriteAvailability.allows(snapshot)
    }

    enum Action: String, Identifiable {
        case pause
        case resume

        var id: String { rawValue }
        var title: String { self == .pause ? "Pause mining" : "Resume mining" }
        var symbol: String { self == .pause ? "pause.fill" : "play.fill" }
        var explanation: String {
            self == .pause
                ? "XMRig will stop hashing but the process stays running and can be resumed."
                : "XMRig will resume hashing with its existing local configuration."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("XMRig controller", systemImage: "cpu")
                    .fleetFont(.largeTitle, weight: .bold)
                Text("Hash Fleet sends only XMRig's pause or resume JSON-RPC command. It cannot stop the process, restart the Mac, or rewrite config.json.")
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let info = store.snapshot(for: device.id)?.info {
                    HStack(spacing: 12) {
                        Label(
                            Self.stateLabel(snapshot: snapshot, now: now),
                            systemImage: info.miningPaused ? "pause.circle.fill" : "bolt.circle.fill"
                        )
                        .foregroundStyle(!isCurrent || info.miningPaused ? FleetTheme.warning : FleetTheme.positive)
                        Spacer()
                        Text(FleetFormat.sensor(info, keys: "hashRate", "hashrate")
                            .map { FleetFormat.hashrateWithUnit($0) } ?? "Not reported")
                            .font(FleetTheme.mono())
                    }
                    .fleetCard(padding: FleetSurfaceSpacing.cardInset)
                }

                if !isCurrent { MinerOfflineSettingsNotice(snapshot: snapshot) }

                actionButton(.pause, disabled: store.snapshot(for: device.id)?.info?.miningPaused == true)
                actionButton(.resume, disabled: store.snapshot(for: device.id)?.info?.miningPaused == false)

                if let resultMessage {
                    Label(resultMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(FleetTheme.positive)
                        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(FleetTheme.warning)
                        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
                }
            }
            .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .background(FleetTheme.canvas)
        .navigationTitle("XMRig Control")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                now = Date()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .onDisappear { commandTask?.cancel() }
        .confirmationDialog(
            pendingAction?.title ?? "Confirm XMRig command",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingAction {
                Button(action.title) { send(action) }
                Button("Cancel", role: .cancel) { pendingAction = nil }
            }
        } message: {
            Text(pendingAction?.explanation ?? "")
        }
    }

    @ViewBuilder
    private func actionButton(_ action: Action, disabled: Bool) -> some View {
        if action == .pause {
            actionButtonContent(action, disabled: disabled)
                .buttonStyle(.bordered)
        } else {
            actionButtonContent(action, disabled: disabled)
                .buttonStyle(.borderedProminent)
        }
    }

    private func actionButtonContent(_ action: Action, disabled: Bool) -> some View {
        Button {
            pendingAction = action
        } label: {
            Label(action.title, systemImage: action.symbol)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .disabled(disabled || isSending || !canSend || !isCurrent)
        .accessibilityIdentifier("xmrig.control.\(action.rawValue)")
    }

    private func send(_ action: Action) {
        pendingAction = nil
        guard canSend, !isSending else {
            errorMessage = "Controls are read only. Reconnect and refresh the saved miner first."
            return
        }
        isSending = true
        resultMessage = nil
        errorMessage = nil
        commandTask = Task {
            defer { isSending = false }
            do {
                // Re-read after confirmation. Cached UI state never authorizes a command.
                guard await store.refreshAfterWrite(for: device), canSend, !Task.isCancelled else {
                    errorMessage = "No current connection confirmed. Nothing was sent."
                    return
                }
                let token = MinerCredentialStore.token(for: device.keychainCredentialReference)
                let client = XMRigAPIClient(device: device, bearerToken: token, session: store.session)
                try Task.checkCancellation()
                switch action {
                case .pause: try await client.pause()
                case .resume: try await client.resume()
                }
                let refreshed = await store.refreshAfterWrite(for: device)
                guard !Task.isCancelled else { return }
                resultMessage = "XMRig accepted the \(action.rawValue) command."
                    + (refreshed ? "" : " Fresh state is unavailable. Refresh before another command.")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
