#if os(iOS)
import HashFleetCore
import HashFleetWatchCore

/// Whitelist the configuration fields allowed onto the Watch. Never forward MinerDevice itself,
/// its Keychain reference, an authenticated host, a simulator fleet, or any telemetry/raw response.
struct FleetWatchSetupSelection {
    let miners: [WatchMiner]
    let skippedCount: Int

    init(devices: [MinerDevice], isDemo: Bool) {
        guard !isDemo else {
            miners = []
            skippedCount = devices.count
            return
        }
        var selected: [WatchMiner] = []
        var endpoints: Set<String> = []
        for device in devices {
            guard device.kind == .espMiner, device.keychainCredentialReference == nil,
                  let miner = try? WatchMiner(id: device.id, name: device.name, address: device.address),
                  endpoints.insert(miner.address).inserted else { continue }
            selected.append(miner)
        }
        miners = selected
        skippedCount = devices.count - selected.count
    }
}
#endif
