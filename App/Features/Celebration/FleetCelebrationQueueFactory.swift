import Foundation

/// App entry points choose a bundle-scoped durable queue. Ordinary previews/tests stay isolated.
/// Directory creation, SQLite opening and schema checks belong to the storage actor.
enum FleetCelebrationQueueFactory {
    static func make(isTesting: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) -> FleetCelebrationQueue {
        if arguments.contains("--demo") || (isTesting && !arguments.contains("--ui-test-durable-celebrations")) {
            return FleetCelebrationQueue()
        }
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            let identifier = Bundle.main.bundleIdentifier ?? "app.hashfleet"
            let namespace = isTesting ? identifier + ".queue-tests" : identifier
            let directory = support.appendingPathComponent("HashFleetCelebrations", isDirectory: true)
                .appendingPathComponent(namespace, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try FleetCelebrationQueue(storageURL: directory.appendingPathComponent("pending.sqlite"))
        } catch {
            // Never claim a durable handoff by silently using an in-memory fallback.
            return FleetCelebrationQueue(unavailableMessage: "Record queue storage is unavailable: \(error.localizedDescription)")
        }
    }
}
