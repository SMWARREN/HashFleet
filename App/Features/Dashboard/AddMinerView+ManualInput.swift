import SwiftUI

extension AddMinerView {
    var manualInputSection: some View {
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

    var manualInputsCard: some View {
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
                prompt: Text(minerKind == .espMiner ? "192.168.1.42 or miner.local" : "127.0.0.1:18099")
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

    func inputLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fleetFont(.caption, weight: .semibold, design: .monospaced).tracking(1)
            Text(detail).fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
        }
    }
}
