import Foundation

/// Read-only fleet polling shared by the apps, companion, widgets, and terminal client.
public enum FleetStatusService {
    public static func read(
        devices: [MinerDevice],
        xmrigBearerToken: String? = nil
    ) async -> FleetStatusSnapshot {
        let miners = await withTaskGroup(of: MinerStatusSnapshot.self, returning: [MinerStatusSnapshot].self) { group in
            for device in devices {
                group.addTask {
                    await read(device: device, xmrigBearerToken: xmrigBearerToken)
                }
            }

            var snapshots: [MinerStatusSnapshot] = []
            for await snapshot in group {
                snapshots.append(snapshot)
            }
            return snapshots.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }

        return FleetStatusSnapshot(miners: miners)
    }

    private static func read(device: MinerDevice, xmrigBearerToken: String?) async -> MinerStatusSnapshot {
        do {
            let info: MinerInfo
            switch device.kind {
            case .espMiner:
                info = try await MinerAPIClient(device: device).info()
            case .xmrig:
                info = try await XMRigAPIClient(device: device, bearerToken: xmrigBearerToken).summary()
            }
            return MinerStatusSnapshot(device: device, info: info)
        } catch {
            return MinerStatusSnapshot(device: device, error: error.localizedDescription)
        }
    }
}
