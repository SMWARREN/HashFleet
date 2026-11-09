import Foundation

/// Reboot-guarded block-found detection retained for app and shared-core consumers.
///
/// The firmware `blockFound` counter resets to 0 on every reboot and then re-climbs, so a
/// power-cycle or reflash makes the counter rise without a real solve. Detection fires only on the
/// explicit firmware `showNewBlock` flag, or on a counter increase that did not coincide with a
/// reboot (an uptime decrease). This mirrors the app's `MinerBlockFoundEvent.detect` policy.
public enum FleetBlockDetection {
    public struct Result: Sendable, Equatable {
        public let coinLabel: String?
        public let height: Int?
        public let count: Int?
        public let uptimeSeconds: Int?

        public init(coinLabel: String?, height: Int?, count: Int?, uptimeSeconds: Int? = nil) {
            self.coinLabel = coinLabel
            self.height = height
            self.count = count
            self.uptimeSeconds = uptimeSeconds
        }
    }

    /// Returns a block result when `current` represents a newly found block relative to `previous`.
    /// The first observation for a device (`previous == nil`) is always a silent baseline.
    public static func detect(
        previous: FleetSharedStore.BlockBaseline?,
        current: MinerInfo
    ) -> Result? {
        guard let previous else { return nil }

        let currentCount = current.raw["blockFound"]?.intValue
        let currentShowNewBlock = current.raw["showNewBlock"]?.boolValue == true
        let currentUptime = current.raw["uptimeSeconds"]?.intValue

        let rebooted: Bool
        if let oldUp = previous.uptimeSeconds, let newUp = currentUptime {
            rebooted = newUp < oldUp
        } else {
            rebooted = false
        }

        let counterIncreased: Bool
        if let old = previous.count, let new = currentCount {
            counterIncreased = new > old
        } else {
            counterIncreased = false
        }
        let flagRaised = currentShowNewBlock && !previous.showNewBlock

        guard flagRaised || (counterIncreased && !rebooted) else { return nil }

        let pools = ConfiguredMiningPool.resolve(info: current)
        let selected =
            pools.first(where: { $0.isActive == true })
            ?? pools.first(where: { $0.role.localizedCaseInsensitiveContains("primary") })
            ?? pools.first

        return Result(
            coinLabel: selected?.coin?.rawValue.uppercased(),
            height: current.raw["blockHeight"]?.intValue,
            count: currentCount,
            uptimeSeconds: currentUptime
        )
    }
}
