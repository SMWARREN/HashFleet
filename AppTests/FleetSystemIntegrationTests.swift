import AppIntents
import Foundation
import Testing
@testable import HashFleet

@Suite(.serialized)
struct FleetSystemIntegrationTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func spokenSummaryRequiresLocalDeviceAuthentication() {
        #expect(GetLastSavedFleetSummaryIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
    }

    @Test func appDeclaresBaseLocaleForSiriPhraseTraining() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDevelopmentRegion") as? String == "en")
    }

    @Test func pendingOpenIsConsumedExactlyOnceWithoutChangingOtherPreferences() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: FleetSystemIntegration.widgetSharingKey)
        #expect(!FleetSystemNavigation.consume(defaults: defaults))
        FleetSystemNavigation.request(defaults: defaults)
        #expect(FleetSystemNavigation.consume(defaults: defaults))
        #expect(!FleetSystemNavigation.consume(defaults: defaults))
        #expect(!defaults.bool(forKey: FleetSystemIntegration.widgetSharingKey))
        #expect(defaults.persistentDomain(forName: suite)?.count == 1)
    }

    private func defaults() throws -> (UserDefaults, String) {
        let suite = "app.hashfleet.fleet-system-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    private func glance(
        updatedAt: Date? = nil,
        onlineCount: Int = 2,
        minerCount: Int = 3,
        hashrateGHs: Double = 2_400.5,
        powerWatts: Double = 38.25,
        isDemo: Bool = false
    ) -> FleetGlance {
        FleetGlance(
            updatedAt: updatedAt ?? now,
            onlineCount: onlineCount,
            minerCount: minerCount,
            hashrateGHs: hashrateGHs,
            powerWatts: powerWatts,
            isDemo: isDemo
        )
    }

    @Test func summaryRequiresExplicitWidgetSharingOptInAndDoesNotInvokeLoader() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var loaded = false
        let expected = glance()
        let reader = FleetSystemSummaryReader(defaults: defaults) {
            loaded = true
            return expected
        }

        let summary = reader.summary(now: now)

        #expect(summary.contains("sharing is off"))
        #expect(!loaded)
        #expect(defaults.persistentDomain(forName: suite)?.isEmpty != false)
    }

    @Test func optedInReaderUsesOnlyInjectedAggregateAndDoesNotWrite() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: FleetSystemIntegration.widgetSharingKey)
        let beforeKeyCount = defaults.persistentDomain(forName: suite)?.count ?? 0
        let expected = glance()

        let summary = FleetSystemSummaryReader(defaults: defaults) { expected }.summary(now: now)

        #expect(summary.contains("Last saved fleet"))
        #expect(summary.contains("2 of 3 online"))
        #expect(summary.contains("2.40 TH/s"))
        #expect(summary.contains("38.2 watts"))
        let afterKeyCount = defaults.persistentDomain(forName: suite)?.count ?? 0
        #expect(afterKeyCount == beforeKeyCount)
        #expect(!summary.contains("192.168.1.20"))
        #expect(!summary.contains("wallet"))
        #expect(!summary.contains("secret"))
    }

    @Test func zeroMinerAggregateIsHonest() {
        let summary = FleetSystemSummaryFormatter.format(
            glance(updatedAt: now, onlineCount: 0, minerCount: 0, hashrateGHs: 0, powerWatts: 0),
            now: now
        )

        #expect(summary.contains("No miners"))
        #expect(!summary.contains("0 GH/s"))
        #expect(!summary.contains("online"))
    }

    @Test func zeroReadingWithConfiguredMinersRemainsARealZero() {
        let summary = FleetSystemSummaryFormatter.format(
            glance(updatedAt: now, onlineCount: 0, minerCount: 2, hashrateGHs: 0, powerWatts: 0),
            now: now
        )

        #expect(summary.contains("0 GH/s"))
        #expect(summary.contains("0.0 watts"))
        #expect(summary.contains("0 of 2 online"))
    }

    @Test func invalidAggregateNeverExposesMetrics() {
        let invalid = glance(onlineCount: 4, minerCount: 3, hashrateGHs: .nan)
        let summary = FleetSystemSummaryFormatter.format(invalid, now: now)

        #expect(summary.contains("invalid"))
        #expect(!summary.contains("nan"))
        #expect(!summary.contains("TH/s"))
        #expect(!summary.contains("watts"))
    }

    @Test func staleAggregateUsesLastSavedAndHonestCurrentReadingLanguage() {
        let stale = glance(updatedAt: now.addingTimeInterval(-FleetGlance.freshnessInterval - 1))
        let summary = FleetSystemSummaryFormatter.format(stale, now: now)

        #expect(summary.contains("Last saved fleet"))
        #expect(summary.contains("Saved"))
        #expect(summary.contains("stale"))
        #expect(summary.contains("open Hash Fleet for a current reading"))
        #expect(!summary.contains("refreshing"))
    }

    @Test func demoAggregateIsExplicitlyLabeledAsSampleData() {
        let summary = FleetSystemSummaryFormatter.format(glance(isDemo: true), now: now)

        #expect(summary.contains("Demo sample data"))
        #expect(summary.contains("no hardware connection"))
        #expect(summary.contains("Last saved fleet"))
    }

    @Test func timestampIsIncludedWithoutAddingPrivateIdentity() {
        let summary = FleetSystemSummaryFormatter.format(glance(updatedAt: now), now: now)

        #expect(summary.contains("Saved"))
        #expect(!summary.contains("miner-"))
        #expect(!summary.contains("address"))
        #expect(!summary.contains("wallet"))
    }

    @Test func sidebarDestinationRestorationIDsRoundtrip() {
        let destinations: [FleetSidebarDestination] = [
            .overview,
            .network,
            .energy,
            .achievements,
            .reports,
            .backup,
            .monitoring,
            .preferences,
            .about,
            .support
        ]
        for dest in destinations {
            let id = dest.id
            let restored = FleetSidebarDestination(restorationID: id)
            #expect(restored == dest)
        }

        let minerID = UUID()
        let minerDest = FleetSidebarDestination.miner(minerID)
        let restoredMiner = FleetSidebarDestination(restorationID: minerDest.id)
        #expect(restoredMiner == minerDest)

        #expect(FleetSidebarDestination(restorationID: "unknown_destination") == nil)
        #expect(FleetSidebarDestination(restorationID: "miner-not-a-uuid") == nil)
    }

    @Test func appShortcutsDeclareOrangeTileColorAndExpectedIntentShortTitles() {
        #expect(FleetSystemShortcuts.shortcutTileColor == .orange)
        let shortcuts = FleetSystemShortcuts.appShortcuts
        #expect(shortcuts.count == 5)
    }

    @Test func hardwareIntentsRequireLocalAuthenticationAndDoNotOpenApp() {
        #expect(RestartFleetMinerIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
        #expect(!RestartFleetMinerIntent.openAppWhenRun)
        #expect(SetFleetMinerFrequencyIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
        #expect(!SetFleetMinerFrequencyIntent.openAppWhenRun)
        #expect(SetFleetMinerFanSpeedIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
        #expect(!SetFleetMinerFanSpeedIntent.openAppWhenRun)
    }

    @Test func controlActionsProvideDescriptiveMetadataAndRiskWarnings() {
        let restart = FleetMinerControlAction.restart
        #expect(restart.actionName == "Restart")
        #expect(restart.valueDescription == "Immediate reboot")
        #expect(restart.riskDescription.contains("Rebooting will temporarily halt mining"))

        let freq = FleetMinerControlAction.setFrequency(525)
        #expect(freq.actionName == "Set Frequency")
        #expect(freq.valueDescription == "525.0 MHz")
        #expect(freq.riskDescription.contains("firmware encoding limit"))

        let fan = FleetMinerControlAction.setFanSpeed(80)
        #expect(fan.actionName == "Set Fan Speed")
        #expect(fan.valueDescription == "80% (Manual mode)")
        #expect(fan.riskDescription.contains("autofanspeed = 0"))
    }

    @Test func controlErrorsProvideDescriptiveMessages() {
        let notFound = FleetMinerControlError.deviceNotFound("xyz")
        #expect(notFound.errorDescription?.contains("xyz") == true)

        let invalidAddr = FleetMinerControlError.invalidAddress("bad.url")
        #expect(invalidAddr.errorDescription?.contains("bad.url") == true)

        let demo = FleetMinerControlError.demoModeReadOnly
        #expect(demo.errorDescription?.contains("demo mode") == true)

        let invalidParam = FleetMinerControlError.invalidParameter("Out of range")
        #expect(invalidParam.errorDescription == "Out of range")

        let preflight = FleetMinerControlError.preflightFailed("Offline")
        #expect(preflight.errorDescription?.contains("Offline") == true)

        let stale = FleetMinerControlError.staleDevice("Timed out")
        #expect(stale.errorDescription?.contains("Timed out") == true)

        let write = FleetMinerControlError.writeFailed("500 Internal Error")
        #expect(write.errorDescription?.contains("500 Internal Error") == true)
    }

    @Test func minerEntityDisplayRepresentationProvidesNameAndAddress() {
        let entity = FleetMinerEntity(id: "test-id", name: "Desk BM1370", address: "192.168.1.100")
        #expect(entity.id == "test-id")
        #expect(entity.name == "Desk BM1370")
        #expect(entity.address == "192.168.1.100")
        #expect(String(describing: entity.displayRepresentation.title).contains("Desk BM1370"))
        #expect(String(describing: entity.displayRepresentation.subtitle).contains("192.168.1.100"))
    }
}
