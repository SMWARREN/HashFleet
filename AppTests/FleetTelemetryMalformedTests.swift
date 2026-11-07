import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

extension FleetTelemetryCompletenessTests {
    // MARK: - Negative and malformed metrics

    @Test func negativeMetricsAreRejectedRatherThanSubtracted() async throws {
        // Audited ESP-Miner thermal.c returns -1 for an uninitialized sensor, and a negative power
        // or hashrate is never physical. Such a value must not silently reduce a fleet total.
        let completenessEnv = try await store([
            complete(hashrate: 1_000, power: 20),
            ["hostname": .string("uninitialized"), "hashRate": .number(-1), "power": .number(-1)]
        ])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.totalHashrate == 1_000, "The -1 placeholder is excluded, not subtracted")
        #expect(store.totalPower == 20)
        #expect(store.hashrateReading.reporting == 1)
        #expect(store.hashrateReading.online == 2)
        #expect(store.hashrateReading.isPartial)
        #expect(store.efficiencyReading.reporting == 1)
        #expect(store.efficiencyReading.value == nil, "Pair coverage is incomplete, so no figure is shown")
        #expect(store.glance == .empty)
    }

    @Test func numericStringsAreAcceptedExactlyAsTheCardsAndHistoryAcceptThem() async throws {
        // JSONValue.doubleValue and FleetFormat.sensor both parse finite numeric strings from older
        // or custom firmware. Totals must agree, or a card would show a value the fleet total denies.
        let completenessEnv = try await store([
            ["hostname": .string("stringy"), "hashRate": .string("1200.5"), "power": .string("19")]
        ])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.totalHashrate == 1200.5)
        #expect(store.totalPower == 19)
        #expect(store.hashrateReading.isComplete)
        #expect(store.efficiencyReading.hasReading)
    }

    @Test func nonFiniteAndWrongTypedMetricsAreNotCounted() async throws {
        let invalid = FleetTotals(snapshots: [
            MinerSnapshot(
                info: MinerInfo(raw: [
                    "hashRate": .number(.nan), "power": .number(.infinity)
        ])
            )
        ])
        #expect(!invalid.hashrate.hasReading)
        #expect(!invalid.power.hasReading)
        #expect(!invalid.isPublishable)
        let completenessEnv = try await store([
            ["hostname": .string("typed"), "hashRate": .bool(true), "power": .bool(true)],
            ["hostname": .string("garbage"), "hashRate": .string("fast"), "power": .null]
        ])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.onlineCount == 2)
        #expect(!store.hashrateReading.hasReading, "Booleans, null and non-numeric strings are not metrics")
        #expect(!store.powerReading.hasReading)
        #expect(store.totalHashrate == 0)
        #expect(store.efficiencyReading.value == nil)
        #expect(store.glance == .empty)
    }

    @Test func lowercaseHashrateKeyIsAcceptedForOlderFirmware() async throws {
        let completenessEnv = try await store([
            ["hostname": .string("legacy"), "hashrate": .integer(750), "power": .integer(11)]
        ])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.totalHashrate == 750)
        #expect(store.totalPower == 11)
        #expect(store.hashrateReading.isComplete)
    }

    @Test func preferredKeyWinsAndAnUnusablePreferredValueIsNotBackfilled() async throws {
        // `hashRate` is the audited field. When it is present but unusable, silently falling back to
        // a different key would report a number the firmware did not offer for that field.
        let completenessEnv = try await store([
            ["hostname": .string("conflict"), "hashRate": .number(-5), "hashrate": .number(999)]
        ])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!store.hashrateReading.hasReading)
        #expect(store.totalHashrate == 0)
    }

    @Test func whitespaceAndEmptyStringMetricsDoNotBecomeReadings() async throws {
        let completenessEnv = try await store([
            ["hostname": .string("empty_fields"), "hashRate": .string(""), "power": .string("   ")],
            ["hostname": .string("hex_and_alpha"), "hashRate": .string("not-a-number"), "power": .string("N/A")]
        ])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.onlineCount == 2)
        #expect(!store.hashrateReading.hasReading)
        #expect(!store.powerReading.hasReading)
        #expect(store.totalHashrate == 0)
        #expect(store.totalPower == 0)
        #expect(store.efficiencyReading.value == nil)
        #expect(store.glance == .empty)
    }

    @Test func complexObjectAndArrayTelemetryValuesAreRejected() async throws {
        let completenessEnv = try await store([
            [
                "hostname": .string("nested"),
                "hashRate": .array([.number(500)]),
                "power": .object(["watts": .number(15)])
            ]
        ])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.onlineCount == 1)
        #expect(!store.hashrateReading.hasReading)
        #expect(!store.powerReading.hasReading)
        #expect(store.totalHashrate == 0)
        #expect(store.totalPower == 0)
    }

    // MARK: - Demo remains coherent

    @Test func demoFleetReportsCompleteCoverage() async throws {
        let suite = "app.hashfleet.completeness.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        store.loadDemo()
        #expect(store.onlineCount == 3)
        #expect(store.hashrateReading.isComplete)
        #expect(store.powerReading.isComplete)
        #expect(abs(store.totalHashrate - 3_020) < 0.001)
        #expect(store.efficiencyReading.hasReading)
        #expect(store.glance.isDemo)
        #expect(store.glance.hashrateGHs > 0)
    }
}
