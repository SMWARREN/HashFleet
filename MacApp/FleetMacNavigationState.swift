import SwiftUI
import OSLog

/// Menu commands and the window keep the same reference, including after the window closes.
@MainActor
@Observable
final class FleetMacNavigationState {
    var sidebarSelection: FleetSidebarDestination? = .overview {
        didSet {
            FleetMacNavigationTrace.record(
                "native.sidebar", "old=\(String(describing: oldValue)) new=\(String(describing: sidebarSelection))",
                stack: true
            )
        }
    }
    var fleetPath = NavigationPath() {
        didSet {
            FleetMacNavigationTrace.record(
                "native.path", "oldCount=\(oldValue.count) newCount=\(fleetPath.count)", stack: true
            )
        }
    }

    func select(_ destination: FleetSidebarDestination) {
        fleetPath = NavigationPath()
        sidebarSelection = destination
    }
}

/// Diagnostic-only. No View/Observable state, defaults writes, timers, files or hardware calls.
/// The flag is opt-in and the installed app is never launched or replaced by this helper.
@MainActor
enum FleetMacNavigationTrace {
    static let enabled = isEnabled(arguments: ProcessInfo.processInfo.arguments)
    private static let logger = Logger(subsystem: "app.hashfleet.mac", category: "NavigationTrace")
    private static var budget = Budget()

    static func isEnabled(arguments: [String]) -> Bool {
        arguments.contains("--trace-fleet-navigation")
    }

    struct Budget {
        enum Admission: Equatable { case record, exhausted, drop }
        let limit: Int
        private(set) var count = 0
        private var reportedExhaustion = false

        init(limit: Int = 256) { self.limit = max(0, limit) }

        mutating func admit() -> Admission {
            guard count < limit else {
                guard !reportedExhaustion else { return .drop }
                reportedExhaustion = true
                return .exhausted
            }
            count += 1
            return .record
        }
    }

    static func record(_ event: String, _ detail: @autoclosure () -> String = "", stack: Bool = false) {
        guard enabled else { return }
        switch budget.admit() {
        case .drop:
            return
        case .exhausted:
            logger.notice("HF_NAV_TRACE exhausted limit=256. Missing later events are not evidence of no writes.")
        case .record:
            let text = detail()
            logger.notice("HF_NAV_TRACE event=\(event, privacy: .public) detail=\(text, privacy: .public)")
            if stack {
                // Compact addresses stay below unified-log message limits. Symbolicate with
                // the exact candidate UUID/dSYM, not the installed app's older symbols.
                let frames = Thread.callStackReturnAddresses.prefix(24)
                    .map { String(format: "0x%llx", $0.uint64Value) }.joined(separator: ",")
                logger.notice("HF_NAV_TRACE writer=\(event, privacy: .public) stack=\(frames, privacy: .public)")
            }
        }
    }
}
