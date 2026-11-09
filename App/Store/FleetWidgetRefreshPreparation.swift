import Foundation
import HashFleetCore

/// Foreground-only preparation. A snapshot from before an address change cannot pin its replacement.
/// This intentionally supports only complete, credential-free ASIC fleets on literal private IPv4.
struct FleetWidgetRefreshPreparation {
    private struct Binding: Equatable {
        let address: String
        let kind: MinerDevice.Kind
        let credential: String?
    }
    private var bindings: [UUID: Binding] = [:]
    private var observedAfter: [UUID: Date] = [:]
    private var wasDemo: Bool?

    mutating func targets(
        devices: [MinerDevice], snapshots: [UUID: MinerSnapshot], isDemo: Bool, now: Date
    ) -> [FleetWidgetRefreshTarget]? {
        // A real -> Demo -> real round trip must not reuse the earlier real snapshot.
        let changedMode = wasDemo != nil && wasDemo != isDemo
        wasDemo = isDemo
        var next: [UUID: Binding] = [:]
        for device in devices {
            guard next[device.id] == nil else { return nil }
            let binding = Binding(address: device.address, kind: device.kind,
                credential: device.keychainCredentialReference)
            next[device.id] = binding
            if changedMode || bindings[device.id] != binding { observedAfter[device.id] = now }
        }
        bindings = next
        observedAfter = observedAfter.filter { next[$0.key] != nil }
        guard !isDemo, (1...16).contains(devices.count) else { return nil }
        var targets: [FleetWidgetRefreshTarget] = []
        for device in devices {
            guard device.kind == .espMiner, device.keychainCredentialReference == nil,
                  let url = try? device.validatedURL(),
                  let snapshot = snapshots[device.id], !snapshot.isCached, !snapshot.isReconnecting,
                  snapshot.error == nil, let date = snapshot.completeSnapshotAt,
                  date >= (observedAfter[device.id] ?? now),
                  (-5..<FleetGlance.freshnessInterval).contains(now.timeIntervalSince(date)),
                  let info = snapshot.info else { return nil }
            guard let mac = Self.observedMAC(in: info) else { return nil }
            let target = FleetWidgetRefreshTarget(id: device.id, baseURL: url, expectedMAC: mac)
            guard target.isValid else { return nil }
            targets.append(target)
        }
        return targets.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Missing in-memory readings are not a user revocation. Match only already prepared pins;
    /// never create, renew or expand them here. An expired payload may retain its last reading,
    /// but the refresh runner still rejects its expired permission before making any request.
    static func matchesPreparedFleet(
        _ configuration: FleetWidgetRefreshConfiguration, devices: [MinerDevice],
        snapshots: [UUID: MinerSnapshot], now: Date
    ) -> Bool {
        guard configuration.isValid, now.timeIntervalSince1970.isFinite,
              devices.count == configuration.targets.count,
              Set(devices.map(\.id)).count == devices.count else { return false }
        let targets = Dictionary(uniqueKeysWithValues: configuration.targets.map { ($0.id, $0) })
        for device in devices {
            guard device.kind == .espMiner, device.keychainCredentialReference == nil,
                  let target = targets[device.id], let url = try? device.validatedURL(),
                  url == target.baseURL else { return false }
            // Only a complete current observation can contradict the prepared identity. Cached,
            // partial and reconnecting frames cannot replace or validate a hardware identity.
            if let snapshot = snapshots[device.id], !snapshot.isCached, !snapshot.isReconnecting,
               snapshot.error == nil, let observed = snapshot.completeSnapshotAt,
               observed >= configuration.createdAt,
               (-5..<FleetGlance.freshnessInterval).contains(now.timeIntervalSince(observed)) {
                guard let info = snapshot.info, let mac = Self.observedMAC(in: info),
                      mac == FleetScheduledCheckTarget.normalizedMAC(target.expectedMAC) else { return false }
            }
        }
        return true
    }

    private static func observedMAC(in info: MinerInfo) -> String? {
        var macs: [String] = []
        for key in ["macAddr", "macAddress", "mac"] where info.raw[key] != nil {
            guard case .string(let raw)? = info.raw[key],
                  let mac = FleetScheduledCheckTarget.normalizedMAC(raw) else { return nil }
            macs.append(mac)
        }
        guard let mac = macs.first, macs.allSatisfy({ $0 == mac }) else { return nil }
        return mac
    }
}
