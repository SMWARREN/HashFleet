import Foundation
import HashFleetCore

extension FleetReportSnapshot {
    /// A synchronous main-actor copy makes preview, PDF and CSV agree even as FleetStore refreshes.
    @MainActor
    static func capture(store: FleetStore, at date: Date = .now) -> Self {
        let miners = store.visibleDevices.enumerated().map { index, device in
            let snapshot = store.snapshots[device.id]
            let info = snapshot?.info
            // Identical complete HTTP responses refresh their own observation clock without
            // changing the stable info timestamp. Partial frames can still be newer. Neither
            // clock is allowed to renew power, which retains its own field-observation check.
            let observedAt = [snapshot?.updatedAt, snapshot?.completeSnapshotAt].compactMap { $0 }.max()
            let connection: Connection
            if snapshot?.error != nil {
                connection = .offline
            } else if info != nil && snapshot?.isCached != true {
                connection = .online
            } else {
                connection = .unknown
            }
            let freshness = Freshness.classify(
                observedAt: observedAt,
                capturedAt: date,
                isCached: snapshot?.isCached == true,
                staleAfter: MinerSnapshotFreshness.staleAfterSeconds
            )
            let temperature = FleetMetricTotal.reading(info, keys: ["temp"])
            // A hashrate-only WebSocket update can merge old power into a newly dated snapshot.
            // Its row freshness must never authorize that retained value as current measured power.
            let powerIsFresh = Self.isFreshPowerObservation(
                observedAt: snapshot?.powerObservedAt ?? snapshot?.updatedAt,
                capturedAt: date
            )
            return Miner(
                id: index + 1,
                connection: connection,
                freshness: freshness,
                observedAt: observedAt,
                hashrateGHs: FleetMetricTotal.reading(info, keys: FleetTotals.hashrateKeys),
                powerWatts: powerIsFresh ? FleetMetricTotal.reading(info, keys: FleetTotals.powerKeys) : nil,
                // Firmware uses zero and negative temperature placeholders for uninitialized sensors.
                temperatureCelsius: temperature.flatMap { $0 > 0 ? $0 : nil },
                fanRPM: FleetMetricTotal.reading(info, keys: ["fanrpm"]),
                uptimeSeconds: FleetMetricTotal.reading(info, keys: ["uptimeSeconds"])
            )
        }
        return Self(capturedAt: date, isDemo: store.isDemo, miners: miners)
    }
}
