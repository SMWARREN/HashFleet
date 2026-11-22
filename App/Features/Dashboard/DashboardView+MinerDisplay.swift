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
