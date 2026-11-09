import Foundation
import Observation
import HashFleetCore

/// Local device list management for FleetStore (add, rename, validation).
/// These change the app's local list only, never miner settings.
extension FleetStore {
    func add(name: String, address: String) throws {
        let trimmedName = try validatedLocalName(name)
        let candidate = MinerDevice(
            name: trimmedName,
            address: address.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let url = try candidate.validatedURL()
        let existing = isDemo ? savedDevices : devices
        guard !existing.contains(where: { (try? $0.validatedURL()) == url }) else {
            throw FleetError.duplicate
        }
        // A miner added under a second address (its IP and its mDNS hostname both resolve to the
        // same hardware) cannot be caught here because we do not know the new address's MAC until
        // it is probed. The post-refresh `deduplicateDevicesByMAC()` collapses that case once a
        // snapshot arrives.
        if isDemo { clearDemo() }
        devices.append(
            MinerDevice(
                id: candidate.id,
                name: trimmedName.isEmpty
                    ? MinerDisplayName.automatic(info: nil, address: url.absoluteString) : trimmedName,
                address: url.absoluteString,
                usesAutomaticName: trimmedName.isEmpty
            )
        )
        persist()
    }

    /// Adds an XMRig HTTP API endpoint. The bearer token is stored in Keychain and only its opaque
    /// reference is persisted with the device. Validation is performed by the Add Miner flow before
    /// this local save so this method never contacts or changes the miner.
    func addXMRig(name: String, address: String, bearerToken: String) throws {
        let trimmedName = try validatedLocalName(name)
        let candidate = MinerDevice(
            name: trimmedName,
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .xmrig
        )
        let url = try candidate.validatedURL()
        let existing = isDemo ? savedDevices : devices
        guard !existing.contains(where: { (try? $0.validatedURL()) == url }) else {
            throw FleetError.duplicate
        }
        if isDemo { clearDemo() }

        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = token.isEmpty ? nil : try MinerCredentialStore.save(token: token)
        devices.append(
            MinerDevice(
                id: candidate.id,
                name: trimmedName.isEmpty ? "XMRig on \(url.host ?? "Mac")" : trimmedName,
                address: url.absoluteString,
                kind: .xmrig,
                usesAutomaticName: trimmedName.isEmpty,
                keychainCredentialReference: reference
            )
        )
        persist()
    }

    /// Local app metadata only. Works offline and never changes the firmware hostname.
    /// Leaving the name blank restores the detected model name.
    func rename(_ device: MinerDevice, name: String) throws {
        guard !isDemo else { throw FleetError.demoReadOnly }
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { throw FleetError.missingDevice }
        let name = try validatedLocalName(name)
        devices[index].usesAutomaticName = name.isEmpty
        devices[index].name =
            name.isEmpty
            ? MinerDisplayName.automatic(info: snapshots[device.id]?.info, address: devices[index].address)
            : name
        persist()
    }

    func validatedLocalName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 64,
            !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw FleetError.invalidName
        }
        return trimmed
    }

    /// Collapses devices that are the same physical miner reached through different addresses
    /// (for example its IP `192.0.2.226` and its mDNS name `bitaxe-naja-duo.local`). The
    /// add-time guard only rejects byte-identical URLs, so a miner added both ways appears twice.
    /// Once each device has a snapshot we can compare the hardware MAC address, which is stable
    /// across IP and hostname. Keeps the first device per MAC (preserving a user-set name and its
    /// tracking history) and removes the later duplicates. No-op in demo mode.
    ///
    /// The history transfer must commit before removal. Failure retains both devices for retry.
    func deduplicateDevicesByMAC() async {
        guard !isDemo, !Task.isCancelled, !isDeduplicatingDevices else { return }
        isDeduplicatingDevices = true
        defer { isDeduplicatingDevices = false }
        let token = generation
        var seenMAC: [String: MinerDevice] = [:]
        var duplicates: [(duplicate: MinerDevice, survivor: MinerDevice, mac: String)] = []
        for device in devices {
            let mac = snapshots[device.id]?.info?.macAddress ?? ""
            guard !mac.isEmpty else { continue }
            if let survivor = seenMAC[mac] {
                duplicates.append((duplicate: device, survivor: survivor, mac: mac))
            } else {
                seenMAC[mac] = device
            }
        }
        guard !duplicates.isEmpty else { return }

        for (duplicate, survivor, mac) in duplicates {
            guard matchesDuplicate(duplicate, survivor: survivor, mac: mac, token: token) else { return }
            achievementMergeProtectedIDs = [duplicate.id, survivor.id]
            defer { achievementMergeProtectedIDs = [] }
            let previousAlias = achievementAliases[duplicate.id]
            // Pending MainActor achievement tasks resolve identity immediately before enqueueing
            // their database write. Writes already enqueued precede this merge transaction.
            achievementAliases[duplicate.id] = survivor.id
            do {
                try await achievementMerger(duplicate.id, survivor.id)
                guard matchesDuplicate(duplicate, survivor: survivor, mac: mac, token: token) else {
                    achievementAliases[duplicate.id] = previousAlias
                    return
                }
                remove(duplicate, deleteAchievementHistory: false)
            } catch {
                achievementAliases[duplicate.id] = previousAlias
                persistenceError = "A duplicate miner was kept because its achievement history could not be merged. It will retry on refresh."
            }
        }
    }

    private func matchesDuplicate(_ duplicate: MinerDevice, survivor: MinerDevice, mac: String, token: UUID) -> Bool {
        !Task.isCancelled && !isDemo && generation == token
            && [duplicate, survivor].allSatisfy { candidate in
                devices.contains { $0.id == candidate.id && $0.address == candidate.address && $0.kind == candidate.kind }
                    && snapshots[candidate.id]?.info?.macAddress == mac
            }
    }

    /// Resolves queued writes from a removed duplicate to its still-present survivor.
    func achievementDeviceID(for original: UUID) -> UUID? {
        guard !isDemo else { return nil }
        var resolved = original
        var visited: Set<UUID> = []
        while let next = achievementAliases[resolved] {
            guard visited.insert(resolved).inserted else { return nil }
            resolved = next
        }
        return devices.contains { $0.id == resolved } ? resolved : nil
    }

}
