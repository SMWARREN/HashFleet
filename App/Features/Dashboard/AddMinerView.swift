import SwiftUI
import HashFleetCore
#if os(iOS)
import WatchConnectivity
import HashFleetWatchCore
#endif

struct AddMinerView: View {
    let store: FleetStore
    /// Native workspace completion is owned by the presenting view, not a system open intent.
    var onBulkAddSuccess: (() -> Void)?
    @Environment(\.dismiss) var dismiss
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
    @State private var isManualExpanded = false
    /// Addresses added during this sheet session. Discovery can surface several miners at once,
    /// so adding one must not dismiss the sheet and lose the rest of the results.
    @State var addedAddresses: Set<String> = []
    @FocusState var focusedField: Field?

    enum Field { case name, address, token }

    var body: some View {
        FleetPageNavigationStack { form }
        .presentationBackground(FleetTheme.canvas)
    }

    private var form: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    introduction
                    if FleetReleaseFeatures.xmrigEnabled {
                        Picker("Miner type", selection: $minerKind) {
                            Text("ASIC / Hardware").tag(MinerDevice.Kind.espMiner)
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
            .onChange(of: discovery.candidates) { oldVal, newVal in
                if newVal.count > oldVal.count {
                    FleetHaptics.light()
                }
                markAlreadyPresent(in: newVal)
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
                "Hash Fleet checks nearby private Wi-Fi addresses for compatible miners on your network. " +
                    "It does not change anything."
            )
            .fleetFont(.subheadline)
            .foregroundStyle(FleetTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if discovery.isScanning {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        // Spinning radar with spinning miner chip inside
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                            let elapsed = timeline.date.timeIntervalSinceReferenceDate
                            ZStack {
                                Circle()
                                    .stroke(FleetTheme.accent.opacity(0.2), lineWidth: 3)
                                    .frame(width: 44, height: 44)
                                Circle()
                                    .trim(from: 0, to: AddMinerScanRadarModel.progressFraction(probedHosts: discovery.probedHosts, hostCount: discoveryHostCount))
                                    .stroke(FleetTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .frame(width: 44, height: 44)
                                    .rotationEffect(.degrees(-90))
                                AngularGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .clear, location: 0.55),
                                        .init(color: FleetTheme.accent.opacity(0.2), location: 0.8),
                                        .init(color: FleetTheme.accent.opacity(0.85), location: 0.99),
                                        .init(color: .clear, location: 1.0)
                                    ],
                                    center: .center
                                )
                                .frame(width: 44, height: 44)
                                .rotationEffect(.degrees((elapsed * 160).truncatingRemainder(dividingBy: 360)))
                                .clipShape(Circle())

                                Image(systemName: "wifi")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(FleetTheme.accent)
                                    #if os(iOS)
                                    .symbolEffect(.variableColor.iterative.reversing, isActive: discovery.isScanning)
                                    #endif
                            }
                        }
                        .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Scanning Wi-Fi Fleet…")
                                    .fleetFont(.subheadline, weight: .bold)
                                    .foregroundStyle(FleetTheme.ink)
                                Circle()
                                    .fill(FleetTheme.positive)
                                    .frame(width: 7, height: 7)
                            }
                            Text(isRescanning ? "Re-checking late replies…" : scanProgressSummary)
                                .fleetFont(.caption, design: .monospaced)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .foregroundStyle(isRescanning ? FleetTheme.accent : FleetTheme.secondary)

                            if !discovery.candidates.isEmpty {
                                Text("\(discovery.candidates.count) \(discovery.candidates.count == 1 ? "miner" : "miners") responding live")
                                    .fleetFont(.caption2, weight: .semibold, design: .monospaced)
                                    .foregroundStyle(FleetTheme.positive)
                            }
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

                    HStack(spacing: 12) {
                        Button(role: .cancel) {
                            FleetHaptics.light()
                            discovery.cancel()
                        } label: {
                            Label("Stop Scan", systemImage: "stop.fill")
                                .fleetFont(.footnote, weight: .semibold)
                                .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(FleetPrimaryButtonStyle(tone: .secondary, size: .compact))
                        .accessibilityIdentifier("addMiner.discoveryCancel")

                        if !discovery.candidates.isEmpty {
                            addAllButton
                        }
                    }
                    .animation(.spring(duration: 0.3, bounce: 0.15), value: discovery.candidates.isEmpty)
                }
                .padding(14)
                .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .animation(.spring(duration: 0.35, bounce: 0.2), value: discovery.isScanning)
            } else {
                if !localNetwork.isGranted {
                    Text(localNetwork.status == .denied
                         ? "Local network access is off. Turn on Hash Fleet in \(FleetDeviceCopy.hostSettingsAppName) › Privacy & Security › Local Network, then try again."
                         : "Hash Fleet finds and talks to your miners directly on your Wi-Fi network. Nothing is sent to the internet. "
                            + "Next, iOS will ask whether to allow this. You can choose either option and change it later in Settings.")
                        .fleetFont(.footnote)
                        .foregroundStyle(localNetwork.status == .denied ? FleetTheme.warning : FleetTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    if !localNetwork.isGranted {
                        #if os(iOS)
                            if localNetwork.status == .denied,
                               let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                                return
                            }
                        #endif
                        localNetwork.request()
                    } else {
                        startDiscovery()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if localNetwork.status == .requesting {
                            ProgressView().controlSize(.small)
                            Text("Waiting for permission…")
                        } else if !localNetwork.isGranted {
                            Label(localNetworkButtonTitle, systemImage: localNetwork.status == .denied ? "gear" : "arrow.right")
                        } else {
                            Label(discovery.candidates.isEmpty ? "Scan nearby miners" : "Rescan Wi-Fi",
                                  systemImage: discovery.candidates.isEmpty ? "wifi" : "arrow.clockwise")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 24)
                }
                .buttonStyle(FleetPrimaryButtonStyle(
                    tone: !localNetwork.isGranted ? .accent : .secondary,
                    size: .compact
                ))
                .disabled(localNetwork.status == .requesting)
                .accessibilityIdentifier(localNetwork.isGranted ? "addMiner.discoveryStart" : "addMiner.allowLocalNetwork")
                .animation(.spring(duration: 0.35, bounce: 0.2), value: localNetwork.status)
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
                HStack(spacing: 8) {
                    if localNetwork.status == .requesting {
                        ProgressView().controlSize(.small)
                        Text("Waiting for permission…")
                    } else {
                        Label(localNetworkButtonTitle, systemImage: localNetwork.status == .denied ? "gear" : "arrow.right")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(FleetPrimaryButtonStyle(tone: .accent, size: .compact))
            .disabled(localNetwork.status == .requesting)
            .accessibilityIdentifier("addMiner.allowLocalNetwork")
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

    var isRescanning: Bool {
        discovery.isRescanning || (discovery.isScanning && discoveryHostCount > 0 && discovery.probedHosts >= discoveryHostCount)
    }

    private var scanProgressSummary: String {
        let count = AddMinerScanRadarModel.progressText(probedHosts: discovery.probedHosts, hostCount: discoveryHostCount)
        let percent = AddMinerScanRadarModel.percentText(
            fraction: AddMinerScanRadarModel.progressFraction(
                probedHosts: discovery.probedHosts, hostCount: discoveryHostCount
            )
        )
        return "\(count) · \(percent)"
    }

    @ViewBuilder
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                FleetBrandMark(size: FleetLayout.isMac ? 104 : 76)
                FleetLoadAnimatedArt(
                    loop: .fleetCluster,
                    size: CGSize(width: 180, height: 106),
                    isForcePlaying: discovery.isScanning,
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
        guard localNetwork.isGranted, !discovery.candidates.isEmpty else {
            FleetHaptics.warning()
            return
        }
        if discovery.isScanning {
            discovery.cancel()
        }
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
            FleetHaptics.success()
            #if os(iOS)
            if WCSession.isSupported() && WCSession.default.isPaired {
                FleetWatchSetupCoordinator.shared.start()
                let eligible = FleetWatchSetupSelection(devices: store.devices, isDemo: store.isDemo).miners
                if !eligible.isEmpty {
                    FleetWatchSetupCoordinator.shared.send(eligible)
                }
            }
            #endif
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
            FleetHaptics.error()
            discoveryAddError = result.failures.joined(separator: "\n")
        }
    }

    func startDiscovery() {
        guard localNetwork.isGranted else {
            FleetHaptics.warning()
            return
        }
        FleetHaptics.medium()
        discoveryAddError = nil
        discovery.start()
    }

    /// Adds a discovered miner and stays on the sheet so the remaining results can be added too.
    func addMiner(_ candidate: MinerDiscoveryCandidate) {
        guard localNetwork.isGranted else {
            FleetHaptics.warning()
            return
        }
        guard !addedAddresses.contains(candidate.address) else {
            FleetHaptics.light()
            return
        }
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
            FleetHaptics.light()
        } catch FleetError.duplicate {
            // Already in the fleet from an earlier session. Reflect that rather than erroring.
            addedAddresses.insert(candidate.address)
            FleetHaptics.light()
        } catch {
            validationError = error.localizedDescription
            FleetHaptics.error()
        }
    }
}

#Preview("Add miner") {
    AddMinerView(store: FleetStore())
}
