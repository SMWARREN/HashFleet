import Foundation
import HashFleetCore

/// A separately sourced device restriction, not a firmware option or an encoding limit.
/// Canonical fleet playbook: Gamma 601a must stay at or below 1150 mV VCORE.
enum MinerTuningHardwarePolicy {
    static func maximumCoreVoltage(device: MinerDevice, info: MinerInfo? = nil) -> Double? {
        let host = (try? device.validatedURL())?.host?.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let board = info?.raw["boardVersion"]?.stringValue?.lowercased()
        return host == "192.0.2.221" || board == "601a" ? 1150 : nil
    }

    static func restriction(device: MinerDevice, voltage: Double?, info: MinerInfo? = nil) -> String? {
        guard let voltage, let maximum = maximumCoreVoltage(device: device, info: info), voltage > maximum else {
            return nil
        }
        return "Gamma 601a has a verified 1150 mV core-voltage ceiling. Lower the staged voltage before applying."
    }
}

/// This is the production write path. Verification uses a NEW one-shot Info request after PATCH,
/// never a FleetStore refresh that could join a read which began before the write.
@MainActor
struct MinerTuningApplyService {
    enum Result {
        case verified(MinerInfo)
        case unverified(String)
    }

    enum ApplyError: LocalizedError {
        case blocked(String)
        var errorDescription: String? {
            switch self {
            case .blocked(let message): message
            }
        }
    }

    var session: URLSession = .shared

    func apply(
        device: MinerDevice,
        payload: JSONValue,
        isDemo: Bool,
        writeAuthorized: () -> Bool
    ) async throws -> Result {
        guard !isDemo, writeAuthorized() else {
            throw ApplyError.blocked("Demo, offline or stale miners are read only. No tuning request was sent.")
        }
        let validated = try Self.validatedPayload(payload)
        try Self.checkPolicy(device: device, payload: validated)
        let client = MinerAPIClient(device: device, session: session)
        let preflight = try await client.info()
        try Task.checkCancellation()
        try Self.checkPolicy(device: device, payload: validated, info: preflight)
        guard writeAuthorized() else {
            throw ApplyError.blocked("The miner connection changed during review. No tuning request was sent.")
        }
        let body = try JSONEncoder().encode(validated)
        _ = try await client.execute(.settings, body: body)
        // A successful HTTP response only means the request was accepted, not that settings stuck.
        do {
            let readback = try await client.info()
            guard Self.matches(validated, info: readback) else {
                return .unverified("Request sent, but fresh settings do not match the reviewed change. The draft is retained. Check the miner before trying again.")
            }
            return .verified(readback)
        } catch {
            return .unverified("Request sent, but a fresh readback could not verify it. The draft is retained. Refresh and check the miner before trying again.")
        }
    }

    static func matches(_ payload: JSONValue, info: MinerInfo) -> Bool {
        guard let fields = payload.objectValue, !fields.isEmpty else { return false }
        return fields.allSatisfy { key, target in
            guard let expected = target.doubleValue, let observed = info.raw[key]?.doubleValue,
                expected.isFinite, observed.isFinite else { return false }
            return key == "frequency" ? abs(expected - observed) <= 0.01 : expected == observed
        }
    }

    private static func validatedPayload(_ payload: JSONValue) throws -> JSONValue {
        guard let fields = payload.objectValue, !fields.isEmpty,
            Set(fields.keys).isSubset(of: ["frequency", "coreVoltage"]),
            fields.values.allSatisfy({ $0.doubleValue != nil })
        else { throw ApplyError.blocked("The reviewed tuning payload is invalid. No request was sent.") }
        return try MinerTuningSessionMath.tuningPayload(
            frequency: fields["frequency"]?.doubleValue,
            coreVoltage: fields["coreVoltage"]?.doubleValue,
            riskAcknowledged: true
        )
    }

    private static func checkPolicy(device: MinerDevice, payload: JSONValue, info: MinerInfo? = nil) throws {
        if let message = MinerTuningHardwarePolicy.restriction(
            device: device, voltage: payload.objectValue?["coreVoltage"]?.doubleValue, info: info
        ) {
            throw ApplyError.blocked(message)
        }
    }
}
