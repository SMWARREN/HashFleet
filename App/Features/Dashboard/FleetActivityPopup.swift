import SwiftUI
import HashFleetCore

/// A unified read-only activity surface. Displaying history never changes alert delivery.
struct FleetActivityPopup: View {
    let store: FleetStore
    @Bindable var preferences: FleetPreferences

    init(store: FleetStore) {
        self.store = store
        self.preferences = store.preferences
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(store.isDemo ? "Fleet activity · DEMO" : "Fleet activity", systemImage: "bell.badge")
                    .fleetFont(.headline)
                Toggle("Session-best alerts", isOn: $preferences.sessionBestNotificationsEnabled)
                    .disabled(!preferences.bestShareNotificationsEnabled)
                    .accessibilityIdentifier("activity.sessionAlerts")
                if !preferences.bestShareNotificationsEnabled {
                    Text("Best-share alerts are off. Enable them in Preferences to allow session-best alerts.")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Showing a session record does not send an alert. Alert delivery still requires system permission.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Legacy display choices must not hide miners or block-found history.
                // Only read-only values age on this clock. Keep interactive controls outside
                // its subtree so a freshness refresh cannot interrupt an in-flight gesture.
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    sessionSection(now: context.date)
                }
                notificationsSection
            }
            .padding(16)
        }
        .frame(idealWidth: 360, maxHeight: 520)
        .background(FleetTheme.canvas)
        .foregroundStyle(FleetTheme.ink)
        .tint(FleetTheme.accent)
        .accessibilityIdentifier("activity.popup")
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent notifications")
                .fleetFont(.subheadline, weight: .semibold)
            let entries = FleetActivityPresentation.notifications(from: store)
            if entries.isEmpty {
                Text("No recent notifications")
                    .fleetFont(.callout)
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityIdentifier("activity.emptyNotifications")
            } else {
                ForEach(entries) { entry in
                    // Miner name is primary so each history row is anchored to its miner, matching
                    // the session-best list above. An empty name falls back to an explicit label,
                    // never a title-only row.
                    VStack(alignment: .leading, spacing: 3) {
                        let name = entry.minerName.trimmingCharacters(in: .whitespacesAndNewlines)
                        Text(name.isEmpty ? "Unknown miner" : name).fleetFont(.callout, weight: .medium)
                        Text(entry.title).fleetFont(.caption)
                        Text(entry.occurredAt, style: .relative)
                            .fleetFont(.caption2)
                            .foregroundStyle(FleetTheme.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("activity.notifications")
    }

    private func sessionSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session best")
                .fleetFont(.subheadline, weight: .semibold)
            Text("Each miner's best share since its last session reset. This is not a solved-block claim.")
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.visibleDevices.isEmpty {
                Text("Add a miner to see its session best.")
                    .fleetFont(.callout)
                    .foregroundStyle(FleetTheme.secondary)
            }
            ForEach(store.visibleDevices) { device in
                let value = FleetActivityPresentation.sessionBest(
                    snapshot: store.snapshots[device.id], isDemo: store.isDemo, now: now)
                HStack(alignment: .firstTextBaseline) {
                    Text(device.name).lineLimit(2)
                    Spacer(minLength: 12)
                    Text(value ?? "Not reported")
                        .monospacedDigit()
                        .foregroundStyle(value == nil ? FleetTheme.secondary : FleetTheme.ink)
                }
                .fleetFont(.callout)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(device.name), session best \(value ?? "not currently reported")")
            }
        }
        .accessibilityIdentifier("activity.sessionBest")
    }
}
