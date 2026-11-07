import HashFleetCore
import AppIntents
import Foundation

/// Shared system-integration constants and intents. This file is intentionally safe to compile into
/// both the app and the widget extension: it does not import UIKit or touch app navigation state.
public enum FleetSystemIntegration {
    public static let fleetURL = URL(string: "hashfleet://fleet")!
    public static let widgetSharingKey = "app.hashfleet.shareWithWidgets"
}

enum FleetDestination: String, AppEnum {
    case fleet
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Destination"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.fleet: "Fleet"]
}

/// OpenIntent executes in the foreground app. A pending marker handles cold launch,
/// while the notification also handles an already-active app. No miner data is written.
enum FleetSystemNavigation {
    static let requested = Notification.Name("app.hashfleet.openFleet")
    static let pendingKey = "app.hashfleet.pendingOpenFleet"

    static func request(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingKey)
        NotificationCenter.default.post(name: requested, object: nil)
    }

    static func consume(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: pendingKey) else { return false }
        defaults.removeObject(forKey: pendingKey)
        return true
    }
}

/// Native app-opening intent, including Control Center. Custom URL schemes are
/// reserved for ordinary links, not passed through OpenURLIntent controls.
@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
struct OpenFleetIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Hash Fleet"
    static let description = IntentDescription("Open Hash Fleet's fleet dashboard.")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Destination", default: .fleet)
    var target: FleetDestination

    init() {}

    @MainActor func perform() async throws -> some IntentResult {
        FleetSystemNavigation.request()
        return .result()
    }
}

/// Pure, privacy-safe rendering for the one aggregate payload already shared with widgets.
/// No miner names, network addresses, wallet data, or credentials can enter this formatter.
struct FleetSystemSummaryFormatter {
    static func format(_ glance: FleetGlance, now: Date) -> String {
        guard glance.isValid else {
            return "The last saved fleet summary is unavailable"
                + " because it is invalid. Open Hash Fleet to"
                + " create a new snapshot."
        }

        guard glance.minerCount > 0 else {
            return "No miners are in the last saved fleet summary. Open Hash Fleet to connect a fleet."
        }

        let rate = FleetFormat.hashrateWithUnit(glance.hashrateGHs)
        let power = glance.powerWatts.formatted(.number.precision(.fractionLength(1)))
        let savedAt = glance.updatedAt.formatted(date: .abbreviated, time: .shortened)
        let stale = glance.isStale(at: now)
        let freshness = stale ? " This saved reading is stale; open Hash Fleet for a current reading." : ""
        let mode = glance.isDemo
            ? " Demo sample data; no hardware connection"
            + " is represented."
            : ""

        return "Last saved fleet: \(glance.onlineCount) of"
            + " \(glance.minerCount) online, \(rate),"
            + " \(power) watts. Saved \(savedAt).\(mode)\(freshness)"
    }
}

/// Reads only the already-aggregated FleetGlance cache, and only after explicit widget-sharing opt-in.
/// The injected loader exists for deterministic tests and never changes production behavior.
struct FleetSystemSummaryReader {
    private let defaults: UserDefaults
    private let load: () -> FleetGlance

    init(defaults: UserDefaults = .standard, load: @escaping () -> FleetGlance = { FleetGlanceStorage.shared.load() }) {
        self.defaults = defaults
        self.load = load
    }

    func summary(now: Date) -> String {
        guard defaults.bool(forKey: FleetSystemIntegration.widgetSharingKey) else {
            return "Fleet summary sharing is off. Enable"
                + " Share with Widgets in Hash Fleet to read"
                + " the last saved summary."
        }
        return FleetSystemSummaryFormatter.format(load(), now: now)
    }
}

/// Read-only Siri and Shortcuts result. It never refreshes, writes, or starts networking.
@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
struct GetLastSavedFleetSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Last Saved Fleet Summary"
    static let description = IntentDescription("Read the last aggregate fleet summary saved for widgets.")
    static var openAppWhenRun: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let summary = FleetSystemSummaryReader().summary(now: Date())
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}
