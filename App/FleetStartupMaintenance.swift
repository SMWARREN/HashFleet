import Foundation
import HashFleetCore

/// Startup cleanups are serialized, success-aware and scoped to the store's preferences.
@MainActor
struct FleetStartupMaintenance {
    enum Cleanup: CaseIterable, Hashable {
        case phantomBlocks, bestShareV1, bestShareV2, orphanedAchievements
        case sessionBestShares, pollingDuplicates, chronologicalRecords

        var completionKey: String? {
            switch self {
            case .phantomBlocks: "app.hashfleet.phantomBlockPurge.v1"
            case .bestShareV1: "app.hashfleet.bestShareDedupe.v1"
            case .bestShareV2: "app.hashfleet.bestShareDedupe.v2"
            case .orphanedAchievements: "app.hashfleet.orphanedAchievementsPurge.v1"
            case .sessionBestShares: "app.hashfleet.sessionBestSharePurge.v1"
            case .pollingDuplicates: nil
            case .chronologicalRecords: "app.hashfleet.chronologicalBestShareRecompute.v1"
            }
        }
    }

    typealias Operation = @MainActor (Cleanup, Set<String>) async throws -> Void
    private static var inFlight: Set<ObjectIdentifier> = []
    private let defaults: UserDefaults
    private let isDemo: @MainActor () -> Bool
    private let currentMinerIds: @MainActor () -> Set<String>
    private let perform: Operation

    init(store: FleetStore) {
        self.init(
            defaults: store.defaults,
            isDemo: { store.isDemo },
            currentMinerIds: { Set(store.devices.map { $0.id.uuidString }) },
            perform: Self.performDatabaseCleanup
        )
    }

    /// Tests inject operations and a unique preference suite, never the production singleton.
    init(
        defaults: UserDefaults,
        isDemo: @escaping @MainActor () -> Bool,
        currentMinerIds: @escaping @MainActor () -> Set<String>,
        perform: @escaping Operation
    ) {
        self.defaults = defaults
        self.isDemo = isDemo
        self.currentMinerIds = currentMinerIds
        self.perform = perform
    }

    @discardableResult
    func run() -> Task<Void, Never>? {
        guard !isDemo() else { return nil }
        return Task { await runNow() }
    }

    /// Rechecks Demo at execution and between awaits. A failed cleanup remains retryable.
    func runNow() async {
        guard !Task.isCancelled, !isDemo() else { return }
        let identity = ObjectIdentifier(defaults)
        guard Self.inFlight.insert(identity).inserted else { return }
        defer { Self.inFlight.remove(identity) }
        for cleanup in Cleanup.allCases {
            guard !Task.isCancelled, !isDemo() else { return }
            if let key = cleanup.completionKey, defaults.bool(forKey: key) { continue }
            let minerIds = currentMinerIds()
            if cleanup == .orphanedAchievements && minerIds.isEmpty { continue }
            do {
                try await perform(cleanup, minerIds)
                guard !Task.isCancelled, !isDemo() else { return }
                if let key = cleanup.completionKey { defaults.set(true, forKey: key) }
            } catch {
                // Checked database APIs already log the failure. Do not consume its migration flag.
                continue
            }
        }
    }

    private static func performDatabaseCleanup(_ cleanup: Cleanup, minerIds: Set<String>) async throws {
        // Only evaluated after the Demo guards, never while constructing a Demo helper.
        let database = MinerTelemetryDatabase.shared
        switch cleanup {
        case .phantomBlocks:
            try await database.purgePhantomBlockAchievementsChecked()
        case .bestShareV1, .bestShareV2:
            try await database.deduplicateBestShareAchievementsChecked()
        case .orphanedAchievements:
            try await database.purgeOrphanedAchievementsChecked(keepingMinerIds: minerIds)
        case .sessionBestShares:
            try await database.purgeSessionBestShareAchievementsChecked()
        case .pollingDuplicates:
            try await database.purgePollingDuplicatesOfScoreboardAchievementsChecked()
        case .chronologicalRecords:
            try await database.recomputeChronologicalBestShareRecordsChecked()
        }
    }
}
