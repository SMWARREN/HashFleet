import AppIntents
import Foundation
import HashFleetCore

// MARK: - Restart Miner Intent

@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
public struct RestartFleetMinerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Restart Fleet Miner"
    public static let description = IntentDescription(
        "Reboot a saved fleet miner after verifying identity and confirming risks."
    )
    public static var openAppWhenRun: Bool { false }
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @Parameter(title: "Miner")
    public var target: FleetMinerEntity

    public init() {}

    public init(target: FleetMinerEntity) {
        self.target = target
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let executor = FleetMinerControlExecutor.shared
        let action = FleetMinerControlAction.restart

        let result = try await executor.run(deviceID: target.id, action: action) { dialog in
            try await requestFleetConfirmation(dialog: dialog, target: target, parameter: $target)
        }

        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

// MARK: - Set Miner Frequency Intent

@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
public struct SetFleetMinerFrequencyIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Fleet Miner Frequency"
    public static let description = IntentDescription(
        "Set target ASIC clock frequency in MHz on a saved fleet miner after confirmation."
    )
    public static var openAppWhenRun: Bool { false }
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @Parameter(title: "Miner")
    public var target: FleetMinerEntity

    @Parameter(title: "Frequency (MHz)", inclusiveRange: (1, 65535))
    public var frequencyMHz: Double

    public init() {}

    public init(target: FleetMinerEntity, frequencyMHz: Double) {
        self.target = target
        self.frequencyMHz = frequencyMHz
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let executor = FleetMinerControlExecutor.shared
        let action = FleetMinerControlAction.setFrequency(frequencyMHz)

        let result = try await executor.run(deviceID: target.id, action: action) { dialog in
            try await requestFleetConfirmation(dialog: dialog, target: target, parameter: $target)
        }

        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

// MARK: - Set Miner Fan Speed Intent

@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
public struct SetFleetMinerFanSpeedIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Fleet Miner Fan Speed"
    public static let description = IntentDescription(
        "Set manual fan speed percentage (0-100%) on a saved fleet miner, disabling auto cooling."
    )
    public static var openAppWhenRun: Bool { false }
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @Parameter(title: "Miner")
    public var target: FleetMinerEntity

    @Parameter(title: "Fan Speed (%)", inclusiveRange: (0, 100))
    public var fanSpeedPercent: Int

    public init() {}

    public init(target: FleetMinerEntity, fanSpeedPercent: Int) {
        self.target = target
        self.fanSpeedPercent = fanSpeedPercent
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let executor = FleetMinerControlExecutor.shared
        let action = FleetMinerControlAction.setFanSpeed(fanSpeedPercent)

        let result = try await executor.run(deviceID: target.id, action: action) { dialog in
            try await requestFleetConfirmation(dialog: dialog, target: target, parameter: $target)
        }

        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

/// A declined parameter confirmation must cancel the action, just like intent confirmation.
enum FleetMinerControlConfirmation {
    static func requireApproval(_ confirmed: Bool) throws {
        guard confirmed else { throw CancellationError() }
    }
}

private extension AppIntent {
    /// Preserve the complete target/value/risk dialog on both modern and minimum-supported OSes.
    func requestFleetConfirmation(
        dialog: String,
        target: FleetMinerEntity,
        parameter: IntentParameter<FleetMinerEntity>
    ) async throws {
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            try await requestConfirmation(
                conditions: [],
                actionName: .continue,
                dialog: IntentDialog(stringLiteral: dialog)
            )
        } else {
            // Parameter confirmation supports the full dialog on iOS 17/macOS 14 without
            // the deprecated result-based API. Its negative result does not throw automatically.
            let confirmed = try await parameter.requestConfirmation(
                for: target,
                dialog: IntentDialog(stringLiteral: dialog)
            )
            try FleetMinerControlConfirmation.requireApproval(confirmed)
        }
    }
}
