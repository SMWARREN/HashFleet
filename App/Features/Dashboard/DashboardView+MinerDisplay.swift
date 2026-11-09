import SwiftUI

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
            Toggle("Compact cards", isOn: $preferences.compactCards)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .frame(minWidth: 44, minHeight: 44)
        }
        .fleetDesignedMenu()
        .accessibilityLabel("Sort and display miners")
        .accessibilityIdentifier("dashboard.minerDisplay")
    }
}
