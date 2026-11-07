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

    private(set) var canSend = false
    private(set) var status = "Checking Apple Watch…"
    @ObservationIgnored private var hasStarted = false

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
        guard canSend else { return }
        do {
            let transfer = try WatchFleetSetupTransfer(miners: miners)
            let data = try JSONEncoder().encode(transfer)
            try WCSession.default.updateApplicationContext([Self.payloadKey: data])
            status = "Setup queued for your Watch. Open Hash Fleet there and confirm Import. Your existing Watch miners are kept."
        } catch {
            status = "Setup could not be queued. Check the Watch connection and try again."
        }
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
}
#endif
