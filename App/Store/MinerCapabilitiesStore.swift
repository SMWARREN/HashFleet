import Foundation
import Observation
import HashFleetCore

/// In-memory automatic and manually retried read-only compatibility checks. Never persists raw device responses.
@MainActor @Observable
final class MinerCapabilitiesStore {
    private(set) var reports: [UUID: MinerCapabilityReport] = [:]
    private(set) var checking: Set<UUID> = []
    @ObservationIgnored private(set) var probedIdentities: [UUID: DeviceIdentity] = [:]
    @ObservationIgnored private(set) var failedIdentities: [UUID: DeviceIdentity] = [:]
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var work: [UUID: Task<MinerCapabilityReport, Error>] = [:]
    @ObservationIgnored private var generations: [UUID: UUID] = [:]

    init(session: URLSession = .shared) { self.session = session }

    func check(device: MinerDevice, isDemo: Bool) async {
        guard !isDemo, !Task.isCancelled, !checking.contains(device.id) else { return }
        let id = device.id
        let token = UUID()
        generations[id] = token
        checking.insert(id)
        failedIdentities.removeValue(forKey: id)
        probedIdentities.removeValue(forKey: id)
        // A new attempt must not leave previous success visible as current support.
        reports.removeValue(forKey: id)
        let client = MinerAPIClient(device: device, session: session)
        let task = Task.detached(priority: .utility) {
            try await MinerCapabilityProbe(client: client).check()
        }
        work[id] = task
        defer {
            if generations[id] == token {
                checking.remove(id)
                work.removeValue(forKey: id)
                generations.removeValue(forKey: id)
            }
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard !Task.isCancelled, generations[id] == token else { return }
            reports[id] = result
            if let info = result.info {
                let identity = DeviceIdentity(info: info)
                if result.asicStatus.isFailed {
                    failedIdentities[id] = identity
                } else {
                    probedIdentities[id] = identity
                }
            }
        } catch {
            guard !Task.isCancelled, generations[id] == token,
                !(error is CancellationError)
            else { return }
            // Unexpected probe failures must not become hardware non-support.
            reports[id] = MinerCapabilityReport(
                infoStatus: .failed(message: "Compatibility check failed. Retry when the miner is reachable."),
                asicStatus: .failed(message: "Compatibility check did not complete.")
            )
        }
    }

    /// Automatically detects capabilities once per device identity. Reuses the already observed
    /// `MinerInfo` from regular polling and executes exactly one GET `/api/system/asic`.
    func autoDetect(device: MinerDevice, observedInfo: MinerInfo, isDemo: Bool) async {
        guard !isDemo, !Task.isCancelled else { return }
        let id = device.id
        guard !checking.contains(id) else { return }

        // Start only after valid poll: shape validator ensures this is a recognized ESP-Miner payload.
        guard MinerShapeValidator.isValidInfoShape(.object(observedInfo.raw)) else { return }

        let identity = DeviceIdentity(info: observedInfo)

        // Once per device+identity: return immediately if already probed or failed.
        if probedIdentities[id] == identity {
            // Preserve the dated check snapshot. Current telemetry is held separately by FleetStore.
            return
        }
        if failedIdentities[id] == identity {
            return
        }

        let token = UUID()
        generations[id] = token
        checking.insert(id)

        let client = MinerAPIClient(device: device, session: session)
        let probeTask = Task.detached(priority: .utility) { () -> MinerCapabilityReport in
            try Task.checkCancellation()
            let (asicJson, asicStatus) = await Self.probeSingleASIC(client: client)
            try Task.checkCancellation()
            return MinerCapabilityReport(
                info: observedInfo,
                asic: asicJson,
                infoStatus: .supported,
                asicStatus: asicStatus,
                checkedAt: Date()
            )
        }
        work[id] = probeTask
        defer {
            if generations[id] == token {
                checking.remove(id)
                work.removeValue(forKey: id)
                generations.removeValue(forKey: id)
            }
        }
        do {
            let report = try await withTaskCancellationHandler {
                try await probeTask.value
            } onCancel: {
                probeTask.cancel()
            }
            record(report, id: id, identity: identity, token: token, isDemo: isDemo)
        } catch {
            recordFailure(id: id, token: token, isDemo: isDemo, info: observedInfo)
        }
    }

    /// Stores a completed probe result, unless the pass was cancelled or superseded.
    private func record(
        _ report: MinerCapabilityReport,
        id: UUID,
        identity: DeviceIdentity,
        token: UUID,
        isDemo: Bool
    ) {
        guard !Task.isCancelled, generations[id] == token, !isDemo else { return }
        if report.asicStatus.isFailed {
            failedIdentities[id] = identity
            probedIdentities.removeValue(forKey: id)
        } else {
            probedIdentities[id] = identity
            failedIdentities.removeValue(forKey: id)
        }
        reports[id] = report
    }

    /// Cancellation never marks an identity as failed; it is simply retried on the next pass.
    private func recordFailure(id: UUID, token: UUID, isDemo: Bool, info: MinerInfo) {
        guard !Task.isCancelled, generations[id] == token, !isDemo else { return }
        failedIdentities[id] = DeviceIdentity(info: info)
        probedIdentities.removeValue(forKey: id)
        reports[id] = MinerCapabilityReport(
            info: info,
            asic: nil,
            infoStatus: .supported,
            asicStatus: .failed(message: "Automatic ASIC capability check did not complete."),
            checkedAt: Date()
        )
    }

    func remove(_ id: UUID) {
        work.removeValue(forKey: id)?.cancel()
        generations.removeValue(forKey: id)
        checking.remove(id)
        reports.removeValue(forKey: id)
        probedIdentities.removeValue(forKey: id)
        failedIdentities.removeValue(forKey: id)
    }

    @discardableResult
    func cancelAll() -> [Task<MinerCapabilityReport, Error>] {
        let pending = Array(work.values)
        for task in pending { task.cancel() }
        work.removeAll()
        generations.removeAll()
        checking.removeAll()
        return pending
    }

    func reset() {
        cancelAll()
        reports.removeAll()
        probedIdentities.removeAll()
        failedIdentities.removeAll()
    }

    private nonisolated static func probeSingleASIC(client: MinerAPIClient) async -> (JSONValue?, MinerProbeStatus) {
        if Task.isCancelled { return (nil, .failed(message: "Cancelled")) }
        do {
            let data = try await client.execute(.asic)
            if Task.isCancelled { return (nil, .failed(message: "Cancelled")) }
            let json: JSONValue
            do {
                json = try JSONDecoder().decode(JSONValue.self, from: data)
            } catch {
                return (nil, .failed(message: "ASIC response was not valid JSON."))
            }
            guard case .object = json else {
                return (nil, .failed(message: "ASIC response was not a JSON object."))
            }
            guard MinerShapeValidator.isValidASICShape(json) else {
                return (nil, .failed(message: "Unrecognized /api/system/asic response shape."))
            }
            return (json, .supported)
        } catch {
            if Task.isCancelled || error is CancellationError { return (nil, .failed(message: "Cancelled")) }
            return (nil, asicProbeErrorStatus(error))
        }
    }

    private nonisolated static let unreachableMessage =
        "Could not reach the miner. Check its address, network access and Wi-Fi, then retry."

    private nonisolated static func asicProbeErrorStatus(_ error: any Error) -> MinerProbeStatus {
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return .failed(message: "Cancelled")
        }
        guard let apiError = error as? MinerAPIError else {
            return .failed(message: unreachableMessage)
        }
        switch apiError {
        case .http(let statusCode, _, _):
            if MinerCapabilityProbe.isUnsupportedStatus(statusCode) {
                return .unsupported(statusCode: statusCode)
            }
            let message = "HTTP \(statusCode): \(HTTPURLResponse.localizedString(forStatusCode: statusCode))"
            return .failed(message: message)
        case .invalidAddress:
            return .failed(message: "Invalid miner address.")
        case .invalidResponse:
            return .failed(message: "The miner returned a non-HTTP response.")
        default:
            return .failed(message: unreachableMessage)
        }
    }

}

/// Key identifying a miner's hardware and firmware version configuration.
struct DeviceIdentity: Hashable, Sendable {
    let firmwareVersion: String?
    let axeOSVersion: String?
    let boardVersion: String?
    let asicModel: String?

    init(info: MinerInfo) {
        self.firmwareVersion = MinerCapabilityPresentation.firmwareVersion(info: info)
        self.axeOSVersion = MinerCapabilityPresentation.axeOSVersion(info: info)
        self.boardVersion = MinerCapabilityPresentation.boardVersion(info: info, asic: nil)
        self.asicModel = MinerCapabilityPresentation.asicModel(info: info, asic: nil)
    }
}
