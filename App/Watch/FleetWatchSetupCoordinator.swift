#if os(iOS)
import Foundation
import Observation
import WatchConnectivity
import HashFleetCore
import HashFleetWatchCore

/// This channel transfers configuration only after a user action. Watch telemetry is fetched
/// independently over HTTP and never depends on WCSession reachability or the phone's battery.
@MainActor @Observable
final class FleetWatchSetupCoordinator: NSObject, WCSessionDelegate {
    static let shared = FleetWatchSetupCoordinator()
    static let payloadKey = "app.hashfleet.watch-setup.v1"

    static func syncIfPossible(devices: [MinerDevice], isDemo: Bool) {
        guard WCSession.isSupported() else { return }
        let eligible = FleetWatchSetupSelection(devices: devices, isDemo: isDemo).miners
        guard !eligible.isEmpty else { return }
        shared.send(eligible)
    }

    static func syncReadingsIfPossible(
        devices: [MinerDevice],
        snapshots: [UUID: MinerSnapshot],
        isDemo: Bool
    ) {
        guard WCSession.isSupported(), !isDemo else { return }
        let eligible = FleetWatchSetupSelection(devices: devices, isDemo: false).miners
        guard !eligible.isEmpty else { return }
        let readings: [WatchMinerReading] = eligible.compactMap { miner in
            guard let snapshot = snapshots[miner.id], let info = snapshot.info else { return nil }
            let observedAt = snapshot.completeSnapshotAt ?? snapshot.updatedAt ?? Date()
            return WatchMinerReading(
                minerID: miner.id,
                observedAt: observedAt,
                hashrateGHs: info.hashRate,
                powerWatts: info.power > 0 ? info.power : nil,
                chipTemperatureC: info.temp > 0 ? info.temp : nil,
                vrTemperatureC: info.vrTemp > 0 ? info.vrTemp : nil,
                uptimeSeconds: info.uptimeSeconds > 0 ? Double(info.uptimeSeconds) : nil,
                acceptedShares: info.sharesAccepted,
                rejectedShares: info.sharesRejected
            )
        }
        guard !readings.isEmpty else { return }
        shared.pushCachedReadings(readings)
    }

    private(set) var canSend = false
    private(set) var status = "Checking Apple Watch…"
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var pendingMiners: [WatchMiner]?
    @ObservationIgnored private var lastReadingsSyncAt: Date = .distantPast
    private static let readingsSyncInterval: TimeInterval = 15

    func start() {
        guard !hasStarted else { return }
        guard WCSession.isSupported() else {
            status = "Apple Watch setup is available on a paired iPhone."
            return
        }
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing"),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            status = "Watch transfer is disabled in app tests."
            return
        }
        hasStarted = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ miners: [WatchMiner]) {
        start()
        guard WCSession.isSupported() else { return }
        guard canSend else {
            pendingMiners = miners
            return
        }
        dispatchTransfer(miners)
    }

    private func dispatchTransfer(_ miners: [WatchMiner]) {
        guard !miners.isEmpty else { return }
        let session = WCSession.default
        do {
            let transfer = try WatchFleetSetupTransfer(miners: miners)
            let data = try JSONEncoder().encode(transfer)
            var context = session.applicationContext
            context[Self.payloadKey] = data
            try? session.updateApplicationContext(context)
            if session.isReachable {
                session.sendMessage([Self.payloadKey: data], replyHandler: nil, errorHandler: nil)
            }
            session.transferUserInfo([Self.payloadKey: data])
            status = "Setup sent to your Watch."
        } catch {
            status = "Setup could not be queued."
        }
    }

    private func pushCachedReadings(_ readings: [WatchMinerReading]) {
        start()
        guard canSend else { return }
        let now = Date()
        guard now.timeIntervalSince(lastReadingsSyncAt) >= Self.readingsSyncInterval else { return }
        let session = WCSession.default
        guard let data = try? JSONEncoder().encode(WatchCachedReadingsTransfer(readings: readings, sentAt: now)) else {
            return
        }
        lastReadingsSyncAt = now
        var context = session.applicationContext
        context[WatchRelayKeys.cachedReadings] = data
        try? session.updateApplicationContext(context)
    }

    private func updateAvailability() {
        let session = WCSession.default
        canSend = session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
        if !session.isPaired {
            status = "Pair an Apple Watch with this iPhone, or add miners directly on your Watch."
        } else if !session.isWatchAppInstalled {
            status = "Install Hash Fleet from the Watch app on your iPhone, then return here."
        } else if canSend {
            status = "Ready. Only miner names and local addresses are sent, never credentials or readings."
            if let pending = pendingMiners {
                pendingMiners = nil
                dispatchTransfer(pending)
            }
        } else {
            status = "Waiting for the Watch connection. You can also add miners directly on the Watch."
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: (any Error)?) {
        let failed = error != nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            if failed {
                self.canSend = false
                self.status = "Watch setup is unavailable. You can still add miners directly on your Watch."
            } else {
                self.updateAvailability()
            }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.updateAvailability() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.canSend = false }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.canSend = false
            WCSession.default.activate()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let requestData = message[WatchRelayKeys.cgminerRequest] as? Data,
              let request = try? JSONDecoder().decode(WatchMinerRelayRequest.self, from: requestData) else {
            replyHandler([:])
            return
        }
        // Validate the host as a safe local endpoint before opening a TCP socket.
        guard let target = request.validatedEndpoint() else {
            let payload = (try? JSONEncoder().encode(WatchMinerRelayResponse(error: "invalid_endpoint"))) ?? Data()
            replyHandler([WatchRelayKeys.cgminerResponse: payload])
            return
        }
        struct ReplyBox: @unchecked Sendable {
            let reply: ([String: Any]) -> Void
        }
        let replyBox = ReplyBox(reply: replyHandler)
        Task {
            let response: WatchMinerRelayResponse
            if let reading = try? await WatchMinerHTTPClient.queryCgminerReading(
                host: target.host,
                port: target.port,
                minerID: request.minerID,
                observedAt: Date(),
                timeout: 4
            ) {
                response = WatchMinerRelayResponse(reading: reading)
            } else {
                response = WatchMinerRelayResponse(error: "unreachable")
            }
            let payload = (try? JSONEncoder().encode(response)) ?? Data()
            replyBox.reply([WatchRelayKeys.cgminerResponse: payload])
        }
    }
}
#endif
