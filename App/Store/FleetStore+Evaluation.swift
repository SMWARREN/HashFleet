import Foundation
import Observation
import HashFleetCore

#if canImport(GRDB)
import GRDB
#endif

private struct StateMetricChangeContext {
    let deviceID: UUID
    let date: Date
    let recoveringFromError: Bool
    let previous: MinerInfo?
}

/// Alert and event evaluation for FleetStore.
extension FleetStore {
    @discardableResult
    func recordSuccessfulInfo(
        _ info: MinerInfo, for deviceID: UUID, at date: Date, hasFreshTemperature: Bool = true,
        hasFreshPower: Bool = true, isCompleteSnapshot: Bool = true
    ) -> Bool {
        var snapshot = snapshots[deviceID] ?? MinerSnapshot()
        // A background refresh can persist an outage without changing this store's retained
        // reading. Even identical fresh telemetry must reconcile that offline baseline once.
        let hasPersistedOutage = !isDemo && stateObservations[deviceID.uuidString]?.isOnline == false
        let isRecovering = snapshot.error != nil || snapshot.isCached || snapshot.isReconnecting
            || hasPersistedOutage
        guard isRecovering || snapshot.info != info else {
            // An identical HTTP response still proves that the complete snapshot is fresh. Keep
            // the published info stable, but retain the timestamped hashrate sample so a steady
            // miner still accumulates real coverage for the adaptive history ranges. Live
            // WebSocket frames skip this write entirely because they are not complete snapshots.
            guard isCompleteSnapshot else { return false }
            snapshot.completeSnapshotAt = date
            if hasFreshPower { snapshot.powerObservedAt = date }
            appendHistorySample(info, to: &snapshot, at: date)
            snapshots[deviceID] = snapshot
            if !isDemo, preferences.telemetryStorageEnabled {
                recordTelemetryToDatabase(info: info, deviceID: deviceID, date: date)
            }
            return false
        }
        snapshot.powerObservedAt = hasFreshPower ? date : (snapshot.powerObservedAt ?? snapshot.updatedAt)
        let wasErroring = snapshot.error != nil
        let previous = snapshot.isCached ? nil : snapshot.info
        if let previous { snapshot.previousInfo = previous }
        snapshot.info = info
        snapshot.updatedAt = date
        if isCompleteSnapshot { snapshot.completeSnapshotAt = date }
        snapshot.error = nil
        snapshot.isCached = false
        snapshot.isReconnecting = false
        appendHistorySample(info, to: &snapshot, at: date)
        snapshots[deviceID] = snapshot
        lastRefresh = date
        updateAutomaticName(for: deviceID, info: info)
        cacheSuccessfulInfo(info, for: deviceID, at: date)

        // Record telemetry to database if enabled
        if !isDemo, preferences.telemetryStorageEnabled {
            recordTelemetryToDatabase(info: info, deviceID: deviceID, date: date)
        }

        guard let device = devices.first(where: { $0.id == deviceID }) else { return false }
        if !isDemo, hasFreshTemperature,
            let event = temperatureAlerts.observe(
                device: device, info: info, observedAt: date,
                isOnline: true, isCached: false, now: date
            ) {
            pendingTemperatureEvents.append(event)
            enqueueNotification(.temperature(event))
        }
        // High-power alarms use the same alarm/threshold discipline as temperature: only a
        // freshly observed `power` field counts, so partial WebSocket frames that retain an old
        // reading never fabricate an alarm.
        if !isDemo, hasFreshPower,
            let event = powerAlerts.observe(
                device: device, info: info, observedAt: date,
                isOnline: true, isCached: false, now: date
            ) {
            pendingPowerAlertEvents.append(event)
            enqueueNotification(.power(event))
        }

        detectBestShare(device: device, info: info, previous: previous, deviceID: deviceID, date: date)
        detectBlockFound(device: device, info: info, previous: previous, deviceID: deviceID, date: date)
        detectStateAndMetricChanges(
            device: device,
            info: info,
            context: StateMetricChangeContext(
                deviceID: deviceID,
                date: date,
                recoveringFromError: wasErroring,
                previous: previous
            )
        )
        return true
    }

    /// Detects connectivity recovery and significant metric movement against the miner's own
    /// previous reading. While recovering from a failed or cached snapshot the persisted
    /// baseline is the honest prior state; the retained in-memory reading predates the outage
    /// and would wrongly look "still online".
    private func detectStateAndMetricChanges(
        device: MinerDevice,
        info: MinerInfo,
        context: StateMetricChangeContext
    ) {
        guard !isDemo else { return }
        let key = context.deviceID.uuidString
        let persisted = stateObservations[key]
        // A background refresh may have recorded this miner offline while the foreground
        // snapshot still held its pre-outage reading. The persisted "offline" state wins, so the
        // recovery is announced (and replaces the offline alert) instead of being missed.
        let baseline = context.recoveringFromError || persisted?.isOnline == false
            ? persisted
            : context.previous.map { MinerFleetStateObservation(info: $0, isOnline: true, observedAt: context.date) }
                ?? persisted
        if let baseline {
            if !baseline.isOnline {
                let event = MinerStateChangeEvent(
                    deviceID: context.deviceID, minerName: device.name, kind: .backOnline, occurredAt: context.date)
                pendingStateChangeEvents.append(event)
                enqueueNotification(.stateChange(event))
            } else if let alert = MinerMetricAlertEvent.detect(
                device: device, previous: baseline, current: info, occurredAt: context.date) {
                pendingMetricAlertEvents.append(alert)
                enqueueNotification(.metricAlert(alert))
            }
        }
        stateObservations[key] = MinerFleetStateObservation(info: info, isOnline: true, observedAt: context.date)
        persistStateObservations()
    }

    /// Fall back to the persisted baseline when there is no in-memory previous reading, so a
    /// background refresh or a fresh launch can still detect a new record.
    private func detectBestShare(
        device: MinerDevice, info: MinerInfo, previous: MinerInfo?, deviceID: UUID, date: Date
    ) {
        let currentBestShare = MinerBestShareObservation(info: info)
        let persistedBaseline = bestShareObservations[deviceID.uuidString]
        let bestShareBaseline = previous.map(MinerBestShareObservation.init) ?? persistedBaseline
        // Monotonic all-time high-water mark. The persisted baseline's all-time field is kept as the
        // running maximum below, so it survives a miner reset/flash that drops the firmware's
        // reported bestDiff back toward 0. Guards against re-celebrating an already-seen record.
        let allTimeFloor = persistedBaseline.flatMap { MiningDifficultyFormat.parse($0.bestDiff) }
        if let event = MinerBestShareEvent.detect(
            device: device,
            previous: bestShareBaseline,
            current: currentBestShare,
            occurredAt: date,
            allTimeFloor: allTimeFloor
        ) {
            latestBestShareEvent = event
            pendingBestShareEvents.append(event)
            enqueueNotification(.bestShare(event))

            // Only write our own achievement row when this device hasn't confirmed scoreboard
            // support. reconcileScoreboard() (see runMonitoring) imports the same all-time record
            // from the miner's own firmware scoreboard, which is more precise (exact decimal
            // difficulty, real ntime, coin) and authoritative. Writing here too made every
            // all-time record appear twice: once as a rounded integer with no metadata from this
            // polling path, once as the precise scoreboard entry — the same real share, two rows.
            if event.kind == .allTime, !scoreboardSupportedDeviceIDs.contains(deviceID),
                !isDemo, preferences.telemetryStorageEnabled {
                let difficulty = MiningDifficultyFormat.parse(event.rawValue)
                    .map { NSDecimalNumber(decimal: $0).doubleValue }
                Task { @MainActor in
                    guard let difficulty, let achievementID = achievementDeviceID(for: deviceID) else { return }
                    await MinerTelemetryDatabase.shared.recordPollingBestShareAchievement(
                        minerId: achievementID.uuidString, timestamp: date, difficulty: difficulty)
                }
            }
        }
        // Persist the last session reading as-is (session legitimately resets), but keep the
        // all-time field monotonic so a later reset cannot lower the baseline.
        let storedAllTimeRaw: String
        if let floor = allTimeFloor,
            let current = MiningDifficultyFormat.parse(currentBestShare.bestDiff),
            floor >= current {
            storedAllTimeRaw = persistedBaseline?.bestDiff ?? currentBestShare.bestDiff
        } else {
            storedAllTimeRaw = currentBestShare.bestDiff
        }
        bestShareObservations[deviceID.uuidString] = MinerBestShareObservation(
            bestDiff: storedAllTimeRaw,
            bestSessionDiff: currentBestShare.bestSessionDiff
        )
        persistBestShareObservations()
    }

    private func detectBlockFound(
        device: MinerDevice, info: MinerInfo, previous: MinerInfo?, deviceID: UUID, date: Date
    ) {
        let currentBlockObservation = MinerBlockFoundObservation(info: info)
        let sharedObservation = isDemo
            ? nil
            : FleetSharedStore.observeBlock(deviceID: deviceID, info: info)
        let persistedPrevious = blockObservations[deviceID.uuidString]
        let blockEvent: MinerBlockFoundEvent?
        if let previous {
            blockEvent = MinerBlockFoundEvent.detect(
                device: device,
                previous: previous,
                current: info,
                occurredAt: date
            )
        } else {
            blockEvent = MinerBlockFoundEvent.detect(
                device: device,
                previous: persistedPrevious,
                current: currentBlockObservation,
                currentInfo: info,
                occurredAt: date
            )
        }
        blockObservations[deviceID.uuidString] = currentBlockObservation
        persistBlockObservations()
        // The push extension may have announced this block already (same miner and counter).
        // Claiming it here keeps the block on exactly one channel across both processes.
        if let blockEvent, isDemo || FleetSharedStore.claimBlockAnnouncement(
            FleetSharedStore.blockKey(
                deviceID: deviceID, count: blockEvent.count, height: blockEvent.height,
                uptimeSeconds: currentBlockObservation.uptimeSeconds,
                bootID: sharedObservation?.bootID,
                eventID: sharedObservation?.eventID)) {
            latestBlockFoundEvent = blockEvent
            pendingBlockFoundEvents.append(blockEvent)
            enqueueNotification(.blockFound(blockEvent))

            // Record block found achievement to database
            if !isDemo, preferences.telemetryStorageEnabled {
                Task { @MainActor in
                    guard let achievementID = achievementDeviceID(for: deviceID) else { return }
                    await MinerTelemetryDatabase.shared.recordAchievement(
                        minerId: achievementID.uuidString,
                        eventType: "block_found",
                        timestamp: date,
                        blockHeight: currentBlockObservation.height ?? currentBlockObservation.count,
                        metadata: currentBlockObservation.height.map { height in
                            ["height": height]
                        }
                    )
                }
            }
        }
    }

    @discardableResult
    func recordFailedInfo(_ error: String, for deviceID: UUID) -> Bool {
        var snapshot = snapshots[deviceID] ?? MinerSnapshot()
        guard snapshot.error != error || snapshot.isReconnecting else { return false }
        if snapshot.error == nil, let info = snapshot.info, let observed = snapshot.updatedAt {
            cacheSuccessfulInfo(info, for: deviceID, at: observed, force: true)
        }
        // Fire a single offline transition per outage. The persisted baseline is authoritative:
        // it is shared with background refreshes, so an outage already announced from the
        // background is not announced again by the foreground store's stale in-memory snapshot.
        // Only a miner with no recorded baseline falls back to its live (non-cached) snapshot.
        let wasOnline = !isDemo
            && (stateObservations[deviceID.uuidString]?.isOnline
                ?? (snapshot.error == nil && snapshot.info != nil && !snapshot.isCached))
        snapshot.error = error
        snapshot.isReconnecting = false
        snapshots[deviceID] = snapshot

        if !isDemo {
            let prior = stateObservations[deviceID.uuidString]
            if wasOnline, let device = devices.first(where: { $0.id == deviceID }) {
                let disconnectedAt = Date()
                let event = MinerStateChangeEvent(
                    deviceID: deviceID, minerName: device.name, kind: .offline,
                    detail: error, occurredAt: disconnectedAt)
                pendingStateChangeEvents.append(event)
                enqueueNotification(.stateChange(event))
                // Persist the disconnect itself (distinct from generic poll errors) so the
                // telemetry database always has a timestamped offline event per outage.
                if preferences.telemetryStorageEnabled {
                    Task { @MainActor in
                        await MinerTelemetryDatabase.shared.recordConnectivityEvent(
                            minerId: deviceID.uuidString,
                            eventType: "disconnect",
                            timestamp: disconnectedAt,
                            errorMessage: error
                        )
                    }
                }
            }
            stateObservations[deviceID.uuidString] = MinerFleetStateObservation(
                isOnline: false, hashrate: prior?.hashrate,
                power: prior?.power, observedAt: Date())
            persistStateObservations()
        }

        // Record connectivity event to database
        if !isDemo, preferences.telemetryStorageEnabled {
            Task { @MainActor in
                await MinerTelemetryDatabase.shared.recordConnectivityEvent(
                    minerId: deviceID.uuidString,
                    eventType: "error",
                    errorMessage: error
                )
            }
        }
        return true
    }

    private func appendHistorySample(_ info: MinerInfo, to snapshot: inout MinerSnapshot, at date: Date) {
        guard let rate = FleetMetricTotal.reading(info, keys: FleetTotals.hashrateKeys) else {
            return
        }
        snapshot.history.append(HashratePoint(date: date, value: rate))
        snapshot.history = Array(snapshot.history.suffix(360))
    }

    private func recordTelemetryToDatabase(info: MinerInfo, deviceID: UUID, date: Date) {
        MinerTelemetryDatabase.shared.recordReading(
            minerId: deviceID.uuidString,
            timestamp: date,
            reading: Self.telemetryReading(info: info)
        )
    }

    /// The app recorder consumes the same canonical ESP-Miner keys as the status views and
    /// translated XMRig summary. Missing, invalid and negative sentinel readings stay SQL NULL.
    static func telemetryReading(info: MinerInfo) -> MinerReadingInput {
        func integer(_ keys: String...) -> Int? {
            for key in keys {
                guard let raw = info.raw[key] else { continue }
                if case .bool = raw { return nil }
                if let value = raw.doubleValue, value.rounded(.towardZero) != value { return nil }
                guard let value = raw.intValue, value >= 0 else { return nil }
                return value
            }
            return nil
        }
        let fan = integer("fanspeed", "fanSpeed")
        let fallback: Bool?
        switch info.raw["isUsingFallbackStratum"] {
        case .bool(let value): fallback = value
        case .integer(0), .number(0): fallback = false
        case .integer(1), .number(1): fallback = true
        default: fallback = nil
        }
        return MinerReadingInput(
            hashrate: FleetMetricTotal.reading(info, keys: FleetTotals.hashrateKeys),
            power: FleetMetricTotal.reading(info, keys: ["power"]),
            temp: FleetMetricTotal.reading(info, keys: ["temp"]),
            vrTemp: FleetMetricTotal.reading(info, keys: ["vrTemp"]),
            fanSpeed: fan.flatMap { $0 <= 100 ? $0 : nil },
            fanRPM: integer("fanrpm", "fanRpm"),
            voltage: integer("voltage"),
            frequency: integer("frequency"),
            coreVoltage: integer("coreVoltage"),
            sharesAccepted: integer("sharesAccepted"),
            sharesRejected: integer("sharesRejected"),
            uptimeSeconds: integer("uptimeSeconds"),
            activePoolIndex: integer("activePoolIndex"),
            // Never infer fallback merely because an arbitrary pool slot is numbered 1.
            isFallbackPool: fallback
        )
    }
}
