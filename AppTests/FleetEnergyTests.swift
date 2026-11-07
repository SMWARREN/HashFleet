import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Electricity estimates")
@MainActor
struct FleetEnergyTests {
    @Test func constantLoadMathAndUnknownZeroStayDistinct() throws {
        let estimate = FleetEnergyEstimate(watts: 1000, reportingCount: 1, deviceCount: 1, isDemo: false)
        #expect(estimate.dailyKWh == 24)
        #expect(abs(try #require(estimate.dailyCost(rate: 0.15)) - 3.6) < 0.000001)
        #expect(abs(try #require(estimate.monthlyCost(rate: 0.15)) - 108) < 0.000001)
        #expect(estimate.dailyCost(rate: nil) == nil)
        #expect(estimate.dailyCost(rate: -1) == nil)
        #expect(estimate.dailyCost(rate: .infinity) == nil)
        #expect(FleetEnergyEstimate(watts: nil, reportingCount: 0, deviceCount: 2, isDemo: false).dailyKWh == nil)
        #expect(FleetEnergyEstimate(watts: 0, reportingCount: 1, deviceCount: 2, isDemo: false).dailyKWh == 0)
        #expect(FleetEnergyEstimate(watts: .greatestFiniteMagnitude, reportingCount: 1, deviceCount: 1, isDemo: false).dailyKWh == nil)
    }

    @Test(arguments: ["", "NaN", "inf", "-1", "10001", "1e3", "1,000.25", "1.2junk", ".", "1.2.3"])
    func invalidRateFailsWithoutCoercion(_ value: String) {
        #expect(throws: FleetEnergySettings.ValidationError.self) {
            try FleetEnergySettings.parseRate(value, locale: Locale(identifier: "en_US"))
        }
    }

    @Test func localizedDecimalAndZeroRateAreValid() throws {
        #expect(try FleetEnergySettings.parseRate(" 0,15 ", locale: Locale(identifier: "de_DE")) == 0.15)
        #expect(try FleetEnergySettings.parseRate("0.15", locale: Locale(identifier: "en_US")) == 0.15)
        #expect(try FleetEnergySettings.parseRate("0", locale: Locale(identifier: "en_US")) == 0)
    }

    @Test func groupingCannotBecomeADifferentTariff() {
        for input in ["1.000", "1.234", "1.000,25"] {
            #expect(throws: FleetEnergySettings.ValidationError.self) {
                try FleetEnergySettings.parseRate(input, locale: Locale(identifier: "de_DE"))
            }
        }
    }

    @Test func editingRoundTripsSmallAndPreciseTariffsAcrossLocales() throws {
        for identifier in ["en_US", "de_DE", "ar_EG"] {
            let locale = Locale(identifier: identifier)
            for value in [0.0, 0.0000004, 0.1234567, 0.12345678901234567, 10000.0] {
                let text = FleetEnergySettings.editableRate(value, locale: locale)
                #expect(try FleetEnergySettings.parseRate(text, locale: locale) == value)
            }
        }
    }

    @Test func settingsPersistOnlyAfterValidExplicitSave() throws {
        let suite = "app.hashfleet.energy-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = FleetEnergySettings(defaults: defaults)
        #expect(settings.rate == nil)
        try settings.save(rateText: "0.25", currency: "GBP", locale: Locale(identifier: "en_US"))
        #expect(throws: FleetEnergySettings.ValidationError.self) {
            try settings.save(rateText: "2junk", currency: "USD")
        }
        let reloaded = FleetEnergySettings(defaults: defaults)
        #expect(reloaded.rate == 0.25 && reloaded.currency == "GBP")
        #expect(!FleetPreferences(defaults: defaults).blockNotificationsEnabled)
    }

    @Test func staleOfflineCachedFutureAndMissingPowerAreExcluded() throws {
        let suite = "app.hashfleet.energy-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        let now = Date()
        for index in 0..<7 {
            let device = MinerDevice(name: "Miner", address: "192.168.1.\(index + 10)")
            store.devices.append(device)
            var snapshot = MinerSnapshot(info: MinerInfo(raw: ["power": .number(100)]), updatedAt: now)
            switch index {
            case 1: snapshot.updatedAt = now.addingTimeInterval(-121)
            case 2: snapshot.error = "Offline"
            case 3: snapshot.isCached = true
            case 4: snapshot.updatedAt = now.addingTimeInterval(1)
            case 5: snapshot.info = MinerInfo(raw: [:])
            case 6: snapshot.info = MinerInfo(raw: ["power": .number(0)])
            default: break
            }
            store.snapshots[device.id] = snapshot
        }
        let result = FleetEnergyEstimate.capture(store: store, at: now)
        #expect(result.watts == 100)
        #expect(result.reportingCount == 2 && result.deviceCount == 7)
    }

    @Test func partialSocketFrameDoesNotFreshenOldPower() throws {
        let suite = "app.hashfleet.energy-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        try store.add(name: "Desk", address: "192.168.1.10")
        let device = try #require(store.devices.first)
        store.recordSuccessfulInfo(MinerInfo(raw: ["power": .number(100)]), for: device.id,
            at: Date().addingTimeInterval(-180))
        #expect(store.applyLiveMessage(.text(#"{"data":{"hashRate":1250}}"#), for: device.id))
        #expect(FleetEnergyEstimate.capture(store: store).watts == nil)
        #expect(store.applyLiveMessage(.text(#"{"data":{"power":105}}"#), for: device.id))
        #expect(FleetEnergyEstimate.capture(store: store).watts == 105)
    }
}
