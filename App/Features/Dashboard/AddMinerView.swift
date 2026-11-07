import SwiftUI
import HashFleetCore

struct AddMinerView: View {
    let store: FleetStore
    /// Native workspace completion is owned by the presenting view, not a system open intent.
    var onBulkAddSuccess: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var name = ""
    @State private var address = ""
    @State private var minerKind: MinerDevice.Kind = .espMiner
    @State private var bearerToken = ""
    @State private var isValidating = false
    @State private var isFindingThisMac = false
    @State private var validationError: String?
    @State private var discoveryAddError: String?
    @State var discovery = MinerDiscoveryCoordinator()
    @State var localNetwork = LocalNetworkAuthorization()
    /// Addresses added during this sheet session. Discovery can surface several miners at once,
    /// so adding one must not dismiss the sheet and lose the rest of the results.
    @State var addedAddresses: Set<String> = []
    @FocusState private var focusedField: Field?

    private enum Field { case name, address, token }

    var body: some View {
        FleetPageNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    introduction
                    if FleetReleaseFeatures.xmrigEnabled {
                        Picker("Miner type", selection: $minerKind) {
                            Text("ESP Miner").tag(MinerDevice.Kind.espMiner)
                            Text("XMRig").tag(MinerDevice.Kind.xmrig)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("addMiner.kind")
                    }
                    BitsySays(
                        mood: .thinking,
                        message: minerKind == .espMiner
                            ? "I'll help find miners on this Wi-Fi, or you can add one by hand."
                            : "Connect to XMRig's HTTP API for read-only status and reviewed pause or resume controls.",
                        size: 68
                    )
                    .accessibilityIdentifier("addMiner.bitsy")
                    if minerKind == .espMiner { discoveryCard }
                    if minerKind == .xmrig && !localNetwork.isGranted { localNetworkApprovalControls }
                    VStack(alignment: .leading, spacing: 22) {
                        inputLabel(
                            "MINER NAME (OPTIONAL)",
                            detail:
                                "Give your hardware a name, or leave this blank " +
                                    "to use its model name automatically."
                        )
                        TextField("Desk miner", text: $name)
                            .textContentType(.nickname)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .name)
                            .onSubmit { focusedField = .address }
                            .padding(16)
                            .background(FleetTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityLabel("Miner name")
                            .accessibilityIdentifier("addMiner.name")
                        inputLabel(
                            "NETWORK ADDRESS",
                            detail: minerKind == .espMiner
                                ? "Find this on your miner’s display or in your router settings."
                                : "Use the Mac hostname or IP and XMRig HTTP port, such as 192.168.1.20:18099."
                        )
                        TextField(
                            minerKind == .espMiner ? "192.168.1.42 or bitaxe.local" : "127.0.0.1:18099",
                            text: $address
                        )
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($focusedField, equals: .address)
                            .onSubmit(addMiner)
                            .padding(16)
                            .background(FleetTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityLabel("Miner IP address or hostname")
                            .accessibilityIdentifier("addMiner.address")
                        if minerKind == .xmrig {
                            inputLabel(
                                "ACCESS TOKEN (OPTIONAL)",
                                detail: "Stored in this device's Keychain. Hash Fleet never saves the token in its fleet data."
                            )
                            SecureField("XMRig bearer token", text: $bearerToken)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .token)
                                .padding(16)
                                .background(FleetTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityIdentifier("addMiner.xmrigToken")
                            if FleetLayout.isMac {
                                Button {
                                    findXMRigOnThisMac()
                                } label: {
                                    if isFindingThisMac {
                                        ProgressView().frame(maxWidth: .infinity, minHeight: 24)
                                    } else {
                                        Label("Find XMRig on This Mac", systemImage: "desktopcomputer.and.macbook")
                                            .frame(maxWidth: .infinity, minHeight: 24)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isFindingThisMac || isValidating)
                                .accessibilityIdentifier("addMiner.findXMRigThisMac")
                            }
                        }
                        if let validationError {
                            Label(validationError, systemImage: "exclamationmark.circle.fill")
                                .fleetFont(.subheadline)
                                .foregroundStyle(FleetTheme.accent)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Unable to add miner. \(validationError)")
                        }
                    }
                    .fleetCard()
                    Label {
                        Text(
                            minerKind == .espMiner
                                ? FleetDeviceCopy.current.addMinerNetworkExplanation
                                : FleetDeviceCopy.current.xmrigConnectionExplanation
                        )
                    } icon: {
                        Image(systemName: "network")
                    }
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Button(action: addMiner) {
                        if isValidating {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Add miner", systemImage: "plus")
                        }
                    }
                    .buttonStyle(FleetPrimaryButtonStyle())
                    .accessibilityIdentifier("addMiner.save")
                    .disabled(!localNetwork.isGranted || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
                    .opacity(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    Text("Adding a miner saves its address. A live response confirms that it is connected.")
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: FleetLayout.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .background(FleetTheme.canvas)
            .foregroundStyle(FleetTheme.ink)
            .navigationTitle("Add a miner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(addedAddresses.isEmpty ? "Cancel" : "Done") { dismiss() }
                        .accessibilityIdentifier("addMiner.dismiss")
                }
            }
            .tint(FleetTheme.accent)
            .onChange(of: address) { _, _ in validationError = nil }
            .onChange(of: minerKind) { _, _ in
                validationError = nil
                address = ""
                bearerToken = ""
            }
            .onChange(of: discovery.candidates) { _, candidates in
                // A rescan returns fresh candidates. Mark any that are already in the fleet so
                // the rows stay honest instead of inviting a duplicate add.
                markAlreadyPresent(in: candidates)
            }
            .onChange(of: localNetwork.status) { _, status in
                if status != .granted { discovery.cancel() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    discovery.cancel()
                    localNetwork.cancel()
                }
            }
            .onDisappear {
                discovery.cancel()
                localNetwork.cancel()
            }
        }
        .presentationBackground(FleetTheme.canvas)
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Find miners on Wi-Fi", systemImage: "wifi")
                    .fleetFont(.headline)
                    .foregroundStyle(FleetTheme.ink)
                Spacer(minLength: 8)
            }
            Text(
                "Hash Fleet checks nearby private Wi-Fi addresses for a read-only ESP-Miner response. " +
                    "It does not change anything."
            )
            .fleetFont(.subheadline)
            .foregroundStyle(FleetTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if discovery.isScanning {
                AddMinerScanRadar(
                    probedHosts: discovery.probedHosts,
                    hostCount: discoveryHostCount,
                    candidatesCount: discovery.candidates.count,
                    isScanning: true,
                    onCancel: { discovery.cancel() }
                )
            } else if !localNetwork.isGranted {
                localNetworkApprovalControls
            } else {
                Button {
                    startDiscovery()
                } label: {
                    Label("Scan nearby miners", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .buttonStyle(.bordered)
                .tint(FleetTheme.accent)
                .disabled(!localNetwork.isGranted)
                .accessibilityIdentifier("addMiner.discoveryStart")
            }

            discoveryContent
            if let discoveryAddError {
                Label(discoveryAddError, systemImage: "exclamationmark.circle.fill")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("addMiner.bulkError")
            }
        }
        .fleetCard(padding: 16)
        // Keep the card itself discoverable without allowing its identifier to replace the
        // identifiers of the scan button, cancel button, and result rows in the AX tree.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("addMiner.discoveryCard")
    }

    /// Scanning stays disabled until the person explicitly allows local network access.
    @ViewBuilder
    private var localNetworkApprovalControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localNetwork.status == .denied
                 ? "Local network access is off. Turn on Hash Fleet in \(FleetDeviceCopy.hostSettingsAppName) › Privacy & Security › Local Network, then try again."
                 : "Adding or scanning miners needs your permission to access your local network.")
                .fleetFont(.footnote)
                .foregroundStyle(localNetwork.status == .denied ? FleetTheme.warning : FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                localNetwork.request()
            } label: {
                HStack {
                    if localNetwork.status == .requesting { ProgressView().controlSize(.small) }
                    Label(localNetwork.status == .requesting ? "Waiting for approval…" : "Allow local network access",
                          systemImage: "lock.open")
                }
                .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.borderedProminent)
            .tint(FleetTheme.accent)
            .disabled(localNetwork.status == .requesting)
            .accessibilityIdentifier("addMiner.allowLocalNetwork")
            Button {
            } label: {
                Label("Scan nearby miners", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .accessibilityIdentifier("addMiner.discoveryStart")
            .accessibilityHint("Available after you allow local network access.")
        }
    }

    private var discoveryHostCount: Int {
        guard case .scanning(let count) = discovery.state else { return 254 }
        return count
    }

    @ViewBuilder
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                FleetBrandMark(size: FleetLayout.isMac ? 104 : 76)
                FleetLoadAnimatedArt(
                    loop: .fleetCluster,
                    size: CGSize(width: 180, height: 106),
                    accessibilityIdentifier: "addMiner.minerCluster"
                )
                .frame(maxWidth: .infinity)
            }
            Text("Add one more miner.")
                .fleetFont(.largeTitle, weight: .bold)
                .tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
            Text("Connect your open-source miner and keep an eye on its work.")
                .fleetFont(.body)
                .foregroundStyle(FleetTheme.secondary)
        }
    }

    private func inputLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fleetFont(.caption, weight: .semibold, design: .monospaced).tracking(1)
            Text(detail).fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
        }
    }

    /// Flags candidates that already exist in the fleet, using the same URL normalisation
    /// the store uses for duplicate detection.
    private func markAlreadyPresent(in candidates: [MinerDiscoveryCandidate]) {
        addedAddresses.formUnion(
            AddMinerMultiSelection.alreadyPresent(candidates: candidates, devices: store.devices)
        )
    }

    private func addMiner() {
        guard localNetwork.isGranted else { return }
        guard FleetReleaseFeatures.includes(minerKind) else { return }
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if minerKind == .espMiner {
            do {
                try store.add(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    address: address.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                dismiss()
            } catch {
                validationError = error.localizedDescription
            }
            return
        }

        isValidating = true
        validationError = nil
        let enteredAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let candidate = MinerDevice(name: enteredName, address: enteredAddress, kind: .xmrig)
                _ = try await XMRigAPIClient(device: candidate, bearerToken: token.isEmpty ? nil : token).summary()
                try store.addXMRig(name: enteredName, address: enteredAddress, bearerToken: token)
                dismiss()
            } catch {
                validationError = error.localizedDescription
                isValidating = false
            }
        }
    }

    private func findXMRigOnThisMac() {
        guard FleetLayout.isMac else { return }
        isFindingThisMac = true
        validationError = nil
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            for port in [18099, 4444, 8080, 18080] {
                let candidateAddress = "127.0.0.1:\(port)"
                let candidate = MinerDevice(name: "XMRig on This Mac", address: candidateAddress, kind: .xmrig)
                if (try? await XMRigAPIClient(
                    device: candidate,
                    bearerToken: token.isEmpty ? nil : token
                ).summary()) != nil {
                    address = candidateAddress
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = "XMRig on This Mac" }
                    isFindingThisMac = false
                    return
                }
            }
            validationError = "No XMRig HTTP API answered on the common local ports. Enter its configured port manually."
            isFindingThisMac = false
        }
    }

    /// Adds every discovered miner not already in the fleet. Settings are never changed.
    func addAllDiscovered() {
        guard localNetwork.isGranted, !discovery.isScanning, !discovery.candidates.isEmpty else { return }
        #if os(macOS)
        FleetMacNavigationTrace.record("addAll.begin", "candidates=\(discovery.candidates.count)")
        #endif
        let result = AddMinerMultiSelection.addAll(
            candidates: discovery.candidates, alreadyAdded: addedAddresses, customName: name
        ) { customName, address in
            try store.add(name: customName, address: address)
        }
        addedAddresses = result.addedAddresses
        if result.failures.isEmpty {
            discoveryAddError = nil
            #if os(macOS)
            FleetMacNavigationTrace.record("addAll.workspaceCompletion")
            AddMinerMultiSelection.completeInWorkspace(
                returnToFleet: onBulkAddSuccess, dismiss: { dismiss() }
            )
            FleetMacNavigationTrace.record("addAll.complete")
            #else
            dismiss()
            FleetSystemNavigation.request()
            #endif
        } else {
            discoveryAddError = result.failures.joined(separator: "\n")
        }
    }

    func startDiscovery() {
        guard localNetwork.isGranted else { return }
        discoveryAddError = nil
        discovery.start()
    }

    /// Adds a discovered miner and stays on the sheet so the remaining results can be added too.
    func addMiner(_ candidate: MinerDiscoveryCandidate) {
        guard localNetwork.isGranted else { return }
        guard !addedAddresses.contains(candidate.address) else { return }
        do {
            // A custom name belongs to a single miner, so only apply it to the first one added.
            // Every later miner resolves its own model-derived name after the first live response.
            let customName = AddMinerMultiSelection.name(
                forCustomName: name, alreadyAdded: addedAddresses
            )
            try store.add(name: customName, address: candidate.address)
            addedAddresses.insert(candidate.address)
            validationError = nil
        } catch FleetError.duplicate {
            // Already in the fleet from an earlier session. Reflect that rather than erroring.
            addedAddresses.insert(candidate.address)
        } catch {
            validationError = error.localizedDescription
        }
    }
}

#Preview("Add miner") {
    AddMinerView(store: FleetStore())
}
