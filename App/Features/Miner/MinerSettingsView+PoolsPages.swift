import SwiftUI
import HashFleetCore

/// Pool and tuning settings pages. Split from MinerSettingsView+Pages.swift for file length;
/// the cards, wording and bindings are unchanged.
extension MinerSettingsView {
    var poolsPage: some View {
        proposalPage("Pools", subtitle: "Configure pool connections and active roles.") {
            if usesFallbackPool {
                Label(
                    "This miner reports its fallback pool is selected. Share statistics may reset when pools change.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
            }
            soloPoolPresets
            configuredPoolSlots
            pools
            activePoolSlots
        }
    }

    private var usesFallbackPool: Bool {
        guard let currentInfo = store.snapshot(for: device.id)?.info else { return false }
        return MinerActivePool(info: currentInfo).isUsingFallback
    }

    /// Which configured slots the miner uses as primary and fallback. Changing a
    /// role is reviewed separately from editing the slot's connection details.
    var activePoolSlots: some View {
        settingsHubCard {
            settingsHubHeader(
                "Active pool slots",
                subtitle: "Choose the primary and fallback roles.",
                symbol: "arrow.triangle.branch"
            )
            Divider().overlay(FleetTheme.separator)
            fieldLabel("Primary slot")
            Picker("Primary slot", selection: $primarySlot) { ForEach(0..<8) { Text(poolSlotTitle($0)).tag($0) } }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            fieldLabel("Fallback slot")
            Picker("Fallback slot", selection: $secondarySlot) { ForEach(0..<8) { Text(poolSlotTitle($0)).tag($0) } }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            fieldNote("primaryPoolIndex", label: "the active pool slots")
            Text(
                ("Configure these slots first. Slot IDs are not array offsets. "
                + "Legacy firmware may not implement pool slots.")
            )
            .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            proposalReviewButton("Review active slot selection") {
                show(.settings, object: ["primaryPoolIndex": primarySlot, "secondaryPoolIndex": secondarySlot])
            }
            Text("Review and confirm before sending to your miner.")
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    var tuningPage: some View {
        MinerTuningSessionView(device: device, store: store, insights: insights)
    }

    var advancedPage: some View {
        settingsPage("Tools & firmware") {
            FleetSettingsSection("Settings editor") {
                NavigationLink {
                    MinerCustomJSONRoute(device: device, store: store, insights: insights)
                } label: {
                    Label("Request JSON editor", systemImage: "curlybraces")
                }
                .accessibilityIdentifier("settings.customJSON")
                Text(
                    "For firmware-specific settings not covered by the native forms. Inspect every field before APPLY."
                )
                .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
            }
            .listRowBackground(FleetTheme.surface)
            FleetSettingsSection("Diagnostics") {
                NavigationLink("Scan Wi-Fi networks") {
                    MinerEndpointView(device: device, store: store, endpoint: .wifiScan, insights: insights)
                }
                NavigationLink("ASIC capabilities · raw reported references") {
                    MinerEndpointView(device: device, store: store, endpoint: .asic, insights: insights)
                }
            }
            .listRowBackground(FleetTheme.surface)
            FleetSettingsSection("Firmware & maintenance") {
                NavigationLink("Firmware OTA update") {
                    MinerEndpointView(device: device, store: store, endpoint: .otaFirmware, insights: insights)
                }
                NavigationLink("Custom web UI update") {
                    MinerEndpointView(device: device, store: store, endpoint: .otaWWW, insights: insights)
                }
                Text(
                    ("Firmware updates and hardware changes carry risk. "
                    + "Read the compatibility requirements and confirm only the operation you intend.")
                )
                .fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
            }
            .listRowBackground(FleetTheme.surface)
        }
    }

}
