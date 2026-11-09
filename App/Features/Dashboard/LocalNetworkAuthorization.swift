import Foundation
import Network
import Observation

/// A short, explicitly requested Bonjour round trip, not a cached privacy preference.
/// NWBrowser.ready is not proof of approval. Only discovering our unique service on a
/// non-loopback interface unlocks local actions. The browser remains alive to observe denial.
@MainActor @Observable
final class LocalNetworkAuthorization {
    enum Status: Equatable { case notRequested, requesting, granted, denied }

    static let serviceType = "_hashfleet._tcp"
    static let grantedKey = "app.hashfleet.localNetworkApproved.v1"

    private(set) var status: Status = .notRequested
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var attempt: UUID?

    init(defaults: UserDefaults = .standard) {
        // Retire the old false-positive flag. Privacy permission is owned by the OS and
        // may have changed since the last sheet, launch, or network connection.
        #if os(macOS)
        // Native navigation may construct destinations before presentation. Repeatedly
        // removing an absent defaults key still broadcasts a preferences change.
        // Retire the legacy flag once, without generating a render-time write loop.
        if defaults.object(forKey: Self.grantedKey) != nil {
            defaults.removeObject(forKey: Self.grantedKey)
        }
        #else
        defaults.removeObject(forKey: Self.grantedKey)
        #endif
    }

    var isGranted: Bool { status == .granted }

    /// Called only from an explicit user action. Never starts a subnet scan.
    func request() {
        guard status != .requesting else { return }
        cancel()
        #if os(macOS)
        // The Mac app is sandboxed without the network.server entitlement, so it cannot
        // publish the temporary Bonjour probe. macOS prompts on the first local connection
        // itself, and a denial surfaces as a connection failure handled by markDenied().
        status = .granted
        return
        #endif
        let id = UUID()
        attempt = id
        status = .requesting
        let serviceName = "HashFleet-\(id.uuidString)"
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        do {
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(name: serviceName, type: Self.serviceType)
            // No application protocol or device control is exposed by this temporary listener.
            listener.newConnectionHandler = { $0.cancel() }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.attempt == id else { return }
                    if case .failed(let error) = state {
                        self.finish(Self.isPolicyDenied(error) ? .denied : .notRequested)
                    }
                }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            finish(.notRequested)
            return
        }

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: "local."), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.attempt == id else { return }
                switch state {
                case .waiting(let error), .failed(let error):
                    if Self.isPolicyDenied(error) { self.finish(.denied) } else if case .failed = state { self.finish(.notRequested) }
                default:
                    // In particular, .ready is not permission evidence.
                    break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.contains { result in
                guard case .service(let name, _, _, _) = result.endpoint,
                      name == serviceName else { return false }
                return result.interfaces.contains { $0.type != .loopback }
            }
            Task { @MainActor [weak self] in
                guard let self, self.attempt == id, found else { return }
                self.timeout?.cancel()
                self.timeout = nil
                self.status = .granted
            }
        }
        self.browser = browser
        browser.start(queue: .main)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self, self.attempt == id else { return }
            // An unanswered prompt, unavailable network, or service error is not approval.
            self.finish(.notRequested)
        }
    }

    static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == -65570 }
        return false
    }

    func cancel() {
        attempt = nil
        timeout?.cancel()
        timeout = nil
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
        status = .notRequested
    }

    private func finish(_ result: Status) {
        cancel()
        status = result
    }

    func markDenied() { finish(.denied) }
}
