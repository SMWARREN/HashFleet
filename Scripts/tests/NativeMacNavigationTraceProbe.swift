// Standalone, non-app verifier for the ACTUAL MacApp/FleetMacNavigationState.swift.
// No NSApplication, NSWindow, defaults, networking or hardware is created.
// Compile together with that production file, not with copied trace implementation.
// This minimal enum substitutes only the sidebar type needed to compile the state owner.
// This is NOT native-window convergence or Add All workflow acceptance.
import SwiftUI

enum FleetSidebarDestination: Hashable {
    case overview
    case settings
}

@main
@MainActor
struct NativeMacNavigationTraceProbe {
    static func main() {
        precondition(!FleetMacNavigationTrace.isEnabled(arguments: []))
        precondition(!FleetMacNavigationTrace.isEnabled(arguments: ["--demo", "--ui-testing"]))
        precondition(!FleetMacNavigationTrace.isEnabled(arguments: ["--trace-fleet-navigation=false"]))
        precondition(FleetMacNavigationTrace.isEnabled(arguments: ["--trace-fleet-navigation"]))

        var budget = FleetMacNavigationTrace.Budget()
        for _ in 0..<256 { precondition(budget.admit() == .record) }
        precondition(budget.count == 256)
        precondition(budget.admit() == .exhausted)
        for _ in 0..<1_000 { precondition(budget.admit() == .drop) }
        precondition(budget.count == 256)
        for limit in [0, -1] {
            var empty = FleetMacNavigationTrace.Budget(limit: limit)
            precondition(empty.admit() == .exhausted)
            precondition(empty.admit() == .drop)
            precondition(empty.count == 0)
        }

        var detailWasEvaluated = false
        func detail() -> String { detailWasEvaluated = true; return "synthetic-only" }
        FleetMacNavigationTrace.record("probe.optIn", detail(), stack: true)
        precondition(detailWasEvaluated == FleetMacNavigationTrace.enabled)

        let state = FleetMacNavigationState()
        precondition(state.sidebarSelection == .overview)
        precondition(state.fleetPath.count == 0)
        state.fleetPath.append("synthetic-route")
        precondition(state.fleetPath.count == 1)
        state.select(.settings)
        precondition(state.sidebarSelection == .settings)
        precondition(state.fleetPath.count == 0)
        state.sidebarSelection = nil
        precondition(state.sidebarSelection == nil)
        print("PASS production trace/state: opt-in=\(FleetMacNavigationTrace.enabled), lazy details, finite budget, select/path semantics. No app/window created.")
    }
}
