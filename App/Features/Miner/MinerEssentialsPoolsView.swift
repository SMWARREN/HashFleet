import SwiftUI
import HashFleetCore

/// The compact Essentials route lets people choose a connection by purpose, not by firmware ID.
struct MinerEssentialsPoolsView: View {
    let device: MinerDevice
    let store: FleetStore
    @State private var editorRoute: EditorRoute?

    private struct EditorRoute: Hashable {
        let id = UUID()
        let baseline: MinerEssentialsPoolBaseline
        let identity: MinerInlineActionState.Identity

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private var snapshot: MinerSnapshot? { store.snapshot(for: device.id) }
    private var canWrite: Bool {
        MinerWriteAvailability.allows(snapshot, device: device, currentDevices: store.visibleDevices, isDemo: store.isDemo)
    }

    var body: some View {
        FleetSettingsList {
            Section {
                VStack(spacing: 0) {
                    ForEach(MinerPoolRole.allCases) { role in
                        if role == .fallback { Divider().padding(.leading, 14) }
                        poolRow(role)
                    }
                }
                .fleetTourTarget("guide.ordinaryPools")
                .listRowInsets(EdgeInsets())
                .listRowBackground(FleetTheme.surface)
            } header: {
                Text("Connections").accessibilityIdentifier("settings.pools.essentials")
            } footer: {
                Text("Edit a connection here. Use Full View for pool presets, assignments, and advanced options.")
                    .foregroundStyle(FleetTheme.secondary)
            }

            if !store.isDemo && !canWrite {
                Section { MinerOfflineSettingsNotice(snapshot: snapshot) }
                    .listRowBackground(FleetTheme.surface)
            }
        }
        .navigationTitle("Pools")
        .navigationBarTitleDisplayMode(.inline)
        .tint(FleetTheme.accent)
        .navigationDestination(item: $editorRoute) { route in
            MinerEssentialsPoolEditor(device: device, store: store, initial: route.baseline, identity: route.identity)
        }
    }

    @ViewBuilder
    private func poolRow(_ role: MinerPoolRole) -> some View {
        let raw = snapshot?.info?.raw ?? [:]
        let connection = MinerEssentialsPoolBaseline.reportedConnection(role, raw: raw)
        let id = "settings.pools.\(role.rawValue)"
        if canWrite, let info = snapshot?.info, let identity = MinerInlineActionState.identity(from: info),
           let baseline = MinerEssentialsPoolBaseline(role: role, raw: raw) {
            Button {
                editorRoute = .init(baseline: baseline, identity: identity)
            } label: {
                rowLabel(role, connection: connection, showsChevron: true)
                    .padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 68)
                    .contentShape(Rectangle())
            }
            // Each button must own its touch target within the grouped List row.
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
        } else {
            rowLabel(role, connection: connection, readOnly: true)
                .padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 68)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(id)
        }
    }

    private func rowLabel(_ role: MinerPoolRole, connection: MinerPoolConnection?,
                          readOnly: Bool = false, showsChevron: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: role == .primary ? "network" : "arrow.triangle.branch")
                .fleetFont(.body, weight: .semibold)
                .foregroundStyle(role == .primary ? FleetTheme.accent : FleetTheme.secondary)
                .frame(width: 24)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(role.title).fleetFont(.headline).foregroundStyle(FleetTheme.ink)
                Text(connection?.address ?? "Not reported")
                    .fleetFont(.subheadline).foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if role == .fallback {
                    Text("Backup connection").fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                }
                if readOnly, !store.isDemo, canWrite {
                    Text("Not editable in Essentials")
                        .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .fleetFont(.footnote, weight: .semibold)
                    .foregroundStyle(FleetTheme.secondary)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MinerEssentialsPoolEditor: View {
    private enum Field: Hashable { case server, port, worker, password }

    let device: MinerDevice
    let store: FleetStore
    let identity: MinerInlineActionState.Identity
    @State private var baseline: MinerEssentialsPoolBaseline
    @State private var draft: MinerPoolConnection
    @State private var password = ""
    @State private var review: MinerEssentialsPoolChange?
    @State private var failure: String?
    @State private var receipt: String?
    @State private var isSaving = false
    @State private var requiresReopen = false
    @FocusState private var focused: Field?

    init(device: MinerDevice, store: FleetStore, initial: MinerEssentialsPoolBaseline,
         identity: MinerInlineActionState.Identity) {
        self.device = device
        self.store = store
        self.identity = identity
        _baseline = State(initialValue: initial)
        _draft = State(initialValue: initial.connection)
    }

    private var currentInfo: MinerInfo? {
        let snapshot = store.snapshot(for: device.id)
        guard MinerWriteAvailability.allows(snapshot, device: device, currentDevices: store.visibleDevices, isDemo: store.isDemo),
              let info = snapshot?.info, MinerInlineActionState.identity(from: info) == identity else { return nil }
        return info
    }

    var body: some View {
        FleetSettingsForm {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Server")
                    TextField("pool.example.com", text: $draft.server)
                        .accessibilityLabel("Server")
                        .accessibilityIdentifier("settings.pool.server")
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
#endif
                        .focused($focused, equals: .server)
                        .submitLabel(.next)
                        .onSubmit { focused = .port }
                }
                .id(Field.server)
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Port")
                    TextField("Enter port", text: $draft.port)
                        .accessibilityLabel("Port")
                        .accessibilityIdentifier("settings.pool.port")
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                        .focused($focused, equals: .port)
                }
                .id(Field.port)
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Worker or wallet")
                    TextField("As provided by your pool", text: $draft.worker)
                        .accessibilityLabel("Worker or wallet")
                        .accessibilityIdentifier("settings.pool.worker")
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .focused($focused, equals: .worker)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                }
                .id(Field.worker)
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Pool password")
                    SecureField(baseline.needsPassword(for: draft.server) ? "Enter new password" : "Leave blank to keep it",
                                text: $password)
                        .accessibilityLabel("Pool password")
                        .accessibilityIdentifier("settings.pool.password")
                        .focused($focused, equals: .password)
                        .submitLabel(.done)
                        .onSubmit { focused = nil }
                }
                .id(Field.password)
            } header: {
                Text("Connection details")
            } footer: {
                if baseline.needsPassword(for: draft.server) {
                    Text("Use the new server’s password or the placeholder your pool specifies. The previous password won’t be reused.")
                } else {
                    Text("Use the server, port, and worker or wallet provided by your pool.")
                }
            }
            .listRowBackground(FleetTheme.surface)
            .disabled(isSaving)

            Section {
                if let failure {
                    Label(failure, systemImage: "exclamationmark.circle")
                        .foregroundStyle(FleetTheme.warning)
                        .accessibilityIdentifier("settings.pool.error")
                }
                if let receipt {
                    Label(receipt, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(FleetTheme.positive)
                        .accessibilityIdentifier("settings.pool.saved")
                }
                if currentInfo == nil && !isSaving && failure == nil {
                    Text("Reconnect and refresh the miner to edit this connection.")
                        .foregroundStyle(FleetTheme.secondary)
                }
                Button(action: buildReview) {
                    FleetPendingButtonLabel(title: "Review changes", pendingTitle: "Saving…", isPending: isSaving)
                }
                .buttonStyle(FleetPrimaryButtonStyle(tone: .accent, fullWidth: true))
                .disabled(currentInfo == nil || isSaving || requiresReopen || (draft == baseline.connection && password.isEmpty))
                .accessibilityIdentifier("settings.pool.review")
            }
            .listRowBackground(FleetTheme.surface)
        }
        .fleetRevealEditingField(focused)
        .navigationTitle(baseline.role.title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(FleetTheme.accent)
        .fleetEditingDone(focused != nil, identifier: "settings.pool.keyboardDone") { focused = nil }
        .alert("Save \(baseline.role.title.lowercased())?", isPresented: Binding(
            get: { review != nil }, set: { if !$0 { review = nil } }
        ), presenting: review) { change in
            Button("Cancel", role: .cancel) {}
            Button("Save pool") { save(change) }
                .accessibilityIdentifier("settings.pool.confirm")
        } message: { change in
            Text(reviewMessage(change))
        }
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label).fleetFont(.subheadline, weight: .semibold).foregroundStyle(FleetTheme.ink)
            .accessibilityHidden(true)
    }

    private func reviewMessage(_ change: MinerEssentialsPoolChange) -> String {
        var details = ["\(device.name) · \(change.address)"]
        if change.changesWorker { details.append("Updates the worker or wallet you entered.") }
        if change.changesPassword { details.append("Replaces this connection’s password.") }
        details.append("The miner may reconnect. Other pool assignments stay unchanged.")
        return details.joined(separator: "\n\n")
    }

    private func buildReview() {
        focused = nil
        failure = nil
        receipt = nil
        do {
            guard let change = try baseline.plan(for: draft, password: password) else {
                failure = "Nothing to save."
                return
            }
            review = change
        } catch {
            failure = error.localizedDescription
        }
    }

    private func save(_ change: MinerEssentialsPoolChange) {
        guard !isSaving, !requiresReopen else { return }
        guard currentInfo != nil else {
            failure = "The miner connection changed. Nothing was sent. Reopen Pools to try again."
            requiresReopen = true
            return
        }
        guard let body = try? JSONEncoder().encode(change.payload) else {
            failure = "The pool request couldn’t be prepared. Nothing was sent."
            return
        }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            let operation = MinerOperationModel(session: store.session)
            let role = change.baseline.role
            var changedDuringReview = false
            await operation.execute(device: device, endpoint: .settings, body: body, query: [], isDemo: store.isDemo,
                validatePreflight: { info in
                    guard MinerInlineActionState.identity(from: info) == identity,
                          MinerEssentialsPoolBaseline(role: role, raw: info.raw) == change.baseline else {
                        changedDuringReview = true
                        throw MinerToolError.message("Pool settings changed during review. Nothing was sent.")
                    }
                }, writeAuthorized: { currentInfo != nil })
            if changedDuringReview {
                failure = "The miner or connection changed. Nothing was sent. Reopen Pools to see the current settings."
                requiresReopen = true
                return
            }
            if operation.error != nil {
                failure = "The save couldn’t be confirmed. Check the miner connection and reopen Pools before retrying."
                requiresReopen = true
                return
            }
            guard await store.refreshAfterWrite(for: device), let info = currentInfo,
                  change.baseline.matches(change, raw: info.raw),
                  let current = MinerEssentialsPoolBaseline(role: role, raw: info.raw) else {
                failure = "The miner accepted the request, but the new connection couldn’t be verified. Reopen Pools before retrying."
                requiresReopen = true
                return
            }
            baseline = current
            draft = current.connection
            password = ""
            if change.changesPassword {
                receipt = change.changesConnection
                    ? "Connection settings verified. The miner hides passwords on readback."
                    : "Password request accepted. The miner hides passwords on readback."
            } else {
                receipt = "\(role.title) saved and verified."
            }
        }
    }
}
