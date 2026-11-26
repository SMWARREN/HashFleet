import Foundation
import Observation
import WatchConnectivity
import HashFleetWatchCore

/// An optional inbox, not a data dependency. A Watch with no paired/available phone can
/// add miners, restore its local cache and refresh HTTP readings without starting this inbox.
@MainActor @Observable
final class WatchConfigurationReceiver: NSObject, WCSessionDelegate {
    var pending: WatchFleetSetupTransfer?
    var latestCachedReadings: WatchCachedReadingsTransfer?
    private(set) var status: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hasStarted = false
    nonisolated static let payloadKey = "app.hashfleet.watch-setup.v1"
    private static let handledKey = "app.hashfleet.watch.last-handled-setup"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    func start() {
        guard !hasStarted, WCSession.isSupported() else { return }
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing"),
              !ProcessInfo.processInfo.arguments.contains("--demo") else { return }
        hasStarted = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func finish() {
        if let pending { defaults.set(pending.id.uuidString, forKey: Self.handledKey) }
        pending = nil
    }

    private func receive(_ data: Data) {
        guard data.count <= 32_768,
              let transfer = try? JSONDecoder().decode(WatchFleetSetupTransfer.self, from: data) else {
            status = "The iPhone setup could not be read. Add miners here or send a new setup."
            return
        }
        guard defaults.string(forKey: Self.handledKey) != transfer.id.uuidString else { return }
        pending = transfer
        status = nil
    }

    private func receiveCachedReadings(_ data: Data) {
        guard data.count <= 65_536,
              let transfer = try? JSONDecoder().decode(WatchCachedReadingsTransfer.self, from: data),
              transfer.version == WatchCachedReadingsTransfer.currentVersion else { return }
        latestCachedReadings = transfer
    }

    /// Relays a cgminer TCP query through the paired iPhone via WatchConnectivity.
    nonisolated static func relayCgminer(miner: WatchMiner, host: String, port: Int) async -> WatchMinerReading? {
        guard WCSession.isSupported() else { return nil }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return nil }
        guard let requestData = try? JSONEncoder().encode(
            WatchMinerRelayRequest(minerID: miner.id, host: host, port: port)
        ) else { return nil }

        return await withCheckedContinuation { continuation in
            final class Once: @unchecked Sendable {
                private let lock = NSLock()
                private var cont: CheckedContinuation<WatchMinerReading?, Never>?
                init(_ cont: CheckedContinuation<WatchMinerReading?, Never>) { self.cont = cont }
                func resume(_ value: WatchMinerReading?) {
                    lock.lock()
                    let c = cont
                    cont = nil
                    lock.unlock()
                    c?.resume(returning: value)
                }
            }
            let once = Once(continuation)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5) {
                once.resume(nil)
            }
            session.sendMessage(
                [WatchRelayKeys.cgminerRequest: requestData],
                replyHandler: { reply in
                    guard let data = reply[WatchRelayKeys.cgminerResponse] as? Data,
                          let response = try? JSONDecoder().decode(WatchMinerRelayResponse.self, from: data) else {
                        once.resume(nil)
                        return
                    }
                    once.resume(response.reading)
                },
                errorHandler: { _ in
                    once.resume(nil)
                }
            )
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard error == nil, state == .activated else { return }
        Task { @MainActor [weak self] in
            let context = WCSession.default.receivedApplicationContext
            if let data = context[Self.payloadKey] as? Data {
                self?.receive(data)
            }
            if let readingsData = context[WatchRelayKeys.cachedReadings] as? Data {
                self?.receiveCachedReadings(readingsData)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Extract the Sendable values before crossing the delegate's executor boundary.
        let setupData = applicationContext[Self.payloadKey] as? Data
        let readingsData = applicationContext[WatchRelayKeys.cachedReadings] as? Data
        Task { @MainActor [weak self] in
            if let setupData { self?.receive(setupData) }
            if let readingsData { self?.receiveCachedReadings(readingsData) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[Self.payloadKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[Self.payloadKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.receive(data) }
    }
}
