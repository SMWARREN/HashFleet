import SwiftUI
import HashFleetCore

/// Discoverable native controls next to the miner list, using the existing saved preferences.
extension DashboardView {
    var minerDisplayMenu: some View {
        @Bindable var preferences = store.preferences
        return Menu {
            Picker("Sort miners", selection: $preferences.sort) {
                ForEach(FleetPreferences.SortOption.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            Toggle("Ascending", isOn: $preferences.ascending)
            Toggle("Compact cards", isOn: usesNumberFirstOverview ? $numberFirstCompactCards : $preferences.compactCards)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
                .fleetFont(.footnote, weight: .semibold)
                .foregroundStyle(FleetTheme.ink)
                .frame(minWidth: 48, minHeight: 48)
                .contentShape(Rectangle())
        }
        .fleetDesignedMenu()
        .accessibilityLabel("Sort and display miners")
        .accessibilityIdentifier("dashboard.minerDisplay")
    }
}

extension DashboardView {
    // Dashboard footer and list summaries.
    var footer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "network")
            Text(
                store.isDemo
                    ? "Demo data stays separate from your real fleet."
                    : (FleetLayout.isMac
                        ? "Direct to your miners. Private by design.\nPress ⌘R to refresh your fleet."
                        : "Direct to your miners. Private by design.\nPull down to refresh your fleet.")
            )
        }
        .fleetFont(.footnote)
        .foregroundStyle(FleetTheme.secondary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 2)
    }

    var filteredDevices: [MinerDevice] {
        let devices = store.preferences.sorted(store.visibleDevices, snapshots: store.snapshots)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return devices }
        return devices.filter { device in
            device.name.localizedCaseInsensitiveContains(query)
                || device.address.localizedCaseInsensitiveContains(query)
                || store.snapshots[device.id]?.info?.asicModel.localizedCaseInsensitiveContains(query) == true
        }
    }

    var attentionSummary: FleetAttentionSummary {
        FleetAttentionSummary(
            devices: store.visibleDevices,
            snapshots: store.snapshots,
            liveConnectionErrors: store.liveConnectionErrors
        )
    }

    var dashboardListSummary: FleetDashboardListSummary {
        FleetDashboardListSummary(
            totalCount: store.visibleDevices.count,
            onlineCount: store.onlineCount,
            attentionCount: attentionSummary.count,
            isRefreshing: store.isRefreshing,
            reconnectingCount: store.reconnectingCount
        )
    }
}
