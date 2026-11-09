import Foundation

/// Process-local bridge from the live app store to background Siri execution.
/// Defaults to blocked until the production store initializes. No widget cache or
/// persisted opt-in is used. Every read and write of the flag is protected by the lock.
final class FleetHardwareControlGate: @unchecked Sendable {
    static let shared = FleetHardwareControlGate()
    private let lock = NSLock()
    private var blocked = true

    var isBlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return blocked
    }

    func update(isDemo: Bool) {
        lock.lock()
        defer { lock.unlock() }
        blocked = isDemo
    }
}
