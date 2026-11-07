import AppIntents

/// App-only registration for Siri and Shortcuts. The shared intent itself remains target-safe for the
/// widget extension, while this provider is deliberately kept out of the widget target.
@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
struct FleetSystemShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenFleetIntent(),
            phrases: [
                "Open \(.applicationName) fleet",
                "Show \(.applicationName) fleet"
            ],
            shortTitle: "Open Hash Fleet",
            systemImageName: "arrow.up.forward.app"
        )
        AppShortcut(
            intent: GetLastSavedFleetSummaryIntent(),
            phrases: [
                "Get the last saved \(.applicationName) fleet summary",
                "Read my last saved \(.applicationName) fleet summary"
            ],
            shortTitle: "Last saved fleet",
            systemImageName: "gauge.with.dots.needle.67percent"
        )
        AppShortcut(
            intent: RestartFleetMinerIntent(),
            phrases: [
                "Restart \(.applicationName) miner \(\.$target)",
                "Reboot \(.applicationName) miner \(\.$target)"
            ],
            shortTitle: "Restart miner",
            systemImageName: "arrow.clockwise.circle.fill"
        )
        AppShortcut(
            intent: SetFleetMinerFrequencyIntent(),
            phrases: [
                "Set frequency on \(.applicationName) miner \(\.$target)",
                "Set \(.applicationName) miner \(\.$target) frequency"
            ],
            shortTitle: "Set miner frequency",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: SetFleetMinerFanSpeedIntent(),
            phrases: [
                "Set fan speed on \(.applicationName) miner \(\.$target)",
                "Set \(.applicationName) miner \(\.$target) fan speed"
            ],
            shortTitle: "Set miner fan speed",
            systemImageName: "fanblades.fill"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .orange }
}
