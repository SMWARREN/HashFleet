import Foundation
import Observation
import WatchConnectivity
import HashFleetWatchCore

/// An optional inbox, not a data dependency. A Watch with no paired/available phone can
/// add miners, restore its local cache and refresh HTTP readings without starting this inbox.
@MainActor @Observable
final class WatchConfigurationReceiver: NSObject, WCSessionDelegate {
    var pending: WatchFleetSetupTransfer?
    private(set) var status: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hasStarted = false
    private static let payloadKey = "app.hashfleet.watch-setup.v1"
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

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                            error: (any Error)?) {
        guard error == nil, state == .activated else { return }
        Task { @MainActor [weak self] in
            guard let data = WCSession.default.receivedApplicationContext[Self.payloadKey] as? Data else { return }
            self?.receive(data)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Extract the Sendable value before crossing the delegate's executor boundary.
        guard let data = applicationContext["app.hashfleet.watch-setup.v1"] as? Data else { return }
        Task { @MainActor [weak self] in self?.receive(data) }
    }
}
