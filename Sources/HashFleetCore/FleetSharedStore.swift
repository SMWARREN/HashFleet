import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Legacy App Group device and block-baseline storage retained for compatibility with existing
/// shared-core consumers and stored data. The rejected Local Push Connectivity extension has
/// been removed. This API does not install a background poller or guarantee alert delivery.
public enum FleetSharedStore {
    public static let appGroupIdentifier = "group.app.hashfleet.shared"

    private static let devicesKey = "app.hashfleet.shared.devices.v1"
    private static let blockBaselineKey = "app.hashfleet.shared.block-baselines.v1"
    private static let blockObservationStateKey = "app.hashfleet.shared.block-observation-state.v1"

    public static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Devices

    /// Writes a fleet to the legacy shared container. The main app no longer mirrors its fleet
    /// here for background polling.
    public static func writeDevices(_ devices: [MinerDevice]) {
        guard let defaults, let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: devicesKey)
    }

    public static func readDevices() -> [MinerDevice] {
        switch readDevicesState() {
        case .configured(let devices): return devices
        case .unconfigured, .unavailable: return []
        }
    }

    /// Distinguishes a genuinely empty first-run store from a store that exists but cannot be
    /// decoded. Callers must not turn the latter into an implicit LAN discovery request.
    public enum DevicesReadState: Equatable, Sendable {
        case unconfigured
        case configured([MinerDevice])
        case unavailable
    }

    public static func readDevicesState() -> DevicesReadState {
        guard let defaults else { return .unavailable }
        guard let data = defaults.data(forKey: devicesKey) else { return .unconfigured }
        guard let devices = try? JSONDecoder().decode([MinerDevice].self, from: data) else {
            return .unavailable
        }
        return .configured(devices)
    }

    // MARK: - Block baselines

    /// The last block-found evidence the provider observed for a device, keyed by device UUID.
    /// Mirrors `MinerBlockFoundObservation` but is defined in Core so both processes can share it
    /// without importing app-only types.
    public struct BlockBaseline: Codable, Equatable, Sendable {
        public var count: Int?
        public var height: Int?
        public var showNewBlock: Bool
        public var uptimeSeconds: Int?

        public init(count: Int?, height: Int? = nil, showNewBlock: Bool, uptimeSeconds: Int?) {
            self.count = count
            self.height = height
            self.showNewBlock = showNewBlock
            self.uptimeSeconds = uptimeSeconds
        }

        public init(info: MinerInfo) {
            count = info.raw["blockFound"]?.intValue
            height = info.raw["blockHeight"]?.intValue
            showNewBlock = info.raw["showNewBlock"]?.boolValue == true
            uptimeSeconds = info.raw["uptimeSeconds"]?.intValue
        }
    }

    /// Shared identity assigned while both the app and provider observe the same miner.
    /// Height is preferred when firmware supplies it. The boot ID and event ID cover older
    /// firmware whose counter can reset or whose only event signal is a flag edge.
    public struct BlockObservation: Equatable, Sendable {
        public let bootID: String
        public let eventID: String?

        public init(bootID: String, eventID: String?) {
            self.bootID = bootID
            self.eventID = eventID
        }
    }

    private struct BlockObservationState: Codable {
        var count: Int?
        var height: Int?
        var showNewBlock: Bool
        var uptimeSeconds: Int?
        var bootID: String
        var flagEventSequence: UInt64
        var lastFlagEventID: String?
    }

    public static func readBlockBaselines() -> [String: BlockBaseline] {
        guard let defaults, let data = defaults.data(forKey: blockBaselineKey),
            let value = try? JSONDecoder().decode([String: BlockBaseline].self, from: data)
        else { return [:] }
        return value
    }

    public static func writeBlockBaselines(_ baselines: [String: BlockBaseline]) {
        guard let defaults, let data = try? JSONEncoder().encode(baselines) else { return }
        defaults.set(data, forKey: blockBaselineKey)
    }

    /// Records one observation in the shared channel and returns the stable identity that should
    /// be used when the observation represents a block. Both processes call this before their
    /// local detector result is claimed, so the first observer assigns an identity and the second
    /// observer reuses it instead of creating a duplicate or colliding with a prior boot.
    public static func observeBlock(
        deviceID: UUID,
        info: MinerInfo,
        defaults: UserDefaults? = defaults
    ) -> BlockObservation? {
        guard let defaults else { return nil }
        return withAnnouncementLock {
            var states = readBlockObservationStates(defaults)
            let key = deviceID.uuidString
            let prior = states[key]
            let count = info.raw["blockFound"]?.intValue
            let height = info.raw["blockHeight"]?.intValue
            let showNewBlock = info.raw["showNewBlock"]?.boolValue == true
            let uptimeSeconds = info.raw["uptimeSeconds"]?.intValue
            let rebooted: Bool
            if let oldUptime = prior?.uptimeSeconds, let newUptime = uptimeSeconds {
                rebooted = newUptime < oldUptime
            } else {
                rebooted = false
            }
            let bootID = rebooted || prior == nil ? UUID().uuidString : prior!.bootID
            var flagEventSequence = prior?.flagEventSequence ?? 0
            var lastFlagEventID = prior?.lastFlagEventID
            let countIncreased: Bool
            if let oldCount = prior?.count, let newCount = count {
                countIncreased = newCount > oldCount && !rebooted
            } else {
                countIncreased = false
            }
            let isEvent = (showNewBlock && !(prior?.showNewBlock ?? false)) || countIncreased
            if isEvent {
                flagEventSequence += 1
                lastFlagEventID = "\(bootID):event:\(flagEventSequence)"
            }
            states[key] = BlockObservationState(
                count: count,
                height: height,
                showNewBlock: showNewBlock,
                uptimeSeconds: uptimeSeconds,
                bootID: bootID,
                flagEventSequence: flagEventSequence,
                lastFlagEventID: lastFlagEventID
            )
            writeBlockObservationStates(states, defaults: defaults)
            return BlockObservation(
                bootID: bootID,
                // The second process observes the same event after the first process has
                // persisted it. Reuse the last identity for that replay, but never carry an
                // event identity across a detected reboot.
                eventID: rebooted ? nil : lastFlagEventID
            )
        }
    }

    private static func readBlockObservationStates(_ defaults: UserDefaults) -> [String: BlockObservationState] {
        guard let data = defaults.data(forKey: blockObservationStateKey),
            let value = try? JSONDecoder().decode([String: BlockObservationState].self, from: data)
        else { return [:] }
        return value
    }

    private static func writeBlockObservationStates(
        _ states: [String: BlockObservationState], defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(states) else { return }
        defaults.set(data, forKey: blockObservationStateKey)
    }

    // MARK: - One channel per block

    private static let appActiveUntilKey = "app.hashfleet.shared.app-active-until.v1"
    private static let announcedBlocksKey = "app.hashfleet.shared.announced-blocks.v1"
    /// How long an "app is open" heartbeat stays valid. The app refreshes it while active, so a
    /// crash or suspension lets the extension resume pushing within this window.
    public static let appActiveHeartbeat: TimeInterval = 90

    /// Records that the app is open, so the background provider leaves presentation to the app.
    public static func markAppActive(_ active: Bool, now: Date = .now, defaults: UserDefaults? = defaults) {
        defaults?.set(active ? now.addingTimeInterval(appActiveHeartbeat).timeIntervalSince1970 : 0,
                      forKey: appActiveUntilKey)
    }

    public static func isAppActive(now: Date = .now, defaults: UserDefaults? = defaults) -> Bool {
        guard let until = defaults?.double(forKey: appActiveUntilKey), until > 0 else { return false }
        return now.timeIntervalSince1970 < until
    }

    /// A block key both processes agree on. Height is the strongest identity and deliberately
    /// excludes the other fields so two pollers that observe the same height with slightly
    /// different counters still share one key. Older firmware can omit height, so the counter is
    /// paired with a coarse uptime boot epoch. Flag-only responses use the same epoch fallback.
    /// Uptime is intentionally quantized because two pollers never observe a response at exactly
    /// the same second. A response without height, count, or uptime cannot be made unique and is
    /// marked explicitly rather than pretending otherwise.
    public static func blockKey(
        deviceID: UUID,
        count: Int?,
        height: Int? = nil,
        uptimeSeconds: Int? = nil,
        bootID: String? = nil,
        eventID: String? = nil
    ) -> String {
        var parts = [deviceID.uuidString]
        if let height {
            parts.append("height=\(height)")
        } else if let eventID {
            parts.append("event=\(eventID)")
        } else if let count {
            parts.append("count=\(count)")
            if let bootID {
                parts.append("boot=\(bootID)")
            } else if let uptimeSeconds {
                parts.append("boot=\(uptimeSeconds / 60)")
            }
        } else if let bootID {
            parts.append("boot=\(bootID)")
        } else if let uptimeSeconds {
            parts.append("boot=\(uptimeSeconds / 60)")
        } else {
            parts.append("event=unknown")
        }
        return parts.joined(separator: "|")
    }

    /// Claims the right to announce a block. Returns false when the app or the provider already
    /// announced it, so each block reaches the user on exactly one channel.
    @discardableResult
    public static func claimBlockAnnouncement(_ key: String, defaults: UserDefaults? = defaults) -> Bool {
        guard let defaults else { return true }
        return withAnnouncementLock {
            var announced = defaults.stringArray(forKey: announcedBlocksKey) ?? []
            guard !announced.contains(key) else { return false }
            announced.append(key)
            defaults.set(Array(announced.suffix(200)), forKey: announcedBlocksKey)
            return true
        }
    }

    private static let announcementProcessLock = NSLock()

    /// UserDefaults writes are not a cross-process compare-and-swap. The app and its push
    /// extension share an App Group, so serialize the small read/check/write transaction with an
    /// advisory file lock. Unit-test suites and unsupported hosts fall back to a process lock.
    private static func withAnnouncementLock<T>(_ body: () -> T) -> T {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            announcementProcessLock.lock()
            defer { announcementProcessLock.unlock() }
            return body()
        }

        let lockURL = directory.appendingPathComponent("announced-blocks.lock")
        if !FileManager.default.fileExists(atPath: lockURL.path) {
            _ = FileManager.default.createFile(atPath: lockURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: lockURL)
        else {
            announcementProcessLock.lock()
            defer { announcementProcessLock.unlock() }
            return body()
        }
        defer { try? handle.close() }

        #if canImport(Darwin) || canImport(Glibc)
        _ = flock(handle.fileDescriptor, LOCK_EX)
        defer { _ = flock(handle.fileDescriptor, LOCK_UN) }
        #endif
        return body()
    }
}
