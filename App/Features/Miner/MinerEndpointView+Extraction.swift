import SwiftUI
import UniformTypeIdentifiers
import Observation
import HashFleetCore

enum MinerWriteAvailability {
    static func allows(
        _ snapshot: MinerSnapshot?,
        device: MinerDevice,
        currentDevices: [MinerDevice],
        isDemo: Bool,
        now: Date = .now
    ) -> Bool {
        !isDemo
            && currentDevices.contains { $0.id == device.id && $0.address == device.address }
            && allows(snapshot, now: now)
    }

    static func allows(_ snapshot: MinerSnapshot?, now: Date = .now) -> Bool {
        guard let snapshot, !snapshot.isCached, !snapshot.isReconnecting, snapshot.error == nil, snapshot.info != nil,
            let updatedAt = snapshot.updatedAt
        else { return false }
        // Identical HTTP responses intentionally retain updatedAt, but still advance the
        // complete observation clock. A freshly re-read unchanged value is not stale cache.
        let observed = max(updatedAt, snapshot.completeSnapshotAt ?? updatedAt)
        let age = now.timeIntervalSince(observed)
        return age >= -60 && age <= FleetGlance.freshnessInterval * 3
    }
}

struct MinerOfflineSettingsNotice: View {
    let snapshot: MinerSnapshot?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                snapshot?.isReconnecting == true ? "Reconnecting · read only" : "Offline or stale · read only",
                systemImage: snapshot?.isReconnecting == true ? "arrow.clockwise" : "wifi.slash"
            )
                .fleetFont(.subheadline, weight: .semibold)
            if let date = snapshot?.updatedAt, snapshot?.info != nil {
                Text("Last known settings · last seen \(date.formatted(date: .abbreviated, time: .standard))")
            } else {
                Text("No current connection confirmed.")
            }
            Text("Reconnect and refresh before changing settings. Cached readings are not live.")
            if snapshot?.isCached == true { Text("Passwords and wallet credentials are not stored in the cache.") }
        }
        .fleetFont(.caption)
        .foregroundStyle(snapshot?.isReconnecting == true ? FleetTheme.secondary : FleetTheme.warning)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("miner.offlineReadOnly")
    }
}

@Observable @MainActor
final class MinerOperationModel {
    var isRunning = false
    var response = ""
    var error: String?
    var capability = "Unverified on this firmware"
    var exportedFile: URL?
    var exportError: String?
    @ObservationIgnored private var responseData: Data?
    @ObservationIgnored private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func clearExport() {
        if let file = exportedFile { try? FileManager.default.removeItem(at: file) }
        exportedFile = nil
        exportError = nil
    }

    func prepareExport(isLog: Bool) {
        clearExport()
        guard let responseData else { return }
        do {
            let filename = isLog ? "miner-logs" : "miner-response"
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(filename)-\(UUID().uuidString).txt")
            try responseData.write(to: file, options: [.atomic, .completeFileProtection])
            exportedFile = file
        } catch {
            exportError =
                "Device request succeeded, but export could not be prepared: " + "\(error.localizedDescription)"
        }
    }

    func execute(
        device: MinerDevice,
        endpoint: MinerEndpoint,
        body: Data?,
        query: [URLQueryItem],
        isDemo: Bool,
        writeAuthorized: @MainActor () -> Bool = { false }
    ) async {
        guard !isRunning else { return }
        guard !isDemo else {
            error = "Demo mode is read only. No request was sent. Connect a real miner to use " + "endpoint tools."
            return
        }
        guard !MinerRequestSafety.isWrite(endpoint) || writeAuthorized() else {
            error =
                "Miner offline or stale. Settings are read only until a fresh connection succeeds. "
                + "No write was sent."
            return
        }
        isRunning = true
        error = nil
        response = ""
        clearExport()
        responseData = nil
        defer { isRunning = false }
        do {
            try Task.checkCancellation()
            let client = MinerAPIClient(device: device, session: session)
            // A snapshot may have been fresh at review but the miner can disconnect before Apply.
            // Require a valid read-only Info response immediately before any mutation.
            if MinerRequestSafety.isWrite(endpoint) {
                let preflight = try await client.info()
                try Task.checkCancellation()
                if let message = MinerTuningHardwarePolicy.restriction(
                    device: device,
                    voltage: MinerRequestSafety.coreVoltage(in: body),
                    info: preflight
                ) {
                    throw MinerToolError.message(message + " No request was sent.")
                }
                // Re-read the current Demo mode, identity and freshness after suspension.
                // A Boolean captured before the Info request cannot revoke a reviewed write.
                guard writeAuthorized() else {
                    throw MinerToolError.message(
                        "The miner connection changed during review. No request was sent."
                    )
                }
            }
            try Task.checkCancellation()
            let data = try await client.execute(endpoint, body: body, query: query)
            capability = "Responded successfully on this firmware"
            let display = MinerRequestSafety.pretty(data)
            response =
                display.isEmpty
                ? "Request completed successfully with an empty response."
                : String(display.prefix(100_000))
            if display.count > 100_000 {
                response += "\n\n[Display truncated. Share the file for the complete response.]"
            }
            responseData = data
        } catch {
            self.error = error.localizedDescription
            capability = "Request failed. Support is not confirmed."
        }
    }
}

extension MinerEndpointView {
    static func template(for endpoint: MinerEndpoint) -> String {
        switch endpoint {
        case .boot:
            return "{\n  \"partition\": \"\"\n}"
        case .updatePool:
            return "{\n  \"stratumURL\": \"\",\n  \"stratumPort\": 3333,\n  \"stratumUser\": \"\"\n}"
        case .updateTheme:
            return "{\n  \"colorScheme\": \"\",\n  \"primaryColor\": \"\"\n}"
        default:
            return "{\n\n}"
        }
    }
}
