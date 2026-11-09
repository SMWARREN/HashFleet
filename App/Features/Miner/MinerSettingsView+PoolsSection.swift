import SwiftUI
import HashFleetCore

extension MinerSettingsView {
    var pools: some View {
        settingsHubCard {
            settingsHubHeader(
                "Pool connection",
                subtitle: "Stratum server, worker and protocol for one slot.",
                symbol: "externaldrive.connected.to.line.below"
            )
            Divider().overlay(FleetTheme.separator)
            fieldLabel("Firmware API")
            Picker("Firmware API", selection: poolModeSelection) {
                Text("Pool slot").tag("slot")
                Text("Legacy primary").tag("primary")
                Text("Legacy fallback").tag("fallback")
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            if poolMode == "slot" {
                fieldLabel("Slot ID")
                Picker("Slot ID", selection: poolSlotSelection) { ForEach(0..<8) { Text(poolSlotTitle($0)).tag($0) } }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("settings.pools.slot")
                fieldNote("pools", label: "the pool slot list")
                Text(
                    ("Current pool data is read from info.pools using each pool\'s id. "
                    + "Empty slots start a new configuration.")
                )
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
            TextField("Stratum server", text: $poolURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            TextField("Port", text: $poolPort).keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            poolCoinIdentity(draftPoolCoin)
                .accessibilityIdentifier("settings.pools.draftCoin")
            Text(
                ("Coin identity comes from a verified server and, for shared hosts such as SoloPool, its port. "
                + "Unknown endpoints are not guessed.")
            )
            .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            TextField("User / worker", text: $poolUser)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("settings.pools.user")
            fieldNote("user", label: "the pool worker or payout address")
            if draftPoolCoin == .dgb, poolPort == "8004" || poolPort == "7004" || poolPort == "9004" {
                Text(
                    "DGB SHA-256 only. Check that your payout address is DigiByte and not Bitcoin. "
                        + "Payouts to an address of the wrong coin cannot be recovered."
                )
                .fleetFont(.caption).foregroundStyle(FleetTheme.warning)
            }
            fieldLabel("Pool protocol")
            Picker("Pool protocol", selection: $poolProtocol) {
                Text("SV1").tag("SV1")
                Text("SV2").tag("SV2")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.pools.protocol")

            fieldLabel("Password")
            Picker("Password", selection: $poolPasswordMode) {
                ForEach(MinerPoolPasswordMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.pools.passwordMode")
            if poolPasswordMode == .replace {
                SecureField("Replacement password", text: $poolPassword)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("settings.pools.password")
                fieldNote("password", label: "the replacement stratum pool password")
            } else if poolPasswordMode == .clear {
                Label("The reviewed request will send an empty password.", systemImage: "exclamationmark.triangle")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.warning)
                    .accessibilityIdentifier("settings.pools.passwordClearNotice")
            } else {
                Text("The existing password stays in place and is redacted in the request details.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
            }

            if poolMode == "slot" {
                Toggle(
                    "I understand this replaces the entire slot",
                    isOn: $poolReplacementAcknowledged
                )
                .tint(FleetTheme.accent)
                .accessibilityIdentifier("settings.pools.replacementAcknowledgement")
                Text(
                    "A slot update is a full replacement. Fields not included by the firmware contract "
                        + "can reset, so review the complete JSON before confirming."
                )
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.warning)
            }
            proposalReviewButton("Review pool change", action: reviewPool)
                .disabled(poolMode == "slot" && !poolReplacementAcknowledged)
                .accessibilityIdentifier("settings.pools.review")
            Text("Review and confirm before sending to your miner.")
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            if poolMode == "slot" {
                NavigationLink("Delete slot \(slot)…") {
                    MinerEndpointView(device: device, store: store, endpoint: .deletePool(slot))
                }
                .fleetFont(.subheadline).foregroundStyle(FleetTheme.accent)
            }
        }
    }
}
