import Foundation

/// Closing the transient status popover must precede workspace navigation. The main
/// window and monitoring process are not closed. Injected actions also keep this
/// ordering testable without creating a status item or activating an application.
@MainActor
enum FleetMacMenuNavigation {
    static func select(
        _ destination: FleetSidebarDestination,
        dismiss: () -> Void, open: (FleetSidebarDestination) -> Void
    ) {
        dismiss()
        open(destination)
    }

    static func destination(minerID: UUID?, availableIDs: Set<UUID>) -> FleetSidebarDestination {
        guard let minerID, availableIDs.contains(minerID) else { return .overview }
        return .miner(minerID)
    }
}
