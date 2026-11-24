import SwiftUI
import HashFleetCore

struct AddMinerView: View {
    let store: FleetStore
    /// Native workspace completion is owned by the presenting view, not a system open intent.
    var onBulkAddSuccess: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State var name = ""
    @State var address = ""
    @State var minerKind: MinerDevice.Kind = .espMiner
    @State var bearerToken = ""
    @State var isValidating = false
    @State var isFindingThisMac = false
    @State var validationError: String?
    @State var discoveryAddError: String?
    @State var discovery = MinerDiscoveryCoordinator()
    @State var localNetwork = LocalNetworkAuthorization()
    @State private var isShowingDesignGallery = false
    @State private var isManualExpanded = false
    @AppStorage("addMiner.discoveryDesignStyle") private var selectedStyle: MinerDiscoveryDesignStyle = .unifiedSheet
    /// Addresses added during this sheet session. Discovery can surface several miners at once,
    /// so adding one must not dismiss the sheet and lose the rest of the results.
    @State var addedAddresses: Set<String> = []
    @FocusState private var focusedField: Field?

    private enum Field { case name, address, token }

    var body: some View {
        FleetPageNavigationStack { form }
        .presentationBackground(FleetTheme.canvas)
        #if os(iOS)
        // Only present full screen cover if the user explicitly chose Sonar Grid or AirDrop Fleet.
        // Unified Sheet expands natively right inside this sheet without taking over the screen.
        .fullScreenCover(isPresented: Binding(
            get: { discovery.isScanning && selectedStyle != .unifiedSheet },
            set: { presented in if !presented, discovery.isScanning { discovery.cancel() } }
        )) {
            AddMinerFullScreenScan(
                probedHosts: discovery.probedHosts,
                hostCount: discoveryHostCount,
                candidates: discovery.candidates,
                onCancel: { discovery.cancel() }
            )
        }
        #endif
    }

    private var designGalleryButton: some View {
        Button {
            isShowingDesignGallery = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(FleetTheme.accent)
                Text("Preview Discovery Designs (A · B · C)")
                    .fleetFont(.footnote, weight: .semibold)
                    .foregroundStyle(FleetTheme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(FleetTheme.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(FleetTheme.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .sheet(isPresented: $isShowingDesignGallery) {
            AddMinerDesignGalleryView()
        }
    }

    private var form: some View {
        ScrollViewReader { proxy in
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
                    designGalleryButton
                    if minerKind == .espMiner { discoveryCard }
                    if minerKind == .xmrig && !localNetwork.isGranted { localNetworkApprovalControls }
                    if minerKind == .espMiner && (discovery.isScanning || !discovery.candidates.isEmpty) {
                        DisclosureGroup(isExpanded: $isManualExpanded) {
                            manualInputSection
                                .padding(.top, 10)
                        } label: {
                            Label("Add Manually by IP & Address", systemImage: "network")
                                .fleetFont(.subheadline, weight: .semibold)
                                .foregroundStyle(FleetTheme.secondary)
                        }
                        .padding(14)
                        .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        manualInputSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: FleetLayout.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .fleetEditingScroll()
            .fleetRevealEditingField(focusedField, using: proxy)
            .accessibilityIdentifier("addMiner.formScroll")
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
            .fleetEditingDone(focusedField != nil, identifier: "addMiner.keyboardDone") { focusedField = nil }
            .tint(FleetTheme.accent)
            .onAppear { store.preferences.continueWithCurrentDashboard() }
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
    }

    private var manualInputSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            manualInputsCard
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
            Text("Adding a miner saves its address. A live response confirms that it is connected.")
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var manualInputsCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            inputLabel(
                "MINER NAME (OPTIONAL)",
                detail:
                    "Give your hardware a name, or leave this blank " +
                        "to use its model name automatically."
            )
            TextField("Miner name (optional)", text: $name,
                      prompt: Text("Desk miner").foregroundStyle(FleetTheme.secondary))
                .fleetFont(.body)
                .foregroundStyle(FleetTheme.ink)
                .textContentType(.nickname)
                .submitLabel(.next)
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = .address }
                .padding(16)
                .background(FleetTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
                .id(Field.name)
                .accessibilityLabel("Miner name (optional)")
                .accessibilityIdentifier("addMiner.name")
            inputLabel(
                "NETWORK ADDRESS",
                detail: minerKind == .espMiner
                    ? "Find this on your miner’s display or in your router settings."
                    : "Use the Mac hostname or IP and XMRig HTTP port, such as 192.168.1.20:18099."
            )
            TextField(
                "Miner IP address or hostname",
                text: $address,
                prompt: Text(minerKind == .espMiner ? "192.168.1.42 or bitaxe.local" : "127.0.0.1:18099")
                    .foregroundStyle(FleetTheme.secondary)
            )
                .fleetFont(.body)
                .foregroundStyle(FleetTheme.ink)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .address)
                #if os(iOS)
                .submitLabel(minerKind == .xmrig ? .next : .go)
                .onSubmit {
                    if minerKind == .xmrig { focusedField = .token } else { addMiner() }
                }
                #else
                .submitLabel(.done)
                .onSubmit(addMiner)
                #endif
                .padding(16)
                .background(FleetTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
                .id(Field.address)
                .accessibilityLabel("Miner IP address or hostname")
                .accessibilityIdentifier("addMiner.address")
            if minerKind == .xmrig {
                inputLabel(
                    "ACCESS TOKEN (OPTIONAL)",
                    detail: "Stored in this device's Keychain. Hash Fleet never saves the token in its fleet data."
                )
                SecureField("XMRig bearer token (optional)", text: $bearerToken,
                            prompt: Text("XMRig bearer token").foregroundStyle(FleetTheme.secondary))
                    .fleetFont(.body)
                    .foregroundStyle(FleetTheme.ink)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .token)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .padding(16)
                    .background(FleetTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
                    .id(Field.token)
                    .accessibilityLabel("XMRig bearer token (optional)")
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
    }

    var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Find miners on Wi-Fi", systemImage: "wifi")
                    .fleetFont(.headline)
                    .foregroundStyle(FleetTheme.ink)
                    .accessibilityAddTraits(.isHeader)
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
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(FleetTheme.accent.opacity(0.2), lineWidth: 3)
                                .frame(width: 38, height: 38)
                            Circle()
                                .trim(from: 0, to: AddMinerScanRadarModel.progressFraction(probedHosts: discovery.probedHosts, hostCount: discoveryHostCount))
                                .stroke(FleetTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 38, height: 38)
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(FleetTheme.accent)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(AddMinerScanRadarModel.progressText(probedHosts: discovery.probedHosts, hostCount: discoveryHostCount))
                                .fleetFont(.subheadline, weight: .semibold)
                                .foregroundStyle(FleetTheme.ink)
                            Text(AddMinerScanRadarModel.percentText(fraction: AddMinerScanRadarModel.progressFraction(probedHosts: discovery.probedHosts, hostCount: discoveryHostCount)) + " complete · \(discovery.candidates.count) found")
                                .fleetFont(.caption, design: .monospaced)
                                .foregroundStyle(FleetTheme.secondary)
                        }
                        Spacer()
                    }

                    // Smooth progress line with ShipSwift LightSweep effect
                    GeometryReader { geo in
                        let frac = AddMinerScanRadarModel.progressFraction(probedHosts: discovery.probedHosts, hostCount: discoveryHostCount)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(FleetTheme.separator.opacity(0.3))
                                .frame(height: 6)
                            SWLightSweep(lineWidth: 60, duration: 1.2, lineColor: Color.white.opacity(0.7), cornerRadius: 3) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(FleetTheme.accent)
                                    .frame(width: max(8, geo.size.width * CGFloat(frac)), height: 6)
                            }
                            .animation(.easeOut(duration: 0.2), value: frac)
                        }
                    }
                    .frame(height: 6)

                    HStack(spacing: 10) {
                        Button("Cancel Scan") {
                            discovery.cancel()
                        }
                        .fleetFont(.footnote, weight: .semibold)
                        .foregroundStyle(FleetTheme.secondary)
                        .accessibilityIdentifier("addMiner.discoveryCancel")

                        Spacer()
                        if !discovery.candidates.isEmpty {
                            addAllButton
                        }
                    }
                }
                .padding(12)
                .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .animation(.spring(duration: 0.35, bounce: 0.2), value: discovery.isScanning)
            } else if !localNetwork.isGranted {
                localNetworkApprovalControls
            } else {
                Button {
                    startDiscovery()
                } label: {
                    Label("Scan nearby miners", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
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
                 : "Hash Fleet finds and talks to your miners directly on your Wi-Fi network. Nothing is sent to the internet. "
                    + "Next, iOS will ask whether to allow this. You can choose either option and change it later in Settings.")
                .fleetFont(.footnote)
                .foregroundStyle(localNetwork.status == .denied ? FleetTheme.warning : FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                #if os(iOS)
                    if localNetwork.status == .denied,
                       let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                        return
                    }
                #endif
                localNetwork.request()
            } label: {
                HStack {
                    if localNetwork.status == .requesting { ProgressView().controlSize(.small) }
                    Label(localNetwork.status == .requesting ? "Waiting…" : localNetworkButtonTitle,
                          systemImage: "arrow.right")
                }
                .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(FleetPrimaryButtonStyle(size: .compact))
            .disabled(localNetwork.status == .requesting)
            .accessibilityIdentifier("addMiner.allowLocalNetwork")
            Button {
            } label: {
                Label("Scan nearby miners", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
            .disabled(true)
            .accessibilityIdentifier("addMiner.discoveryStart")
            .accessibilityHint("Available after you respond to the local network prompt.")
        }
    }

    private var localNetworkButtonTitle: String {
        #if os(iOS)
            if localNetwork.status == .denied { return "Open Settings" }
        #endif
        return "Continue"
    }

    var discoveryHostCount: Int {
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
                .accessibilityAddTraits(.isHeader)
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

    func addMiner() {
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

    func findXMRigOnThisMac() {
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
}

// Discovery actions share the sheet’s private draft and validation state.
extension AddMinerView {
    /// Adds every discovered miner not already in the fleet. Settings are never changed.
    func addAllDiscovered() {
        guard localNetwork.isGranted, !discovery.isScanning, !discovery.candidates.isEmpty else { return }
        #if os(macOS)
        FleetMacNavigationTrace.record("addAll.begin", "candidates=\(discovery.candidates.count)")
        #endif
        let result = AddMinerMultiSelection.addAll(
            candidates: discovery.candidates, alreadyAdded: addedAddresses, customName: name
        ) { customName, candidate in
            try store.add(
                name: customName,
                address: candidate.address,
                firmwareFamily: candidate.firmwareFamily,
                detectedFamily: candidate.detectedFamily
            )
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
            try store.add(
                name: customName,
                address: candidate.address,
                firmwareFamily: candidate.firmwareFamily,
                detectedFamily: candidate.detectedFamily
            )
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
