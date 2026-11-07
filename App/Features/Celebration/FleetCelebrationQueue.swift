import Foundation

/// Record popups stay until acknowledged. A second miner's record waits rather than replacing
/// the popup the user is still reading. Delivery's journal owns cross-launch deduplication.
struct FleetCelebrationQueue {
    private(set) var current: FleetCelebration?
    private(set) var pending: [FleetCelebration] = []

    mutating func present(_ celebration: FleetCelebration) {
        guard current?.id != celebration.id,
              !pending.contains(where: { $0.id == celebration.id }) else { return }
        if current == nil {
            current = celebration
        } else {
            pending.append(celebration)
        }
    }

    mutating func dismiss() {
        current = pending.isEmpty ? nil : pending.removeFirst()
    }

    /// An explicit session-only opt-out also clears records already waiting to be shown.
    /// Other kinds keep their current presentation and FIFO order.
    mutating func removeSessionBests() {
        pending.removeAll { $0.kind == .bestShareSession }
        if current?.kind == .bestShareSession { dismiss() }
    }
}
