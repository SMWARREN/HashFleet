import AppIntents

/// Explicit authenticated manual reads. Automatic timeline reads require separate consent.
struct RefreshFleetWidgetIntent: AppIntent {
    static var title: LocalizedStringResource { "Refresh fleet widget" }
    static var description: IntentDescription {
        IntentDescription("Try one bounded, read-only local refresh of the prepared ASIC fleet. Keeps the last saved reading if any miner cannot be read.")
    }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    func perform() async throws -> some IntentResult {
        // Await persistence before returning. WidgetKit reloads after this action completes.
        _ = await refresh(using: FleetWidgetRefreshRunner(storage: .shared))
        return .result()
    }

    /// The same awaited action path with explicitly injected private storage and reads for tests.
    func refresh(using runner: FleetWidgetRefreshRunner) async -> FleetWidgetRefreshOutcome {
        await runner.refresh { publication in
            await FleetActivityRefreshHandoff.deliver(publication)
        }
    }
}

#if !os(macOS)
// AppIntent alone normally runs in the widget extension, which cannot update app-owned activities.
// This conformance gives the explicit, authenticated refresh app-process execution without opening UI.
extension RefreshFleetWidgetIntent: LiveActivityIntent {}
#endif
