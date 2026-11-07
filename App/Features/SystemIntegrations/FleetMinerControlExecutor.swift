import Foundation
import HashFleetCore

public enum FleetMinerControlAction: Equatable, Sendable {
    case restart
    case setFrequency(Double)
    case setFanSpeed(Int)

    public var actionName: String {
        switch self {
        case .restart: "Restart"
        case .setFrequency: "Set Frequency"
        case .setFanSpeed: "Set Fan Speed"
        }
    }

    public var valueDescription: String {
        switch self {
        case .restart: "Immediate reboot"
        case .setFrequency(let mhz): "\(mhz) MHz"
        case .setFanSpeed(let percent): "\(percent)% (Manual mode)"
        }
    }

    public var riskDescription: String {
        switch self {
        case .restart:
            "Rebooting will temporarily halt mining and interrupt pool stratum connections."
        case .setFrequency:
            "Changing frequency changes clock rate and thermal output. "
                + "Safe operation depends on your board revision and cooling. "
                + "1 to 65535 MHz is a firmware encoding limit, not an established hardware-safe operating range. "
                + "Overclocking can cause instability, hardware overheating, or premature failure."
        case .setFanSpeed:
            "Setting manual fan speed disables automatic cooling control (autofanspeed = 0). "
                + "If set too low or left unmonitored, the miner can overheat and sustain hardware damage."
        }
    }
}

public struct FleetMinerPreflightInfo: Sendable {
    public let device: MinerDevice
    public let info: MinerInfo
    public let observedAt: Date
    public let confirmationPrompt: String
    public let confirmationDialog: String

    public init(
        device: MinerDevice,
        info: MinerInfo,
        observedAt: Date,
        confirmationPrompt: String,
        confirmationDialog: String
    ) {
        self.device = device
        self.info = info
        self.observedAt = observedAt
        self.confirmationPrompt = confirmationPrompt
        self.confirmationDialog = confirmationDialog
    }
}

public struct FleetMinerControlResult: Sendable {
    public let success: Bool
    public let message: String
    public let deviceName: String
    public let actionName: String

    public init(success: Bool, message: String, deviceName: String, actionName: String) {
        self.success = success
        self.message = message
        self.deviceName = deviceName
        self.actionName = actionName
    }
}

public enum FleetMinerControlError: LocalizedError, Equatable {
    case deviceNotFound(String)
    case invalidAddress(String)
    case demoModeReadOnly
    case invalidParameter(String)
    case preflightFailed(String)
    case staleDevice(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound(let id):
            "Saved miner with ID '\(id)' was not found in your fleet."
        case .invalidAddress(let address):
            "Miner address '\(address)' is invalid."
        case .demoModeReadOnly:
            "Hash Fleet is in demo mode or hardware control is blocked. Mutations are disabled."
        case .invalidParameter(let message):
            message
        case .preflightFailed(let message):
            "Could not verify miner status before confirmation: \(message)"
        case .staleDevice(let message):
            "Safety check failed: \(message)"
        case .writeFailed(let message):
            "Miner mutation failed: \(message)"
        }
    }
}

public final class FleetMinerControlExecutor: Sendable {
    public static let shared = FleetMinerControlExecutor()

    public static func sharedSavedDevicesLoader() -> [MinerDevice] {
        guard let data = UserDefaults.standard.data(forKey: "app.hashfleet.devices.v1"),
            let devices = try? JSONDecoder().decode([MinerDevice].self, from: data)
        else {
            return []
        }
        return devices
    }

    public static func sharedDemoChecker() -> Bool {
        FleetHardwareControlGate.shared.isBlocked
    }

    public let savedDevicesLoader: @Sendable () -> [MinerDevice]
    public let demoChecker: @Sendable () -> Bool
    public let infoFetcher: @Sendable (MinerDevice) async throws -> MinerInfo
    public let writeExecutor: @Sendable (MinerDevice, MinerEndpoint, Data?) async throws -> Data
    public let dateProvider: @Sendable () -> Date

    public init(
        savedDevicesLoader: (@Sendable () -> [MinerDevice])? = nil,
        demoChecker: (@Sendable () -> Bool)? = nil,
        infoFetcher: (@Sendable (MinerDevice) async throws -> MinerInfo)? = nil,
        writeExecutor: (@Sendable (MinerDevice, MinerEndpoint, Data?) async throws -> Data)? = nil,
        dateProvider: (@Sendable () -> Date)? = nil
    ) {
        self.savedDevicesLoader = savedDevicesLoader ?? { Self.sharedSavedDevicesLoader() }
        self.demoChecker = demoChecker ?? { Self.sharedDemoChecker() }
        self.infoFetcher =
            infoFetcher ?? { device in
                let client = MinerAPIClient(device: device)
                return try await client.info()
            }
        self.writeExecutor =
            writeExecutor ?? { device, endpoint, body in
                let client = MinerAPIClient(device: device)
                return try await client.execute(endpoint, body: body)
            }
        self.dateProvider = dateProvider ?? { Date() }
    }

    public func resolveDevice(id: String) throws -> MinerDevice {
        if demoChecker() {
            throw FleetMinerControlError.demoModeReadOnly
        }
        let devices = savedDevicesLoader()
        guard let device = devices.first(where: { $0.id.uuidString == id }) else {
            throw FleetMinerControlError.deviceNotFound(id)
        }
        guard (try? device.validatedURL()) != nil else {
            throw FleetMinerControlError.invalidAddress(device.address)
        }
        return device
    }

    public func validateParameters(for action: FleetMinerControlAction) throws {
        switch action {
        case .restart:
            break
        case .setFrequency(let mhz):
            guard mhz.isFinite, !mhz.isNaN, (1...65_535).contains(mhz), Float(mhz).isFinite else {
                throw FleetMinerControlError.invalidParameter(
                    "Frequency requires a finite number between 1 and 65535 MHz. "
                        + "This is a firmware wire limit, not a hardware safety guarantee."
                )
            }
        case .setFanSpeed(let percent):
            guard (0...100).contains(percent) else {
                throw FleetMinerControlError.invalidParameter(
                    "Fan speed requires a whole percentage between 0 and 100%."
                )
            }
        }
    }

    public func preflight(
        device: MinerDevice,
        action: FleetMinerControlAction
    ) async throws -> FleetMinerPreflightInfo {
        try Task.checkCancellation()
        if demoChecker() {
            throw FleetMinerControlError.demoModeReadOnly
        }
        try validateParameters(for: action)

        let info: MinerInfo
        do {
            info = try await infoFetcher(device)
        } catch {
            throw FleetMinerControlError.preflightFailed(error.localizedDescription)
        }

        guard MinerShapeValidator.isValidInfoShape(.object(info.raw)) else {
            throw FleetMinerControlError.preflightFailed("Device returned invalid or unrecognized telemetry shape.")
        }

        let now = dateProvider()
        let prompt = "Confirm \(action.actionName) for \(device.name)?"
        let dialog =
            "You are about to \(action.actionName.lowercased()) on miner '\(device.name)' (\(device.address)) "
                + "with value: \(action.valueDescription).\n\nRisks: \(action.riskDescription)\n\n"
                + "Do you want to proceed?"

        return FleetMinerPreflightInfo(
            device: device,
            info: info,
            observedAt: now,
            confirmationPrompt: prompt,
            confirmationDialog: dialog
        )
    }

    /// App Intents supply the system confirmation callback. Declining or cancelling
    /// throws before the only mutation path can be reached.
    func run(
        deviceID: String,
        action: FleetMinerControlAction,
        confirm: (String) async throws -> Void
    ) async throws -> FleetMinerControlResult {
        let device = try resolveDevice(id: deviceID)
        let observation = try await preflight(device: device, action: action)
        try Task.checkCancellation()
        try await confirm(observation.confirmationDialog)
        try Task.checkCancellation()
        return try await executeConfirmed(
            device: device,
            action: action,
            preflightObservedAt: observation.observedAt
        )
    }

    func executeConfirmed(
        device: MinerDevice,
        action: FleetMinerControlAction,
        preflightObservedAt: Date
    ) async throws -> FleetMinerControlResult {
        try Task.checkCancellation()

        // 1. Check demo mode / gate again
        if demoChecker() {
            throw FleetMinerControlError.demoModeReadOnly
        }

        // 2. Revalidate parameters
        try validateParameters(for: action)

        // 3. Re-resolve device from saved storage to prevent targeting deleted or modified devices
        let currentDevice = try resolveDevice(id: device.id.uuidString)
        guard currentDevice.address == device.address else {
            throw FleetMinerControlError.staleDevice("Miner network address changed since confirmation.")
        }

        // 4. Check preflight freshness
        let now = dateProvider()
        let age = now.timeIntervalSince(preflightObservedAt)
        guard age >= -60 && age <= FleetGlance.freshnessInterval * 3 else {
            throw FleetMinerControlError.staleDevice(
                "Preflight verification timed out or is stale. Refresh required."
            )
        }

        // 5. Perform an immediate fresh read-only check right before the mutation
        let freshInfo: MinerInfo
        do {
            freshInfo = try await infoFetcher(currentDevice)
        } catch {
            throw FleetMinerControlError.staleDevice(
                "Device could not be reached immediately prior to write: \(error.localizedDescription)"
            )
        }

        guard MinerShapeValidator.isValidInfoShape(.object(freshInfo.raw)) else {
            throw FleetMinerControlError.staleDevice("Device telemetry is invalid immediately prior to write.")
        }

        // 6. Re-check demo mode, parameters and saved target AFTER awaiting network info fetch
        if demoChecker() {
            throw FleetMinerControlError.demoModeReadOnly
        }
        try validateParameters(for: action)
        let postFetchDevice = try resolveDevice(id: device.id.uuidString)
        guard postFetchDevice.address == device.address else {
            throw FleetMinerControlError.staleDevice("Miner configuration changed during verification.")
        }

        try Task.checkCancellation()

        // 7. Construct payload according to action
        let (endpoint, body) = try payload(for: action)

        // 8. Execute write (NO RETRY on failure)
        let responseData: Data
        do {
            responseData = try await writeExecutor(currentDevice, endpoint, body)
        } catch {
            throw FleetMinerControlError.writeFailed(error.localizedDescription)
        }
        _ = responseData

        return FleetMinerControlResult(
            success: true,
            message: Self.successMessage(for: action, deviceName: currentDevice.name),
            deviceName: currentDevice.name,
            actionName: action.actionName
        )
    }

    private func payload(for action: FleetMinerControlAction) throws -> (endpoint: MinerEndpoint, body: Data?) {
        switch action {
        case .restart:
            return (.restart, nil)
        case .setFrequency(let mhz):
            let jsonValue = JSONValue.object(["frequency": .number(mhz)])
            return (.settings, try JSONEncoder().encode(jsonValue))
        case .setFanSpeed(let percent):
            let jsonValue = JSONValue.object([
                "autofanspeed": .integer(0),
                "manualFanSpeed": .integer(Int64(percent))
            ])
            return (.settings, try JSONEncoder().encode(jsonValue))
        }
    }

    private static func successMessage(for action: FleetMinerControlAction, deviceName: String) -> String {
        switch action {
        case .restart:
            return "Restart request accepted by \(deviceName)."
        case .setFrequency(let mhz):
            return "Frequency change request to \(mhz) MHz sent to \(deviceName)."
        case .setFanSpeed(let percent):
            return "Manual fan speed request of \(percent)% sent to \(deviceName). "
                + "This request also disables automatic fan mode. "
                + "Check the miner to verify the applied settings."
        }
    }
}
