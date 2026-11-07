import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import HashFleetCore

@MainActor
@Observable
final class FleetRemotePushCoordinator {
    static var isTestProcess: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    #if os(macOS)
    // Scheduled check delivery relies on the iOS notification-service extension. The native Mac
    // monitors while running and must not enroll or overwrite an iOS service configuration.
    static let shared = FleetRemotePushCoordinator(
        defaults: .standard, credentials: FleetRemotePushKeychain(), client: FleetRemotePushClient(),
        restricted: true, configurationDefaults: nil)
    #else
    static let shared = FleetRemotePushCoordinator(
        defaults: .standard, credentials: FleetRemotePushKeychain(), client: FleetRemotePushClient(),
        restricted: isTestProcess, configurationDefaults: FleetSharedStore.defaults)
    #endif

    private(set) var settings = FleetRemotePushSettings()
    private(set) var providerReady = false
    private(set) var isWorking = false
    private(set) var isDemo = true
    private(set) var isEnrolled = false
    private(set) var requiresReconnect = false
    private(set) var isRequestingPermission = false
    private(set) var message = "Off by default. Choose which miners receive scheduled check requests."
    let restricted: Bool
    private let defaults: UserDefaults
    private let configurationDefaults: UserDefaults?
    private let credentials: any FleetRemotePushCredentialStore
    private let client: any FleetRemotePushTransport
    private let permission: @MainActor () async -> Bool
    private let register: @MainActor () -> Void
    private let unregister: @MainActor () -> Void
    private var devices: [MinerDevice] = []
    private var preparedTargets: [UUID: FleetScheduledCheckTarget] = [:]
    private var deviceToken: String?
    private var needsSave = false
    private var registrationConfirmed = false
    private var revision = 0
    private static let settingsKey = "app.hashfleet.remotePush.settings"
    private static let dirtyKey = "app.hashfleet.remotePush.pendingSync"
    private static let confirmedKey = "app.hashfleet.remotePush.registrationConfirmed"
    var canConnect: Bool { !restricted && !isDemo }

    init(defaults: UserDefaults, credentials: any FleetRemotePushCredentialStore,
         client: any FleetRemotePushTransport, restricted: Bool,
         configurationDefaults: UserDefaults? = nil,
         permission: @escaping @MainActor () async -> Bool = { await FleetLocalNotifications.requestAuthorization() },
         register: @escaping @MainActor () -> Void = { FleetRemotePushPlatform.register() },
         unregister: @escaping @MainActor () -> Void = { FleetRemotePushPlatform.unregister() }) {
        self.defaults = defaults
        self.configurationDefaults = configurationDefaults
        self.credentials = credentials
        self.client = client
        self.restricted = restricted
        self.permission = permission
        self.register = register
        self.unregister = unregister
        if !restricted, let data = defaults.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(FleetRemotePushSettings.self, from: data),
           saved.miners.count <= 64, Set(saved.miners.map(\.id)).count == saved.miners.count {
            settings = saved
            needsSave = defaults.bool(forKey: Self.dirtyKey)
            registrationConfirmed = defaults.bool(forKey: Self.confirmedKey)
        }
        let existing = FleetScheduledCheckStorage.load(defaults: configurationDefaults)
        preparedTargets = Dictionary(existing.targets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // The app's fleet/demo state must be supplied before any extension check is permitted.
        publishLocalConfiguration()
    }

    func updateFleet(devices: [MinerDevice], snapshots: [UUID: MinerSnapshot], isDemo: Bool) {
        self.isDemo = isDemo
        guard canConnect else { publishLocalConfiguration(); return }
        var seen = Set<UUID>()
        self.devices = Array(devices.filter { $0.kind == .espMiner && seen.insert($0.id).inserted }.prefix(64))
        let updated = settings.merging(self.devices)
        if updated != settings {
            needsSave = needsSave || updated.wirePreferences != settings.wirePreferences
            settings = updated
            revision += 1
        }
        var prepared: [UUID: FleetScheduledCheckTarget] = [:]
        for device in self.devices {
            guard let baseURL = try? device.validatedURL() else { continue }
            if var previous = preparedTargets[device.id], previous.baseURL == baseURL {
                previous.name = FleetRemoteMinerSchedule.safeName(device.name)
                prepared[device.id] = previous
            }
            if let snapshot = snapshots[device.id], !snapshot.isCached, snapshot.error == nil,
               let observedAt = snapshot.completeSnapshotAt, (-120...600).contains(Date.now.timeIntervalSince(observedAt)),
               let info = snapshot.info,
               let rawMAC = ["macAddr", "macAddress", "mac"].compactMap({ key -> String? in
                   if case .string(let value)? = info.raw[key] { return value }
                   return nil
               }).first,
               let mac = FleetScheduledCheckTarget.normalizedMAC(rawMAC) {
                let target = FleetScheduledCheckTarget(id: device.id, name: FleetRemoteMinerSchedule.safeName(device.name),
                    baseURL: baseURL, expectedMAC: mac)
                if target.isValid { prepared[device.id] = target }
            }
        }
        preparedTargets = prepared
        persist()
    }

    func preparationStatus(id: String) -> String {
        guard let uuid = UUID(uuidString: id), preparedTargets[uuid] != nil else {
            return "Refresh this miner in Fleet using a private IPv4 address to prepare its identity for scheduled checks."
        }
        return "Identity prepared on this device. A push can attempt a check when this device can reach the miner."
    }

    func resume() async {
        guard canConnect, !requiresReconnect else { return }
        if settings.enabled, deviceToken == nil {
            message = "Registering this device with Apple Push Notifications…"
            register()
        } else if settings.enabled || (try? credentials.load()) != nil {
            await sync()
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard canConnect else { message = FleetRemotePushError.restricted.message; return }
        if enabled {
            guard !isRequestingPermission, !requiresReconnect else { return }
            guard !settings.miners.isEmpty else { message = "Add a miner before enabling summaries."; return }
            guard settings.miners.contains(where: { $0.enabled && UUID(uuidString: $0.id).map { preparedTargets[$0] != nil } == true }) else {
                message = "Refresh at least one selected miner in Fleet to prepare its local identity before enabling scheduled checks."
                return
            }
            let requestRevision = revision
            isRequestingPermission = true
            let granted = await permission()
            isRequestingPermission = false
            guard revision == requestRevision, canConnect else { return }
            guard granted else { message = FleetRemotePushError.permission.message; return }
        }
        settings.enabled = enabled
        changed()
        if !enabled { deviceToken = nil; unregister() }
        if enabled, deviceToken == nil {
            message = "Registering this device with Apple Push Notifications…"
            register()
        } else {
            await sync()
        }
    }

    func updateSchedule(id: String, enabled: Bool? = nil, interval: Int? = nil) {
        guard canConnect, let index = settings.miners.firstIndex(where: { $0.id == id }) else { return }
        if let enabled { settings.miners[index].enabled = enabled }
        if let interval, FleetRemoteMinerSchedule.intervals.contains(interval) {
            settings.miners[index].intervalMinutes = interval
        }
        changed()
        message = "Changes apply on this device now. Save schedules to update the server."
    }

    func didRegister(deviceToken: Data) {
        guard canConnect, settings.enabled, !deviceToken.isEmpty else { return }
        self.deviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await sync() }
    }

    func registrationFailed() {
        guard canConnect, settings.enabled else { return }
        message = "Apple Push registration is not available on this build or device. Check push signing and try again."
    }

    func sync() async {
        guard canConnect, !requiresReconnect, !isWorking else { return }
        let currentRevision = revision
        let desired = settings
        let savingChanges = needsSave
        isWorking = true
        defer {
            isWorking = false
            if revision != currentRevision, canConnect, !requiresReconnect { Task { await sync() } }
        }
        do {
            var identity = try credentials.load()
            try await handleExistingIdentity(identity: identity, currentRevision: currentRevision, savingChanges: savingChanges)
            guard revision == currentRevision, canConnect else { return }
            if identity == nil {
                guard settings.enabled, deviceToken != nil else {
                    message = "Enable summaries to connect this device. No scheduling data has been sent."
                    return
                }
                let created = try FleetRemotePushKeychain.generate()
                try credentials.save(created)
                identity = created
            }
            guard let identity else { throw FleetRemotePushError.credentials }
            try await registerIdentity(identity, currentRevision: currentRevision, savingChanges: savingChanges, desired: desired)
            guard revision == currentRevision, canConnect else { return }
            if savingChanges {
                try await handleSavingChanges(identity: identity, currentRevision: currentRevision, desired: desired)
            }
            guard revision == currentRevision, canConnect else { return }
            try await handleFinalStatus(currentRevision: currentRevision, identity: identity)
            isEnrolled = true
            if !settings.enabled { deviceToken = nil; unregister() }
            updateMessageForSettings()
        } catch let error as FleetRemotePushError {
            handleAuthError(error)
        } catch {
            message = FleetRemotePushError.connection.message
        }
    }

    private func handleExistingIdentity(identity: FleetRemotePushIdentity?, currentRevision: Int, savingChanges: Bool) async throws {
        guard let existing = identity, registrationConfirmed else { return }
        let status = try await client.send(action: "status", method: "GET", identity: existing, body: nil)
        applyStatus(status)
        isEnrolled = true
        if !savingChanges, revision == currentRevision, let server = status.settings {
            settings = server.merging(devices)
            persist()
        }
    }

    private func registerIdentity(
        _ identity: FleetRemotePushIdentity, currentRevision: Int,
        savingChanges: Bool, desired: FleetRemotePushSettings
    ) async throws {
        guard let deviceToken, settings.enabled else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let request = FleetRemotePushRegistration(deviceToken: deviceToken, environment: environment,
            miners: desired.miners.map { .init(id: $0.id) })
        let reply = try await send("register", method: "POST", identity: identity, body: request)
        applyStatus(reply)
        isEnrolled = true
        registrationConfirmed = true
        persist()
        if !savingChanges, revision == currentRevision, let server = reply.settings {
            settings = server.merging(devices)
            persist()
        }
    }

    private func handleSavingChanges(identity: FleetRemotePushIdentity, currentRevision: Int, desired: FleetRemotePushSettings) async throws {
        let reply = try await send("preferences", method: "PUT", identity: identity, body: desired.wirePreferences)
        applyStatus(reply)
        if revision == currentRevision {
            settings = (reply.settings ?? desired).merging(devices)
            needsSave = false
            persist()
        }
    }

    private func handleFinalStatus(currentRevision: Int, identity: FleetRemotePushIdentity) async throws {
        let status = try await client.send(action: "status", method: "GET", identity: identity, body: nil)
        applyStatus(status)
        registrationConfirmed = true
        if revision == currentRevision, !needsSave, let server = status.settings {
            settings = server.merging(devices)
            persist()
        }
    }

    private func updateMessageForSettings() {
        message = !settings.enabled ? "Scheduled summaries are off."
            : !providerReady ? "Schedules saved. Apple Push provider activation is still required on hashfleet.app."
            : "Schedule saved. Apple Push can request short checks on this device. Delivery and LAN access are best effort."
    }

    private func handleAuthError(_ error: FleetRemotePushError) {
        if case .authentication = error {
            settings.enabled = false
            needsSave = false
            isEnrolled = false
            requiresReconnect = true
            providerReady = false
            deviceToken = nil
            persist()
            unregister()
            message = "This service connection was revoked or could not be verified. Disconnect it here, then opt in again to reconnect."
            return
        }
        message = error.message
    }

    func disconnect() async {
        guard canConnect, !isWorking else { return }
        settings.enabled = false
        changed()
        deviceToken = nil
        unregister()
        isWorking = true
        defer { isWorking = false }
        do {
            if let identity = try credentials.load() {
                _ = try await client.send(action: "register", method: "DELETE", identity: identity, body: nil)
                try credentials.clear()
            }
            resetConnection()
            message = "Disconnected. This installation's push token and server schedules were removed."
        } catch FleetRemotePushError.authentication {
            do { try credentials.clear() } catch { message = FleetRemotePushError.credentials.message; return }
            resetConnection()
            message = "Local connection cleared. Service access was already revoked, so server deletion could not be verified."
        } catch {
            message = "Disabled on this device, but server deletion could not be confirmed. Keep this connection and retry."
        }
    }

    private func resetConnection() {
        settings = FleetRemotePushSettings().merging(devices)
        needsSave = false
        registrationConfirmed = false
        isEnrolled = false
        requiresReconnect = false
        deviceToken = nil
        providerReady = false
        persist()
    }

    private func changed() { revision += 1; needsSave = true; persist() }
    private func persist() {
        publishLocalConfiguration()
        guard !restricted else { return }
        defaults.set(try? JSONEncoder().encode(settings), forKey: Self.settingsKey)
        defaults.set(needsSave, forKey: Self.dirtyKey)
        defaults.set(registrationConfirmed, forKey: Self.confirmedKey)
    }
    private func publishLocalConfiguration() {
        let enabled = canConnect && settings.enabled && !requiresReconnect
        let selected = Set(settings.miners.filter(\.enabled).compactMap { UUID(uuidString: $0.id) })
        let targets = enabled ? devices.compactMap { selected.contains($0.id) ? preparedTargets[$0.id] : nil } : []
        FleetScheduledCheckStorage.write(.init(enabled: enabled, targets: targets), defaults: configurationDefaults)
    }
    private func applyStatus(_ reply: FleetRemotePushReply) {
        if let ready = reply.providerReady { providerReady = ready }
    }
    private func send<T: Encodable>(_ action: String, method: String, identity: FleetRemotePushIdentity,
                                    body: T) async throws -> FleetRemotePushReply {
        try await client.send(action: action, method: method, identity: identity, body: JSONEncoder().encode(body))
    }
}

#if canImport(UIKit)
@MainActor
final class FleetRemotePushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        FleetRemotePushCoordinator.shared.didRegister(deviceToken: deviceToken)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        FleetRemotePushCoordinator.shared.registrationFailed()
    }
}
#endif

@MainActor
enum FleetRemotePushPlatform {
    static func register() {
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #else
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    static func unregister() {
        #if canImport(UIKit)
        UIApplication.shared.unregisterForRemoteNotifications()
        #else
        NSApplication.shared.unregisterForRemoteNotifications()
        #endif
    }
}
