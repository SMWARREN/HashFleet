import Foundation
import Observation

/// The Watch's own miner list and last successful readings.
///
/// All mutation happens on the main actor. Network reads run off the main actor through the injected client,
/// and results are applied only if the miner is still present, so a removed device never reappears.
@MainActor
@Observable
public final class WatchFleetStore {
    public private(set) var miners: [WatchMiner] = []
    public private(set) var readings: [UUID: WatchMinerReading] = [:]
    public private(set) var failures: [UUID: String] = [:]
    public private(set) var isRefreshing = false
    public private(set) var storageError: String?
    public let isDemo: Bool

    @ObservationIgnored private let persistence: WatchFleetPersistence
    @ObservationIgnored private let client: any WatchMinerReadingClient
    @ObservationIgnored private var writesBlocked = false
    @ObservationIgnored private var inflightRefresh: Task<Void, Never>?

    /// Maximum miners read at once.
    static let refreshConcurrency = 4

    /// The Watch app's own storage file, or nil if the platform has no Application Support directory.
    public nonisolated static var defaultStorageURL: URL? { WatchFleetPersistence.defaultURL() }

    /// - Parameters:
    ///   - storageURL: JSON file for configuration and last readings. Pass `nil` to disable persistence.
    ///   - client: Source of readings. Defaults to the direct read-only HTTP client.
    public init(
        storageURL: URL? = WatchFleetStore.defaultStorageURL,
        client: any WatchMinerReadingClient = WatchMinerHTTPClient()
    ) {
        self.isDemo = false
        self.persistence = WatchFleetPersistence(url: storageURL)
        self.client = client
        switch persistence.load() {
        case .empty:
            break
        case let .loaded(snapshot):
            miners = snapshot.miners
            readings = Dictionary(uniqueKeysWithValues: snapshot.readings.map { ($0.minerID, $0) })
        case .corrupt:
            storageError = "Saved miners couldn't be read. The old file was kept aside. Add your miners again."
        case .corruptUnpreserved:
            // Saving now would overwrite the only copy of unreadable data, so all writes stay blocked.
            writesBlocked = true
            storageError = "Saved miners couldn't be read or set aside, so changes are paused to protect them."
        }
    }

    private init(demoMiners: [WatchMiner], demoReadings: [WatchMinerReading], client: any WatchMinerReadingClient) {
        self.isDemo = true
        self.persistence = WatchFleetPersistence(url: nil)
        self.client = client
        self.miners = demoMiners
        self.readings = Dictionary(uniqueKeysWithValues: demoReadings.map { ($0.minerID, $0) })
    }

    // MARK: - Demo

    private struct DemoMinerFixture {
        let name: String
        let address: String
        let hashrateGHs: Double
        let powerWatts: Double
        let chipTemperatureC: Double
        let vrTemperatureC: Double
        let uptimeSeconds: Double
        let acceptedShares: Int
        let rejectedShares: Int
    }

    /// Fixture-only store. It has no storage and its client never opens a network connection.
    public static func demo() -> WatchFleetStore {
        let now = Date()
        let samples: [DemoMinerFixture] = [
            DemoMinerFixture(
                name: "Demo Gamma",
                address: "192.168.0.101",
                hashrateGHs: 1_020,
                powerWatts: 14.2,
                chipTemperatureC: 58,
                vrTemperatureC: 49,
                uptimeSeconds: 93_600,
                acceptedShares: 1_204,
                rejectedShares: 3
            ),
            DemoMinerFixture(
                name: "Demo Duo",
                address: "192.168.0.102",
                hashrateGHs: 2_410,
                powerWatts: 36.8,
                chipTemperatureC: 63,
                vrTemperatureC: 52,
                uptimeSeconds: 410_000,
                acceptedShares: 5_882,
                rejectedShares: 11
            ),
            DemoMinerFixture(
                name: "Demo Bitaxe",
                address: "192.168.0.103",
                hashrateGHs: 505,
                powerWatts: 11.9,
                chipTemperatureC: 61,
                vrTemperatureC: 47,
                uptimeSeconds: 7_320,
                acceptedShares: 212,
                rejectedShares: 0
            )
        ]
        var miners: [WatchMiner] = []
        var readings: [WatchMinerReading] = []
        for sample in samples {
            guard let miner = try? WatchMiner(name: sample.name, address: sample.address) else { continue }
            miners.append(miner)
            readings.append(WatchMinerReading(
                minerID: miner.id,
                observedAt: now,
                hashrateGHs: sample.hashrateGHs,
                powerWatts: sample.powerWatts,
                chipTemperatureC: sample.chipTemperatureC,
                vrTemperatureC: sample.vrTemperatureC,
                uptimeSeconds: sample.uptimeSeconds,
                acceptedShares: sample.acceptedShares,
                rejectedShares: sample.rejectedShares,
                isMiningPaused: false
            ))
        }
        return WatchFleetStore(demoMiners: miners, demoReadings: readings, client: DemoReadingClient())
    }

    // MARK: - Configuration

    /// Adds a miner after validating its name and address.
    public func addMiner(name: String, address: String) throws {
        guard !isDemo else { throw WatchFleetStoreError.demoIsReadOnly }
        let miner = try WatchMiner(name: name, address: address)
        guard !miners.contains(where: { $0.address == miner.address }) else {
            throw WatchFleetStoreError.duplicateMiner
        }
        guard miners.count < WatchFleetLimits.maximumMiners else { throw WatchFleetStoreError.limitReached }
        let updated = miners + [miner]
        try persist(miners: updated, readings: readings)
        miners = updated
        storageError = nil
    }

    /// Removes the miner and its cached reading from this Watch only.
    public func removeMiner(id: UUID) throws {
        guard !isDemo else { throw WatchFleetStoreError.demoIsReadOnly }
        guard miners.contains(where: { $0.id == id }) else { throw WatchFleetStoreError.minerNotFound }
        let updatedMiners = miners.filter { $0.id != id }
        var updatedReadings = readings
        updatedReadings[id] = nil
        try persist(miners: updatedMiners, readings: updatedReadings)
        miners = updatedMiners
        readings = updatedReadings
        failures[id] = nil
        storageError = nil
    }

    /// Appends miners whose endpoint is not already present and returns how many were added.
    ///
    /// Existing entries and cached readings are untouched. An incoming identifier that collides with a different
    /// existing endpoint is given a fresh one. Nothing is added unless the whole merge fits within the limit and
    /// is saved successfully.
    @discardableResult
    public func importMiners(_ incoming: [WatchMiner]) throws -> Int {
        guard !isDemo else { throw WatchFleetStoreError.demoIsReadOnly }
        var knownAddresses = Set(miners.map(\.address))
        var usedIDs = Set(miners.map(\.id))
        var additions: [WatchMiner] = []
        for candidate in incoming {
            guard knownAddresses.insert(candidate.address).inserted else { continue }
            if usedIDs.insert(candidate.id).inserted {
                additions.append(candidate)
            } else {
                var fresh = UUID()
                while !usedIDs.insert(fresh).inserted { fresh = UUID() }
                additions.append(try WatchMiner(id: fresh, name: candidate.name, address: candidate.address))
            }
        }
        guard !additions.isEmpty else { return 0 }
        guard miners.count + additions.count <= WatchFleetLimits.maximumMiners else {
            throw WatchFleetStoreError.limitReached
        }
        let updated = miners + additions
        try persist(miners: updated, readings: readings)
        miners = updated
        storageError = nil
        return additions.count
    }

    // MARK: - Refresh

    /// Reads every miner once. Concurrent calls share one pass. Cancelling the caller cancels the pass and
    /// records no failures for work that did not finish.
    public func refresh() async {
        if let inflightRefresh {
            // Joining callers wait for the shared pass but never cancel it on its owner's behalf.
            await inflightRefresh.value
            return
        }
        if isDemo {
            restampDemoReadings()
            return
        }
        guard !miners.isEmpty else { return }
        let task = Task { await self.performRefresh() }
        inflightRefresh = task
        isRefreshing = true
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func performRefresh() async {
        defer {
            isRefreshing = false
            inflightRefresh = nil
        }
        let targets = miners
        let client = self.client
        var appliedReading = false

        await withTaskGroup(of: (WatchMiner, Result<WatchMinerReading, any Error>).self) { group in
            var iterator = targets.makeIterator()
            var running = 0
            func addNext(_ group: inout TaskGroup<(WatchMiner, Result<WatchMinerReading, any Error>)>) -> Bool {
                guard let miner = iterator.next() else { return false }
                group.addTask {
                    do { return (miner, .success(try await client.fetch(miner))) } catch { return (miner, .failure(error)) }
                }
                return true
            }
            while running < Self.refreshConcurrency, addNext(&group) { running += 1 }
            while let (miner, result) = await group.next() {
                if apply(result, for: miner) { appliedReading = true }
                if !Task.isCancelled, addNext(&group) { continue }
                running -= 1
            }
        }

        if appliedReading, !writesBlocked {
            do {
                try persist(miners: miners, readings: readings)
            } catch {
                storageError = "The Watch couldn't save the latest readings."
            }
        }
    }

    /// Applies one result if the miner is still present. Returns true when a new reading was stored.
    private func apply(_ result: Result<WatchMinerReading, any Error>, for miner: WatchMiner) -> Bool {
        // A miner removed (or replaced) while its read was in flight must not come back.
        guard miners.contains(where: { $0.id == miner.id && $0.address == miner.address }) else { return false }
        switch result {
        case let .success(reading):
            guard reading.minerID == miner.id else {
                failures[miner.id] = WatchMinerFetchError.invalidResponse.errorDescription
                return false
            }
            failures[miner.id] = nil
            if let existing = readings[miner.id], existing.observedAt > reading.observedAt { return false }
            readings[miner.id] = reading
            return true
        case let .failure(error):
            // Cancellation is not a connection failure and must not be reported as one.
            if error is CancellationError || Task.isCancelled { return false }
            let message = (error as? WatchMinerFetchError)?.errorDescription
                ?? WatchMinerFetchError.unreachable.errorDescription
            failures[miner.id] = message
            return false
        }
    }

    private func restampDemoReadings() {
        let now = Date()
        for (id, reading) in readings {
            readings[id] = WatchMinerReading(
                minerID: id,
                observedAt: now,
                hashrateGHs: reading.hashrateGHs,
                powerWatts: reading.powerWatts,
                chipTemperatureC: reading.chipTemperatureC,
                vrTemperatureC: reading.vrTemperatureC,
                uptimeSeconds: reading.uptimeSeconds,
                acceptedShares: reading.acceptedShares,
                rejectedShares: reading.rejectedShares,
                isMiningPaused: reading.isMiningPaused
            )
        }
    }

    // MARK: - Persistence

    private func persist(miners: [WatchMiner], readings: [UUID: WatchMinerReading]) throws {
        guard !writesBlocked else { throw WatchFleetStoreError.persistenceFailed }
        let ids = Set(miners.map(\.id))
        let ordered = miners.compactMap { readings[$0.id] }.filter { ids.contains($0.minerID) }
        do {
            try persistence.save(WatchFleetSnapshot(miners: miners, readings: ordered))
        } catch {
            throw WatchFleetStoreError.persistenceFailed
        }
    }
}

/// Used by the demo store. It never performs any I/O.
private struct DemoReadingClient: WatchMinerReadingClient {
    func fetch(_ miner: WatchMiner) async throws -> WatchMinerReading {
        throw WatchMinerFetchError.unreachable
    }
}
