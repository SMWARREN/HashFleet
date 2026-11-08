import Foundation
import Observation
import HashFleetCore

#if canImport(GRDB)
import GRDB
#endif

/// WebSocket live monitoring and fallback polling for FleetStore. Moved to an extension for
/// file and type length; connection handling and retry behavior are unchanged.
extension FleetStore {
    static let liveSnapshotMaximumAge: TimeInterval = 30
    static let liveFreshnessCheckInterval: Duration = .seconds(15)

    func cancelLiveMonitoring(ownedBy token: UUID? = nil) {
        // SwiftUI can start a replacement `.task(id:)` before the cancelled task reaches its
        // defer. A stale owner must never tear down the replacement generation it no longer owns.
        if let token, token != liveGeneration { return }
        liveGeneration = UUID()
        liveTasks.values.forEach { $0.cancel() }
        liveTasks.removeAll()
        liveFlushTask?.cancel()
        liveFlushTask = nil
        pendingLiveUpdates.removeAll()
        liveAppliedDeviceIDs.removeAll()
        liveConnectedDeviceIDs.removeAll()
        liveConnectionErrors.removeAll()
    }

    /// Keeps the dashboard on one source of truth: a complete HTTP bootstrap snapshot is followed by
    /// a live WebSocket per miner, with an HTTP read used whenever the socket is unavailable or closes.
    /// The live frame is always merged into the existing complete snapshot, never rendered as a
    /// standalone partial diff.
    func runMonitoring(publish: (@MainActor (FleetGlance) async -> Void)? = nil) async {
        guard !isDemo, !Task.isCancelled else { return }
        cancelLiveMonitoring()
        beginReconnecting()
        await refresh()
        reconcileScoreboards()
        if canPublishGlance || canPublishMenuBar, let publish {
            await publish(glance)
        }
        guard preferences.realtimeMonitoring, !isDemo, !Task.isCancelled, !visibleDevices.isEmpty else { return }

        let token = UUID()
        liveGeneration = token
        for device in visibleDevices {
            liveTasks[device.id] = Task { [weak self] in
                await self?.monitor(device: device, token: token)
            }
        }

        defer { cancelLiveMonitoring(ownedBy: token) }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(86_400)) } catch { return }
        }
    }

    /// Pulls each miner's own firmware scoreboard (`/api/system/scoreboard`) — its NVS-persisted,
    /// authoritative top best-share history that survives reboots and app reinstalls — and
    /// reconciles any not-yet-recorded entries into the achievements database. This runs once per
    /// foreground refresh cycle (the list is small and mostly static, unlike live telemetry) and
    /// fills in genuine historical records the app's own polling-based detection could have missed
    /// (for example while the app wasn't running). Firmware without this endpoint fails silently
    /// per device; it never blocks the rest of the fleet or the normal info refresh.
    private func reconcileScoreboards() {
        guard !isDemo, preferences.telemetryStorageEnabled, !visibleDevices.isEmpty else { return }
        let targets = visibleDevices
        let session = session
        Task { @MainActor in
            let results = await Self.fetchScoreboards(targets: targets, session: session)
            guard !Task.isCancelled else { return }
            for result in results {
                guard let achievementID = self.achievementDeviceID(for: result.deviceID) else { continue }
                await MinerTelemetryDatabase.shared.reconcileScoreboard(
                    minerId: achievementID.uuidString,
                    entries: result.entries
                )
                self.scoreboardSupportedDeviceIDs.insert(result.deviceID)
            }
        }
    }

    private nonisolated static func fetchScoreboards(
        targets: [MinerDevice],
        session: URLSession
    ) async -> [ScoreboardFetchResult] {
        await withTaskGroup(of: ScoreboardFetchResult?.self, returning: [ScoreboardFetchResult].self) { group in
            for device in targets where device.kind == .espMiner {
                group.addTask(priority: .utility) {
                    guard let entries = try? await MinerAPIClient(device: device, session: session).scoreboard(),
                        !entries.isEmpty
                    else { return nil }
                    return ScoreboardFetchResult(deviceID: device.id, entries: entries)
                }
            }
            var results: [ScoreboardFetchResult] = []
            results.reserveCapacity(targets.count)
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }
    }

    func monitor(device: MinerDevice, token: UUID) async {
        if device.kind == .xmrig {
            await monitorXMRig(device: device, token: token)
            return
        }
        var retrySeconds = 1.0

        while !Task.isCancelled, token == liveGeneration {
            do {
                try await monitorLiveStreamIteration(device: device, token: token)
                retrySeconds = 1
            } catch {
                guard !Task.isCancelled, token == liveGeneration else { return }
                liveConnectedDeviceIDs.remove(device.id)
                liveConnectionErrors[device.id] = error.localizedDescription
                await fallbackPoll(device, token: token)
                do { try await Task.sleep(for: .seconds(retrySeconds)) } catch { return }
                retrySeconds = min(retrySeconds * 2, 60)
            }
        }

        guard token == liveGeneration else { return }
        liveConnectedDeviceIDs.remove(device.id)
        liveTasks[device.id] = nil
    }

    private func monitorLiveStreamIteration(device: MinerDevice, token: UUID) async throws {
        let stream = try MinerAPIClient(device: device, session: session).liveStream()
        try await consumeLiveStream(stream, device: device, token: token)
    }

    /// Shared by the real WebSocket path and deterministic stream lifecycle tests.
    func consumeLiveStream(
        _ stream: AsyncThrowingStream<MinerWebSocketMessage, Error>,
        device: MinerDevice,
        token: UUID
    ) async throws {
        liveConnectionErrors.removeValue(forKey: device.id)
        liveConnectedDeviceIDs.insert(device.id)
        var appliedFrame = false
        var nextBootstrapAttempt = Date.distantPast
        #if os(macOS)
        liveAppliedDeviceIDs.remove(device.id)
        #endif

        // Some firmware leaves the WebSocket open after it stops delivering frames. That
        // looks connected in the UI but freezes every reading until a manual refresh. Keep
        // the low-cost live path while it is healthy, and issue a bounded HTTP read only
        // when the complete snapshot has not advanced for the expected live cadence.
        let freshnessWatchdog = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, token == self.liveGeneration {
                do {
                    try await Task.sleep(for: Self.liveFreshnessCheckInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled, token == self.liveGeneration else { return }
                if self.needsFallbackPoll(for: device.id) {
                    await self.fallbackPoll(device, token: token)
                }
            }
        }
        defer { freshnessWatchdog.cancel() }

        for try await message in stream {
            try Task.checkCancellation()
            guard token == liveGeneration else { return }
            // The socket can connect while the launch-time HTTP bootstrap is still
            // unavailable. Live frames are partial and cannot safely replace a complete
            // snapshot, so obtain that base automatically instead of waiting for a manual
            // Refresh tap. Retry at a bounded interval while the healthy socket remains open.
            if needsLiveBootstrap(for: device.id), Date() >= nextBootstrapAttempt {
                await fallbackPoll(device, token: token)
                nextBootstrapAttempt = Date().addingTimeInterval(15)
            }
            // The bootstrap await may outlive this generation. Its buffered frame must
            // not be applied to a replacement owner's snapshot or pending update batch.
            guard !Task.isCancelled, token == liveGeneration else { return }
            #if os(macOS)
            // ESP-Miner sends several partial frames per second. Publishing each one re-renders
            // every observing screen and starved the Mac main thread (scroll, sidebar, menus).
            // Merge frames and publish the whole fleet together at most once per interval, so four
            // miners cost one render pass instead of four. The final frame is never lost.
            if let update = Self.liveUpdate(from: message) {
                pendingLiveUpdates[device.id, default: PendingLiveUpdate()].merge(update)
                scheduleLiveFlush(token: token)
            }
            #else
            appliedFrame = applyLiveMessage(message, for: device.id) || appliedFrame
            #endif
        }
        // next() can finish after a replacement starts without yielding another frame.
        guard !Task.isCancelled, token == liveGeneration else { return }
        #if os(macOS)
        if token == liveGeneration {
            flushLiveUpdate(for: device.id)
            appliedFrame = liveAppliedDeviceIDs.remove(device.id) != nil
        }
        #endif

        liveConnectedDeviceIDs.remove(device.id)
        if !appliedFrame { await fallbackPoll(device, token: token) }
        guard !Task.isCancelled, token == liveGeneration else { return }
        // A miner can close a healthy socket after sending a snapshot. Avoid reconnecting
        // in a tight loop when that firmware does not keep the stream open.
        try await Task.sleep(for: .seconds(1))
    }

    func fallbackPoll(_ device: MinerDevice, token: UUID) async {
        guard !Task.isCancelled, token == liveGeneration, !isDemo else { return }
        // A foreground or post-write refresh supersedes any earlier fallback request without
        // tearing down the socket owner. An old response must not restore pre-write settings.
        let refreshGeneration = generation
        do {
            let info: MinerInfo
            switch device.kind {
            case .espMiner:
                info = try await MinerAPIClient(device: device, session: session).info()
            case .xmrig:
                info = try await XMRigAPIClient(
                    device: device,
                    bearerToken: MinerCredentialStore.token(for: device.keychainCredentialReference),
                    session: session
                ).summary()
            }
            guard !Task.isCancelled, token == liveGeneration, refreshGeneration == generation,
                devices.contains(where: { $0.id == device.id && $0.address == device.address && $0.kind == device.kind })
            else { return }
            recordSuccessfulInfo(info, for: device.id, at: Date())
        } catch {
            guard !Task.isCancelled, token == liveGeneration, refreshGeneration == generation,
                devices.contains(where: { $0.id == device.id && $0.address == device.address && $0.kind == device.kind })
            else { return }
            recordFailedInfo(error.localizedDescription, for: device.id)
        }
    }

    /// XMRig exposes an HTTP summary rather than ESP-Miner's live WebSocket. Poll at a modest
    /// foreground interval and use the same snapshot/error pipeline as every other miner.
    func monitorXMRig(device: MinerDevice, token: UUID) async {
        while !Task.isCancelled, token == liveGeneration {
            await fallbackPoll(device, token: token)
            guard !Task.isCancelled, token == liveGeneration else { return }
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
        }
        if token == liveGeneration { liveTasks[device.id] = nil }
    }

    /// Mac only: coalesce live frames to at most one fleet-wide publish per second.
    static let livePublishInterval: TimeInterval = 1

    #if os(macOS)
    /// Starts one shared flush for every miner's pending frames. Frames arriving before it fires
    /// join the same publish, so the dashboard renders once per interval for the whole fleet.
    func scheduleLiveFlush(token: UUID) {
        guard liveFlushTask == nil else { return }
        liveFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.livePublishInterval))
            guard let self, !Task.isCancelled, token == self.liveGeneration else { return }
            self.liveFlushTask = nil
            self.flushPendingLiveUpdates()
        }
    }

    /// Applies every pending live frame in one main-actor turn, so SwiftUI sees a single change.
    func flushPendingLiveUpdates() {
        for deviceID in Array(pendingLiveUpdates.keys) { flushLiveUpdate(for: deviceID) }
    }

    func flushLiveUpdate(for deviceID: UUID) {
        guard var pending = pendingLiveUpdates.removeValue(forKey: deviceID),
              let update = pending.take() else { return }
        if applyLiveUpdate(update, for: deviceID) { liveAppliedDeviceIDs.insert(deviceID) }
    }
    #endif

    /// Partial live frames merged between publishes, using the same deep merge as snapshots.
    struct PendingLiveUpdate {
        private var value: [String: JSONValue]?
        mutating func merge(_ update: [String: JSONValue]) {
            value = value.map { JSONValue.object($0).merging(update) } ?? update
        }
        mutating func take() -> [String: JSONValue]? {
            defer { value = nil }
            return value
        }
    }

    static func liveUpdate(from message: MinerWebSocketMessage) -> [String: JSONValue]? {
        guard let envelope = try? message.json().objectValue,
            let update = envelope["data"]?.objectValue, !update.isEmpty else { return nil }
        return update
    }

    func applyLiveMessage(_ message: MinerWebSocketMessage, for deviceID: UUID) -> Bool {
        guard let update = Self.liveUpdate(from: message) else { return false }
        return applyLiveUpdate(update, for: deviceID)
    }

    func applyLiveUpdate(_ update: [String: JSONValue], for deviceID: UUID) -> Bool {
        guard snapshots[deviceID]?.error == nil,
            !update.isEmpty,
            var current = snapshots[deviceID]?.info
        else {
            // A socket may deliver a partial frame before the HTTP bootstrap finishes. Keep it out
            // of the dashboard rather than allowing an incomplete live object to replace a reading.
            return false
        }

        guard case .object(let merged) = JSONValue.object(current.raw).merging(.object(update)) else {
            return false
        }
        current.raw = merged
        return recordSuccessfulInfo(
            current,
            for: deviceID,
            at: Date(),
            hasFreshTemperature: update["temp"] != nil,
            hasFreshPower: FleetTotals.powerKeys.contains { update[$0] != nil },
            isCompleteSnapshot: false
        )
    }

    func needsLiveBootstrap(for deviceID: UUID) -> Bool {
        guard let snapshot = snapshots[deviceID] else { return true }
        return snapshot.info == nil || snapshot.error != nil || snapshot.isCached
    }

    func needsFallbackPoll(
        for deviceID: UUID,
        now: Date = Date(),
        maximumAge: TimeInterval = FleetStore.liveSnapshotMaximumAge
    ) -> Bool {
        guard let snapshot = snapshots[deviceID],
              snapshot.info != nil,
              snapshot.error == nil,
              !snapshot.isCached,
              let completeSnapshotAt = snapshot.completeSnapshotAt
        else { return true }
        return now.timeIntervalSince(completeSnapshotAt) >= maximumAge
    }

}

private struct ScoreboardFetchResult: Sendable {
    let deviceID: UUID
    let entries: [MinerScoreboardEntry]
}
