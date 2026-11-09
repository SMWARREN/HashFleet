import Foundation
import SwiftUI
import Testing
import HashFleetCore
@testable import HashFleet

@Suite(.serialized) @MainActor
struct MinerSettingsAccessTests {
    @Test func commonDraftBatchesOnlyChangedFields() throws {
        let original = MinerInfo(raw: [
            "hostname": .string("rig-one"),
            "statsFrequency": .integer(30),
            "autofanspeed": .integer(1),
            "temptarget": .integer(60)
        ])

        let review = try MinerSettingsReview(
            original: original,
            hostname: "rig-two",
            statsFrequency: 60,
            autoFan: true,
            temperatureTarget: "60"
        )

        let fields = try #require(review.payload.objectValue)
        #expect(fields["hostname"]?.stringValue == "rig-two")
        #expect(fields["statsFrequency"]?.intValue == 60)
        #expect(fields["autofanspeed"] == nil)
        #expect(fields["temptarget"] == nil)
        #expect(review.message.contains("Device name"))
        #expect(review.message.contains("On-device history"))
    }

    @Test func unrelatedChangeDoesNotRequireMissingTemperatureTarget() throws {
        let original = MinerInfo(raw: ["hostname": .string("rig-one")])
        let review = try MinerSettingsReview(
            original: original,
            hostname: "rig-two",
            statsFrequency: nil,
            autoFan: true,
            temperatureTarget: ""
        )
        #expect(review.payload.objectValue?.count == 1)
        #expect(review.payload.objectValue?["hostname"]?.stringValue == "rig-two")
    }

    @Test func invalidCommonDraftsFailBeforeReview() {
        let original = MinerInfo(raw: ["hostname": .string("rig-one")])
        #expect(throws: (any Error).self) {
            try MinerSettingsReview(
                original: original,
                hostname: "bad name",
                statsFrequency: nil,
                autoFan: true,
                temperatureTarget: ""
            )
        }
        #expect(throws: (any Error).self) {
            try MinerSettingsReview(
                original: original,
                hostname: "rig-one",
                statsFrequency: nil,
                autoFan: true,
                temperatureTarget: "90"
            )
        }
    }

    @Test func changeSummaryShowsReportedBeforeAndProposedAfterWithoutChangingPayload() throws {
        let original = MinerInfo(raw: [
            "hostname": .string("rig-before"),
            "statsFrequency": .integer(30),
            "autofanspeed": .integer(1),
            "temptarget": .integer(60)
        ])
        let review = try MinerSettingsReview(
            original: original,
            hostname: "rig-after",
            statsFrequency: 60,
            autoFan: true,
            temperatureTarget: "58"
        )
        #expect(review.changes.map(\.key) == ["hostname", "statsFrequency", "temptarget"])
        #expect(review.changes[0].previousValue == "rig-before")
        #expect(review.changes[0].value == "rig-after")
        #expect(review.changes[1].previousValue == MinerTuningDraft.statsFrequencyLabel(30))
        #expect(review.changes[2].previousValue == "60 °C")
        #expect(review.changes[2].value == "58 °C")
        #expect(review.message.contains("rig-before → rig-after"))
        #expect(review.message.contains("Nothing is sent while you edit"))
        #expect(review.payload.objectValue?.count == 3)
        #expect(review.payload.objectValue?["autofanspeed"] == nil)
        #expect(review.payload.objectValue?["frequency"] == nil)
        #expect(review.payload.objectValue?["coreVoltage"] == nil)
    }

    @Test func missingPreviousValuesAreNotInventedInSettingsReview() throws {
        let review = try MinerSettingsReview(
            original: MinerInfo(raw: [:]),
            hostname: "rig-new",
            statsFrequency: nil,
            autoFan: true,
            temperatureTarget: ""
        )
        #expect(review.changes.count == 1)
        #expect(review.changes[0].previousValue == "Not reported")
        #expect(review.changes[0].value == "rig-new")
        #expect(review.payload.objectValue?.count == 1)
    }

    @Test func changingAutomaticFanShowsItsReportedStateWithoutInventingManualSpeed() throws {
        let review = try MinerSettingsReview(
            original: MinerInfo(raw: ["hostname": .string("rig-one"), "autofanspeed": .integer(0)]),
            hostname: "rig-one",
            statsFrequency: nil,
            autoFan: true,
            temperatureTarget: ""
        )
        #expect(review.changes.count == 1)
        #expect(review.changes[0].previousValue == "Off")
        #expect(review.changes[0].value == "On")
        #expect(review.payload.objectValue?["autofanspeed"]?.intValue == 1)
        #expect(review.payload.objectValue?["manualFanSpeed"] == nil)
        #expect(review.payload.objectValue?["minFanSpeed"] == nil)
    }

    @Test func sharedControlCardDefersLargeContentUntilBodyEvaluation() {
        var evaluations = 0
        let card = MinerControlsCard {
            evaluations += 1
            return Text("Deferred settings fixture")
        }
        #expect(evaluations == 0, "Building a card must not eagerly copy its entire settings page")
        _ = card.body
        #expect(evaluations == 1)
    }

    @Test func everySettingsCategoryIsDirectlyReachable() throws {
        let suite = "UnifiedTuningCategories.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        let device = MinerDevice(name: "Category fixture", address: "fixture.test")
        let view = MinerSettingsView(device: device, store: store)

        for category in MinerSettingsCategory.allCases {
            #expect(type(of: view.categoryDestination(category)) == AnyView.self)
        }
    }

    @Test func snapshotFreshnessStillLocksSettingsIndependentlyOfPresentation() throws {
        let suite = "UnifiedSettingsFreshness.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        let device = MinerDevice(name: "Freshness fixture", address: "fixture.test")
        let view = MinerSettingsView(device: device, store: store)
        #expect(view.offlineReadOnly)

        var snapshot = MinerSnapshot(info: MinerInfo(raw: ["hostname": .string("fixture")]), updatedAt: Date())
        store.snapshots[device.id] = snapshot
        #expect(!view.offlineReadOnly)
        snapshot.isCached = true
        store.snapshots[device.id] = snapshot
        #expect(view.offlineReadOnly)
        snapshot.isCached = false
        snapshot.isReconnecting = true
        store.snapshots[device.id] = snapshot
        #expect(view.offlineReadOnly)
    }
}

@Suite("Miner browser links")
struct FleetBrowserURLTests {
    @Test func hostOnlyMinerAddressUsesHTTPByDefault() throws {
        let destination = try #require(FleetBrowserURL.destination(for: "192.168.1.42", defaultScheme: "http"))
        #expect(destination.scheme == "http")
        #expect(destination.host == "192.168.1.42")
        #expect(destination.path.isEmpty)
    }

    @Test func explicitSecureAddressAndUnsafeSchemesAreHandledSafely() throws {
        let secure = try #require(
            FleetBrowserURL.destination(for: "https://miner.local/status", defaultScheme: "http")
        )
        #expect(secure.scheme == "https")
        #expect(secure.path == "/status")
        #expect(FleetBrowserURL.destination(for: "javascript:alert(1)", defaultScheme: "http") == nil)
    }
}
