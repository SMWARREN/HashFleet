import Foundation
import HashFleetCore

/// FleetStore's narrow backup boundary. File selection and confirmation remain a UI concern; these
/// methods only export validated local configuration, preview an additive restore, and atomically
/// persist a confirmed batch.
@MainActor
extension FleetStore {
    private var fleetBackupCurrentDevices: [MinerDevice] {
        isDemo ? savedDevices : devices
    }

    func fleetBackupExportData() throws -> Data {
        guard !isDemo else { throw FleetBackupError.demoExportDisabled }
        guard unreadableStorage == nil, persistenceError == nil else {
            throw FleetBackupError.storageUnavailable
        }
        return try FleetBackup.encode(devices: devices)
    }

    func fleetBackupPreview(data: Data) throws -> FleetBackupRestorePreview {
        let document = try FleetBackup.decode(data)
        return try FleetBackup.preview(document: document, currentDevices: fleetBackupCurrentDevices)
    }

    /// Re-decodes and re-previews the exact user-selected bytes at confirmation time. An empty
    /// preview is a true no-op, including in demo mode. Non-empty batches are written once so a
    /// failed individual addition cannot leave a half-restored fleet.
    @discardableResult
    func applyFleetBackup(
        data: Data,
        expectedPreview: FleetBackupRestorePreview
    ) throws -> Int {
        guard unreadableStorage == nil, persistenceError == nil else {
            throw FleetBackupError.storageUnavailable
        }
        let document = try FleetBackup.decode(data)
        let freshPreview = try FleetBackup.preview(document: document, currentDevices: fleetBackupCurrentDevices)
        guard freshPreview == expectedPreview else {
            throw FleetBackupError.stalePreview
        }
        guard !freshPreview.additions.isEmpty else { return 0 }

        let current = fleetBackupCurrentDevices
        guard current.count + freshPreview.additions.count <= FleetBackupDocument.maxEntries else {
            throw FleetBackupError.tooManyEntries(current.count + freshPreview.additions.count)
        }
        let imported = freshPreview.additions.map { entry in
            MinerDevice(
                name: entry.name.isEmpty
                    ? MinerDisplayName.automatic(info: nil, address: entry.address)
                    : entry.name,
                address: entry.address,
                usesAutomaticName: entry.name.isEmpty
            )
        }
        let merged = current + imported
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(merged)
        } catch {
            throw FleetBackupError.persistenceFailed
        }

        // Verify UserDefaults returned the exact bytes before mutating the in-memory fleet. This is
        // a best-effort write/readback check, not a durable-disk guarantee.
        let previousData = defaults.data(forKey: Self.storageKey)
        defaults.set(encoded, forKey: Self.storageKey)
        guard defaults.data(forKey: Self.storageKey) == encoded else {
            if let previousData {
                defaults.set(previousData, forKey: Self.storageKey)
            } else {
                defaults.removeObject(forKey: Self.storageKey)
            }
            throw FleetBackupError.persistenceFailed
        }

        if isDemo {
            applyFleetBackupDemoTransition(merged: merged)
        } else {
            devices = merged
        }
        persistenceError = nil
        return imported.count
    }

    /// Do not call clearDemo after the write: its cache restoration can persist the old saved
    /// fleet while automatic names are refreshed. This is the same visible transition, performed
    /// only after the complete new value is safely stored.
    private func applyFleetBackupDemoTransition(merged: [MinerDevice]) {
        cancelRefresh()
        capabilities.reset()
        devices = merged
        savedDevices = []
        snapshots = [:]
        lastRefresh = nil
        isDemo = false
        isPoolIconDemo = false
        latestBestShareEvent = nil
        latestBlockFoundEvent = nil
        pendingBestShareEvents = []
        pendingBlockFoundEvents = []
        pendingTemperatureEvents = []
        // Keep cachedReadings for retained real devices and restore their offline snapshots after
        // leaving demo, matching the normal clear-demo transition without persisting demo data.
        restoreCachedReadings()
    }
}
