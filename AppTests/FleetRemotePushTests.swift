import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Scheduled APNs summaries") @MainActor
struct FleetRemotePushTests {
    @MainActor private final class Credentials: FleetRemotePushCredentialStore {
        var identity: FleetRemotePushIdentity?
        var reads = 0
        func load() throws -> FleetRemotePushIdentity? { reads += 1; return identity }
        func save(_ identity: FleetRemotePushIdentity) throws { self.identity = identity }
        func clear() throws { identity = nil }
    }
    private actor Transport: FleetRemotePushTransport {
        var calls: [String] = []
        var bodies: [Data] = []
        var settings = FleetRemotePushSettings()
        var fail = false
        var authFailure = false
        var healthyStatus = false
        var holdStatus = false
        var statusWaiter: CheckedContinuation<Void, Never>?
        func setFailure(_ value: Bool) { fail = value }
        func setAuthFailure(_ value: Bool) { authFailure = value }
        func setHealthyStatus() { healthyStatus = true }
        func suspendNextStatus() { holdStatus = true }
        func isWaiting() -> Bool { statusWaiter != nil }
        func releaseStatus() { statusWaiter?.resume(); statusWaiter = nil }
        func setEnabled(_ enabled: Bool) { settings.enabled = enabled }
        func recorded() -> [String] { calls }
        func send(action: String, method: String, identity: FleetRemotePushIdentity,
                  body: Data?) async throws -> FleetRemotePushReply {
            calls.append("\(method) \(action)")
            if let body { bodies.append(body) }
            if authFailure { throw FleetRemotePushError.authentication }
            if fail { throw FleetRemotePushError.connection }
            if action == "status", holdStatus {
                holdStatus = false
                await withCheckedContinuation { statusWaiter = $0 }
            }
            if action == "register", method == "POST", let body {
                let value = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
                let miners = try #require(value["miners"] as? [[String: String]])
                if settings.miners.isEmpty {
                    settings.miners = miners.map { .init(id: $0["id"]!, name: "Miner") }
                }
            }
            if action == "preferences", let body {
                settings = try JSONDecoder().decode(FleetRemotePushSettings.self, from: body)
            }
            return .init(ok: true, mode: "device_check_v1", settings: settings, providerReady: healthyStatus)
        }
    }
    @MainActor private final class Fixture {
        let suite = "app.hashfleet.remote-tests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let configurationDefaults: UserDefaults
        let credentials = Credentials()
        let transport = Transport()
        var permissionCount = 0
        var registerCount = 0
        var unregisterCount = 0
        var permissionGranted = true
        var holdPermission = false
        var permissionWaiter: CheckedContinuation<Bool, Never>?
        var device = MinerDevice(name: "Workshop Gamma", address: "192.168.1.50")
        init() {
            defaults = UserDefaults(suiteName: suite)!
            configurationDefaults = UserDefaults(suiteName: suite + ".check")!
        }
        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            configurationDefaults.removePersistentDomain(forName: suite + ".check")
        }
        func model(restricted: Bool = false, demo: Bool = false) -> FleetRemotePushCoordinator {
            let model = FleetRemotePushCoordinator(defaults: defaults, credentials: credentials,
                client: transport, restricted: restricted, configurationDefaults: configurationDefaults,
                permission: {
                    self.permissionCount += 1
                    if self.holdPermission { return await withCheckedContinuation { self.permissionWaiter = $0 } }
                    return self.permissionGranted
                },
                register: { self.registerCount += 1 }, unregister: { self.unregisterCount += 1 })
            model.updateFleet(devices: [device], snapshots: [device.id: snapshot()], isDemo: demo)
            return model
        }
        func snapshot() -> MinerSnapshot {
            let now = Date.now
            return MinerSnapshot(info: MinerInfo(raw: ["macAddr": .string("02:11:22:33:44:55"),
                "hashRate": .number(1_250), "stratumPassword": .string("private-password"),
                "stratumUser": .string("private-wallet")]), updatedAt: now, completeSnapshotAt: now)
        }
        func enroll(_ model: FleetRemotePushCoordinator) async {
            await model.setEnabled(true)
            model.didRegister(deviceToken: Data(repeating: 0xab, count: 32))
            for _ in 0..<500 {
                if model.isEnrolled && !model.isWorking { return }
                await Task.yield()
            }
            #expect(model.isEnrolled && !model.isWorking)
        }
    }

    @Test func malformedAppObservedMACCannotPrepareANewTarget() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model(demo: true)
        var snapshot = fixture.snapshot()
        snapshot.info?.raw["macAddr"] = .string("XY02:11:22:33:44:55")
        model.updateFleet(devices: [fixture.device], snapshots: [fixture.device.id: snapshot], isDemo: false)
        await model.setEnabled(true)
        #expect(!model.settings.enabled)
        #expect(fixture.permissionCount == 0 && fixture.registerCount == 0)
        #expect(await fixture.transport.recorded().isEmpty)
        #expect(FleetScheduledCheckStorage.load(defaults: fixture.configurationDefaults) == .disabled)
    }

    @Test func newInstallIsOffAndDoesNotReadCredentialsOrContactServerOnResume() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        #expect(!model.settings.enabled)
        #expect(model.settings.miners.first?.intervalMinutes == 60)
        #expect(fixture.credentials.reads == 0)
        await model.resume()
        #expect(await fixture.transport.recorded().isEmpty)
        #expect(fixture.permissionCount == 0 && fixture.registerCount == 0)
        #expect(fixture.credentials.identity == nil)
    }

    @Test(arguments: [true, false])
    func demosAndAutomatedRunsNeverEnrollOrUpload(restricted: Bool) async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model(restricted: restricted, demo: !restricted)
        await model.setEnabled(true)
        model.didRegister(deviceToken: Data(repeating: 0xab, count: 32))
        await model.sync()
        #expect(!model.settings.enabled)
        #expect(await fixture.transport.recorded().isEmpty)
        #expect(fixture.credentials.reads == 0 && fixture.permissionCount == 0)
    }

    @Test func permissionDenialLeavesCloudOffAndNeverRegisters() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        fixture.permissionGranted = false
        let model = fixture.model()
        await model.setEnabled(true)
        #expect(!model.settings.enabled)
        #expect(fixture.permissionCount == 1 && fixture.registerCount == 0)
        #expect(await fixture.transport.recorded().isEmpty)
    }

    @Test func explicitOptInWaitsForAPNsTokenAndSavesHourlySettings() async throws {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        await model.setEnabled(true)
        #expect(fixture.registerCount == 1)
        #expect(await fixture.transport.recorded().isEmpty)
        model.didRegister(deviceToken: Data(repeating: 0xab, count: 32))
        for _ in 0..<500 {
            if model.isEnrolled && !model.isWorking { break }
            await Task.yield()
        }
        #expect(model.isEnrolled && model.settings.enabled)
        #expect(model.settings.miners.first?.intervalMinutes == 60)
        #expect(!model.providerReady)
        #expect(model.message.contains("activation"))
        #expect(await fixture.transport.recorded() == ["POST register", "PUT preferences", "GET status"])
        let saved = fixture.defaults.data(forKey: "app.hashfleet.remotePush.settings")!
        let text = try #require(String(bytes: saved, encoding: .utf8))
        #expect(!text.contains(fixture.credentials.identity!.secret))
        #expect(!text.contains(String(repeating: "ab", count: 32)))
    }

    @Test func userScheduleChangesPersistAndInvalidIntervalsAreIgnored() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        await fixture.enroll(model)
        let id = fixture.device.id.uuidString.lowercased()
        model.updateSchedule(id: id, enabled: false, interval: 360)
        model.updateSchedule(id: id, interval: 1)
        await model.sync()
        #expect(model.settings.miners.first?.intervalMinutes == 360)
        #expect(model.settings.miners.first?.enabled == false)
        let restored = fixture.model()
        #expect(restored.settings.miners.first?.intervalMinutes == 360)
        #expect(restored.settings.miners.first?.enabled == false)
    }

    @Test func websiteOptOutIsAdoptedWithoutOverwritingItFromCachedSettings() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        await fixture.enroll(model)
        await fixture.transport.setEnabled(false)
        await model.sync()
        #expect(!model.settings.enabled)
        #expect(model.message == "Scheduled summaries are off.")
    }

    @Test func failedOptOutKeepsCredentialsForRetryAndStopsDeviceRemoteRegistration() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        await fixture.enroll(model)
        await fixture.transport.setFailure(true)
        await model.setEnabled(false)
        #expect(!model.settings.enabled)
        #expect(fixture.unregisterCount == 1)
        #expect(fixture.credentials.identity != nil)
        #expect(model.message.contains("may still apply"))
    }

    @Test func renamedCatalogCannotReenableAWebsiteOptOut() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        await fixture.enroll(model)
        await fixture.transport.setEnabled(false)
        fixture.device.name = "Renamed Gamma"
        model.updateFleet(devices: [fixture.device], snapshots: [:], isDemo: false)
        await model.sync()
        #expect(!model.settings.enabled)
        #expect((await fixture.transport.recorded()).filter { $0 == "PUT preferences" }.count == 1)
    }

    @Test func websiteRevocationNeverSilentlyRegistersAgainAndRequiresExplicitReset() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        await fixture.transport.setHealthyStatus()
        await fixture.enroll(model)
        #expect(model.providerReady)
        await fixture.transport.setAuthFailure(true)
        await model.sync()
        await model.resume()
        #expect(!model.settings.enabled && !model.isEnrolled && model.requiresReconnect)
        #expect(!model.providerReady)
        #expect(!FleetScheduledCheckStorage.load(defaults: fixture.configurationDefaults).enabled)
        #expect(fixture.credentials.identity != nil)
        #expect((await fixture.transport.recorded()).filter { $0 == "POST register" }.count == 1)
        await model.disconnect()
        #expect(fixture.credentials.identity == nil && !model.requiresReconnect)
        #expect(!model.providerReady)
        #expect(model.message.contains("could not be verified"))
    }

    @Test func initialConnectionFailureCanRetryWithoutLosingThePendingEnrollment() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        await fixture.transport.setFailure(true)
        await model.setEnabled(true)
        model.didRegister(deviceToken: Data(repeating: 0xab, count: 32))
        for _ in 0..<500 {
            if model.message.contains("may still apply") { break }
            await Task.yield()
        }
        #expect(fixture.credentials.identity != nil && !model.isEnrolled)
        await fixture.transport.setFailure(false)
        await model.sync()
        #expect(model.isEnrolled && model.settings.enabled && !model.requiresReconnect)
    }

    @Test func pendingPermissionCannotOverlapOrOverrideAnOptOut() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        fixture.holdPermission = true
        let model = fixture.model()
        let pending = Task { await model.setEnabled(true) }
        for _ in 0..<500 {
            if fixture.permissionWaiter != nil { break }
            await Task.yield()
        }
        #expect(fixture.permissionWaiter != nil)
        await model.setEnabled(true)
        await model.setEnabled(false)
        fixture.permissionWaiter?.resume(returning: true)
        fixture.permissionWaiter = nil
        await pending.value
        #expect(!model.settings.enabled && fixture.permissionCount == 1 && fixture.registerCount == 0)
    }

    @Test func editsDuringAnAwaitDoNotUploadAnOldSchedule() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        await fixture.enroll(model)
        await fixture.transport.suspendNextStatus()
        let pending = Task { await model.sync() }
        for _ in 0..<500 {
            if await fixture.transport.isWaiting() { break }
            await Task.yield()
        }
        #expect(await fixture.transport.isWaiting())
        model.updateSchedule(id: fixture.device.id.uuidString.lowercased(), interval: 720)
        await fixture.transport.releaseStatus()
        await pending.value
        for _ in 0..<500 {
            if !model.isWorking && model.settings.miners.first?.intervalMinutes == 720 {
                let saved = await fixture.transport.settings.miners.first?.intervalMinutes
                if saved == 720 { break }
            }
            await Task.yield()
        }
        #expect(await fixture.transport.settings.miners.first?.intervalMinutes == 720)
    }

    @Test func localNamesAreBoundedAndControlFreeAndSummariesNeverCelebrate() {
        #expect(FleetRemoteMinerSchedule.safeName("\n\t") == "Miner")
        #expect(FleetRemoteMinerSchedule.safeName("My\nGamma") == "MyGamma")
        #expect(FleetRemoteMinerSchedule.safeName(String(repeating: "💛", count: 100)).unicodeScalars.count == 64)
        #expect(!FleetNotificationDelegate.fullScreenCelebratedCategories.contains("app.hashfleet.summary"))
    }

    @Test func outboundRegistrationAndPreferencesContainOnlySchedulingMetadata() async throws {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        await fixture.enroll(model)
        let bodies = await fixture.transport.bodies
        #expect(bodies.count == 2)
        let registration = try #require(try JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any])
        #expect(Set(registration.keys) == ["mode", "device_token", "environment", "miners", "batch"])
        #expect(registration["batch"] as? Bool == true)
        #expect(registration["mode"] as? String == "device_check_v1")
        #expect((registration["miners"] as? [[String: String]]) == [["id": fixture.device.id.uuidString.lowercased()]])
        let preferences = try #require(try JSONSerialization.jsonObject(with: bodies[1]) as? [String: Any])
        #expect(Set(preferences.keys) == ["enabled", "miners"])
        let miner = try #require((preferences["miners"] as? [[String: Any]])?.first)
        #expect(Set(miner.keys) == ["id", "enabled", "interval_minutes"])
        for data in bodies {
            let text = try #require(String(bytes: data, encoding: .utf8))
            let excludedValues = [
                fixture.device.name, fixture.device.address, "private-password", "private-wallet",
                "hashRate", "temperature", "macAddr", "021122334455", fixture.credentials.identity!.secret
            ]
            for excluded in excludedValues {
                #expect(!text.contains(excluded))
            }
        }
        #expect(!(await fixture.transport.recorded()).contains("POST telemetry"))
        #expect(!(await fixture.transport.recorded()).contains("POST relay"))
        #expect(model.settings.miners.first?.name == fixture.device.name)
    }

    @Test func unpreparedTargetsCannotEnableScheduledLANChecks() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        fixture.device.address = "miner.local"
        let model = fixture.model()
        await model.setEnabled(true)
        #expect(!model.settings.enabled)
        #expect(model.message.contains("prepare"))
        #expect(fixture.permissionCount == 0 && fixture.registerCount == 0)
        #expect(await fixture.transport.recorded().isEmpty)
    }

    @Test func disconnectClearsOnlyTheCloudInstallation() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        fixture.defaults.set(false, forKey: FleetPreferences.Keys.sessionBestNotificationsEnabled)
        let model = fixture.model()
        await fixture.enroll(model)
        await model.disconnect()
        #expect(!model.isEnrolled && !model.settings.enabled)
        #expect(fixture.credentials.identity == nil)
        #expect(fixture.defaults.object(forKey: FleetPreferences.Keys.sessionBestNotificationsEnabled) as? Bool == false)
        #expect((await fixture.transport.recorded()).contains("DELETE register"))
    }

    @Test func catalogMergePreservesSchedulesDropsRemovedMinersAndNeverUploadsAddresses() throws {
        let device = MinerDevice(name: "Renamed", address: "192.168.1.12")
        let id = device.id.uuidString.lowercased()
        let old = FleetRemotePushSettings(enabled: true, miners: [
            .init(id: id, name: "Previous", enabled: false, intervalMinutes: 720),
            .init(id: UUID().uuidString.lowercased(), name: "Removed")])
        let merged = old.merging([device, MinerDevice(name: "CPU", address: "192.168.1.9", kind: .xmrig)])
        #expect(merged.miners == [.init(id: id, name: "Renamed", enabled: false, intervalMinutes: 720)])
        let text = try #require(String(bytes: try JSONEncoder().encode(merged.wirePreferences), encoding: .utf8))
        #expect(!text.contains("192.168") && !text.contains("address") && !text.contains("Renamed"))
    }

    @Test func onlySelectedMinimalTargetsEnterTheLocalExtensionStoreAndOptOutClearsThem() async throws {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        #expect(!FleetScheduledCheckStorage.load(defaults: fixture.configurationDefaults).enabled)
        await fixture.enroll(model)
        var config = FleetScheduledCheckStorage.load(defaults: fixture.configurationDefaults)
        #expect(config.enabled && config.targets.count == 1)
        let target = try #require(config.targets.first)
        #expect(target.id == fixture.device.id && target.baseURL.host == "192.168.1.50")
        #expect(target.expectedMAC == "021122334455")
        let text = try #require(String(bytes: try JSONEncoder().encode(config), encoding: .utf8))
        #expect(!text.contains("private-password") && !text.contains("private-wallet"))
        #expect(!text.contains(fixture.credentials.identity!.secret) && !text.contains("hashRate"))
        model.updateSchedule(id: fixture.device.id.uuidString.lowercased(), enabled: false)
        #expect(FleetScheduledCheckStorage.load(defaults: fixture.configurationDefaults).targets.isEmpty)
        model.updateSchedule(id: fixture.device.id.uuidString.lowercased(), enabled: true)
        await fixture.transport.setFailure(true)
        await model.setEnabled(false)
        config = FleetScheduledCheckStorage.load(defaults: fixture.configurationDefaults)
        #expect(!config.enabled && config.targets.isEmpty)
        #expect(fixture.unregisterCount > 0)
    }

    @Test func enteringDemoAndRemovingMinerClearLocalCheckTargetsWithoutCloudTraffic() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        await fixture.enroll(model)
        let before = await fixture.transport.recorded()
        model.updateFleet(devices: [fixture.device], snapshots: [:], isDemo: true)
        #expect(!FleetScheduledCheckStorage.load(defaults: fixture.configurationDefaults).enabled)
        #expect(await fixture.transport.recorded() == before)
        model.updateFleet(devices: [], snapshots: [:], isDemo: false)
        #expect(FleetScheduledCheckStorage.load(defaults: fixture.configurationDefaults).targets.isEmpty)
    }

    @Test func localNamesSurviveServerSchedulesThatIntentionallyContainNoNames() async {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let model = fixture.model()
        await fixture.enroll(model)
        await model.sync()
        #expect(model.settings.miners.first?.name == "Workshop Gamma")
        fixture.device.name = "Renamed locally"
        model.updateFleet(devices: [fixture.device], snapshots: [:], isDemo: false)
        #expect(model.settings.miners.first?.name == "Renamed locally")
    }

    @Test func clientRejectsInsecureOrCredentialBearingEndpointsBeforeNetwork() async {
        let identity = FleetRemotePushIdentity(id: UUID().uuidString.lowercased(), secret: "test-only")
        for url in ["http://hashfleet.app/api/v1.php", "https://user:pass@hashfleet.app/api/v1.php",
                    "https://hashfleet.app/api/v1.php?token=bad", "https://evil.example/api/v1.php",
                    "https://hashfleet.app/not-the-api"] {
            let client = FleetRemotePushClient(endpoint: URL(string: url)!)
            do {
                _ = try await client.send(action: "status", method: "GET", identity: identity, body: nil)
                Issue.record("Unsafe endpoint was accepted")
            } catch {}
        }
    }
}
