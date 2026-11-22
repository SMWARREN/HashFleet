import Foundation
import SwiftUI
import Testing
import HashFleetCore
@testable import HashFleet

@Suite
@MainActor
struct MinerNumberFirstAvailabilityTests {
    private var reported: [String: JSONValue] {
        ["hostname": .string("fixture"), "version": .string("v0.0.1"),
         "autofanspeed": .bool(true), "temptarget": .integer(62),
         "frequency": .integer(500), "coreVoltage": .integer(1050)]
    }

    private func availability(
        _ fields: [String: JSONValue], info: MinerProbeStatus = .supported,
        settings: MinerProbeStatus = .supported, firmware: MinerProbeStatus = .supported,
        actions: [MinerDetailQuickAction: MinerProbeStatus] = [:]
    ) -> MinerNumberFirstAvailability {
        .init(info: .init(raw: fields), infoStatus: info, settingsStatus: settings, firmwareStatus: firmware,
              actionStatuses: actions)
    }

    @Test func onlyIndividuallySupportedActionsAppearInOriginalOrder() {
        let mixed: [MinerDetailQuickAction: MinerProbeStatus] = [
            .restart: .supported, .identify: .supported, .pause: .failed(message: "HTTP 403"),
            .resume: .unsupported(statusCode: 405)
        ]
        #expect(availability(reported).quickActions.isEmpty)
        #expect(availability(reported, settings: .notChecked, actions: mixed).quickActions == [.identify, .restart])
        #expect(availability(reported, info: .notChecked, actions: mixed).quickActions.isEmpty)
        #expect(availability(["error": .string("invalid")], actions: mixed).quickActions.isEmpty)
    }

    @Test func eachSurfaceRequiresItsOwnEvidence() {
        let sample = NumberFirstPreview.minerFirmwareNotice
        let supported = availability(reported)
        #expect(supported.cooling && supported.tuning && supported.rawAPI)
        #expect(supported.firmwareUpdate(sample)?.latestVersion == "v0.0.2")

        for unknownOrDenied: MinerProbeStatus in [.notChecked, .failed(message: "HTTP 403"), .unsupported(statusCode: 405)] {
            let readOnly = availability(reported, settings: unknownOrDenied, firmware: unknownOrDenied)
            #expect(readOnly.rawAPI)
            #expect(!readOnly.cooling && !readOnly.tuning && readOnly.firmwareUpdate(sample) == nil)

            let noInfo = availability(reported, info: unknownOrDenied)
            #expect(!noInfo.rawAPI && !noInfo.cooling && !noInfo.tuning && noInfo.firmwareUpdate(sample) == nil)
        }

        let noFirmware = availability(reported, firmware: .notChecked)
        #expect(noFirmware.cooling && noFirmware.tuning && noFirmware.firmwareUpdate(sample) == nil)
        #expect(!availability(["error": .string("unauthorized")]).rawAPI)
    }

    @Test func settingsRequireValidReportedConfiguration() {
        var fields = reported
        fields["temptarget"] = nil
        fields["fanrpm"] = .integer(3100)
        #expect(!availability(fields).cooling && availability(fields).tuning)
        fields["autofanspeed"] = .bool(false)
        fields["manualFanSpeed"] = .integer(0)
        #expect(availability(fields).cooling)
        fields["frequency"] = nil
        fields["actualFrequency"] = .integer(500)
        #expect(availability(fields).cooling && !availability(fields).tuning)

        for invalid: JSONValue in [.integer(-1), .integer(101), .string("unknown")] {
            fields["manualFanSpeed"] = invalid
            #expect(!availability(fields).cooling)
        }
        fields = reported
        fields["coreVoltage"] = .integer(0)
        #expect(!availability(fields).tuning && availability(fields).cooling)
    }

    @Test func firmwareExampleNeedsAMatchingCurrentVersionAndNewerRelease() {
        let supported = availability(reported)
        #expect(supported.firmwareUpdate(nil) == nil)
        for (current, latest, failed) in [
            ("v0.0.0", "v0.0.2", false), ("v0.0.1", "v0.0.1", false), ("v0.0.1", "v0.0.2", true)
        ] {
            let notice = FirmwareUpdateNotice(currentVersion: current,
                releases: [FirmwareRelease(version: latest, url: nil)], checkedAt: .now, checkFailed: failed)
            #expect(supported.firmwareUpdate(notice) == nil)
        }
    }

    @Test func settingsHubPreservesOrderAndRequiresCategoryEvidence() {
        var fields = reported.merging([
            "statsFrequency": .integer(30), "rotation": .integer(90),
            "displayTimeout": .integer(-1), "invertscreen": .integer(0),
            "stratumURL": .string("pool.example"), "fallbackStratumURL": .string("backup.example"),
            "primaryPoolIndex": .integer(0), "secondaryPoolIndex": .integer(1),
            "pools": .array([.object(["stratumURL": .string("pool.example")])])
        ]) { _, new in new }
        let example = availability(fields)
        #expect(example.settingsCategories() == [.general, .pools, .display, .cooling, .tuning])
        #expect(example.showsSettingsHub(in: .essentials))
        #expect(example.showsSettingsHub(in: .full))

        fields["displayTimeout"] = .number(1.5)
        fields["statsFrequency"] = .integer(-1)
        fields["pools"] = .array([])
        #expect(availability(fields).settingsCategories() == [.cooling, .tuning])
    }

    @Test func essentialsCanShowReportedPoolRolesWithoutAdvancedAliasesOrAnAssignedFallback() {
        let modern: [String: JSONValue] = [
            "primaryPoolIndex": .integer(5), "secondaryPoolIndex": .integer(-1),
            "pools": .array([.object(["id": .integer(5), "stratumURL": .string("pool.example")])])
        ]
        let legacy: [String: JSONValue] = ["stratumURL": .string("pool.example")]
        for shape in [modern, legacy] {
            let fields = reported.merging(shape) { _, new in new }
            let example = availability(fields)
            #expect(example.settingsCategories(usesEssentialsPools: true).contains(.pools))
            #expect(!example.settingsCategories().contains(.pools))
            #expect(!availability(fields, settings: .unsupported(statusCode: 405))
                .settingsCategories(usesEssentialsPools: true).contains(.pools))
        }
    }

    @Test func settingsHubKeepsIndependentReadOnlyTools() {
        let denied = availability(reported, settings: .failed(message: "HTTP 403"), firmware: .notChecked)
        #expect(denied.settingsCategories().isEmpty)
        #expect(!denied.showsSettingsHub(in: .essentials))
        #expect(denied.showsSettingsHub(in: .full))
        #expect(denied.firmwareUpdate(NumberFirstPreview.minerFirmwareNotice) == nil)
        #expect(!availability(reported, info: .notChecked).showsSettingsHub(in: .full))
    }
}

@Suite
@MainActor
struct MinerTuningPreviewTests {
    private let configured: [String: JSONValue] = ["frequency": .integer(525), "coreVoltage": .integer(1150)]

    @Test func aDraftDoesNotChangeConfiguredOrMeasuredValues() throws {
        let info = MinerInfo(raw: configured.merging([
            "actualFrequency": .integer(521), "coreVoltageActual": .integer(1128),
            "hashRate": .integer(638), "temp": .integer(59)
        ]) { _, new in new })
        let readings = MinerTuningPreviewReadings(info: info)
        var draft = MinerTuningPreviewDraft(info: info)
        #expect(draft.review == nil)
        draft.edit(.frequency, String(Int(try #require(draft.next(.frequency, direction: 1)))))
        let review = try #require(draft.review)
        #expect(review.changes == [.init(field: .frequency, old: 525, new: 526)])
        #expect(review.payload == .object(["frequency": .number(526)]))
        #expect(review == draft.review)
        #expect(draft.configured[.frequency] == 525 && draft.configured[.coreVoltage] == 1150)
        #expect(readings.clock == 521 && readings.voltage == 1128)
        #expect(readings.hashrate == 638 && readings.temperature == 59)
        draft.reset()
        #expect(draft.value(for: .frequency) == 525 && draft.review == nil)
    }

    @Test func absentAndMalformedFieldsNeverBorrowFromOtherReadings() {
        let readings = MinerTuningPreviewReadings(info: .init(raw: configured))
        #expect(readings.clock == nil && readings.voltage == nil)
        #expect(readings.hashrate == nil && readings.temperature == nil)
        var draft = MinerTuningPreviewDraft(info: .init(raw: [
            "coreVoltage": .number(1150.5), "actualFrequency": .integer(521), "coreVoltageActual": .integer(1128)
        ]))
        #expect(draft.fields.isEmpty)
        draft.edit(.frequency, "526")
        #expect(draft.review == nil && draft.text.isEmpty)
        draft = .init(info: .init(raw: ["frequency": .integer(525)]))
        #expect(draft.fields == [.frequency])
        #expect(draft.next(.coreVoltage, direction: 1) == nil)
    }

    @Test func onlyExactValidChangesCanBeReviewed() throws {
        var draft = MinerTuningPreviewDraft(info: .init(raw: configured))
        for entry in ["", "0525.0", "526.", "65536"] {
            draft.edit(.frequency, entry)
            #expect(draft.review == nil)
        }
        draft.edit(.frequency, "526.5")
        let firstReview = try #require(draft.review)
        draft.edit(.coreVoltage, "1155.5")
        #expect(draft.review == nil)
        draft.edit(.coreVoltage, "1155")
        #expect(draft.review != firstReview)
        #expect(draft.review?.payload == .object(["frequency": .number(526.5), "coreVoltage": .integer(1155)]))
    }

    @Test func adjustmentStopsAtValidatorBounds() {
        var draft = MinerTuningPreviewDraft(info: .init(raw: ["frequency": .integer(1), "coreVoltage": .integer(65_535)]))
        #expect(draft.next(.frequency, direction: -1) == nil)
        #expect(draft.next(.frequency, direction: 1) == 2)
        #expect(draft.next(.coreVoltage, direction: 1) == nil)
        #expect(draft.next(.coreVoltage, direction: -1) == 65_530)
        draft.edit(.coreVoltage, "0")
        #expect(draft.review == nil)
    }
}

@Suite
@MainActor
struct MinerCoolingPreviewDraftTests {
    private var configured: [String: JSONValue] {
        ["autofanspeed": .integer(1), "temptarget": .integer(55),
         "manualFanSpeed": .integer(60), "minFanSpeed": .integer(25),
         "fanspeed": .integer(65), "fanrpm": .integer(4_600), "overheat_mode": .integer(0)]
    }

    @Test func changesIncludeOnlyEditedActiveSettings() {
        let original = MinerCoolingPreviewDraft(info: .init(raw: configured))
        var draft = original
        #expect(draft.changes(from: original).isEmpty)
        draft.adjust(.target, increasing: true)
        draft.adjust(.manual, increasing: true)
        #expect(draft[.manual] == 60)
        #expect(draft.changes(from: original) == ["temptarget": .integer(56)])
        draft.adjust(.minimum, increasing: false)
        #expect(draft.changes(from: original) == ["temptarget": .integer(56), "minFanSpeed": .integer(24)])
        let applied = original.applying(draft.changes(from: original))
        #expect(applied == draft)
        #expect(draft.changes(from: applied).isEmpty)
    }

    @Test func changingModeUsesTheConfiguredSpeedNotTheReading() {
        let original = MinerCoolingPreviewDraft(info: .init(raw: configured))
        var draft = original
        draft.adjust(.minimum, increasing: true)
        draft.select(automatic: false)
        let changes = draft.changes(from: original)
        #expect(changes == ["autofanspeed": .integer(0), "manualFanSpeed": .integer(60)])
        let applied = original.applying(changes)
        #expect(applied.automatic == false)
        #expect(applied[.minimum] == 25)
        var back = applied
        back.select(automatic: true)
        #expect(back.changes(from: applied) == ["autofanspeed": .integer(1), "temptarget": .integer(55)])
    }

    @Test func boundariesPreventStepsPastTheSupportedRange() {
        for (field, automatic): (MinerCoolingPreviewDraft.Field, Bool) in [(.target, true), (.minimum, true), (.manual, false)] {
            for increasing in [true, false] {
                let edge = increasing ? field.bounds.upperBound : field.bounds.lowerBound
                var fields = configured
                fields["autofanspeed"] = .bool(automatic)
                fields[field.rawValue] = .integer(Int64(edge))
                var draft = MinerCoolingPreviewDraft(info: .init(raw: fields))
                #expect(draft.adjusted(field, increasing: increasing) == nil)
                draft.adjust(field, increasing: increasing)
                #expect(draft[field] == edge)
                #expect(draft.adjusted(field, increasing: !increasing) != nil)
            }
        }
    }

    @Test func missingOrInvalidConfigurationDoesNotBorrowFromSensors() {
        var fields = configured
        fields["manualFanSpeed"] = nil
        fields["minFanSpeed"] = .number(25.5)
        var draft = MinerCoolingPreviewDraft(info: .init(raw: fields))
        #expect(draft.supportsMode(automatic: true))
        #expect(!draft.supportsMode(automatic: false))
        #expect(draft[.minimum] == nil)
        draft.select(automatic: false)
        #expect(draft.automatic == true)
        fields["temptarget"] = .integer(67)
        draft = .init(info: .init(raw: fields))
        #expect(!draft.supportsMode(automatic: true))
        #expect(draft.adjusted(.target, increasing: false) == nil)
        fields["autofanspeed"] = nil
        draft = .init(info: .init(raw: fields))
        #expect(draft.activeFields.isEmpty)
        #expect(draft.changes(from: .init(info: .init(raw: configured))).isEmpty)
    }
}

@Suite(.serialized)
@MainActor
struct MinerDetailRenderingCoverageTests {
    enum ReadingState: String, CaseIterable, Sendable {
        case sample, missing, offline, reconnecting, live, cpu
    }

    @Test
    func guidedCoolingPublishesItsActualAnchor() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        for width in [390.0, 1_024.0] {
            let view = MinerDetailView(device: device, store: fixture.store, insights: fixture.insights)
                .environment(\.fleetGuidedDemo, true)
                .environment(\.fleetGuidedTargetID, "guide.cooling")
                .overlayPreferenceValue(FleetTourAnchorKey.self) { anchors in
                    Text(anchors["guide.cooling"] == nil ? "Missing cooling anchor" : "Cooling anchor published")
                        .padding()
                        .background(Color.black)
                        // The center of the wide capture is an OCR tile boundary. Keep
                        // this test-only marker at the leading edge so its words are
                        // observed together. The production content and assertions stay intact.
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            let rendered = try await FleetViewRenderHarness.render(view, width: width, height: 1_400)
            #expect(rendered.visibleText.contains("Cooling anchor published"))
            #expect(!rendered.visibleText.contains("Missing cooling anchor"))
        }
    }

    @Test(arguments: ReadingState.allCases)
    func detailKeepsReportedAndUnavailableReadingsHonest(_ state: ReadingState) async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        var device = try #require(fixture.store.devices.first)
        let originalInfo = try #require(fixture.store.snapshots[device.id]?.info)
        var snapshot = try #require(fixture.store.snapshots[device.id])
        switch state {
        case .sample:
            break
        case .missing:
            snapshot.info = MinerInfo(raw: [:])
        case .offline:
            fixture.store.isDemo = false
            snapshot.error = "Fixture connection unavailable"
            snapshot.isCached = true
        case .reconnecting:
            fixture.store.isDemo = false
            snapshot.isReconnecting = true
        case .live:
            fixture.store.isDemo = false
        case .cpu:
            device.kind = .xmrig
            fixture.store.devices = [device]
            snapshot.info = MinerInfo(raw: [
                "hashRate": .number(0.002),
                "sharesAccepted": .integer(12),
                "sharesRejected": .integer(1),
                "uptimeSeconds": .integer(120),
                "version": .string("XMRig fixture")
            ])
        }
        fixture.store.snapshots[device.id] = snapshot
        let detail = MinerDetailView(device: device, store: fixture.store, insights: fixture.insights,
                                     isLive: state == .live)
        #expect(detail.currentDevice.id == device.id)
        #expect(detail.isXMRig == (state == .cpu))
        #expect(detail.info == snapshot.info)
        // Keep every existing CPU implementation assertion for future re-enable. Shipping
        // navigation visibility is tested separately, rather than deleting CPU coverage.
        let rendered = try await FleetViewRenderHarness.render(NavigationStack {
            if state == .cpu { detail.releasedContent } else { detail }
        }, height: 1_600)
        #expect(rendered.pixelVariation > 1)
        switch state {
        case .sample:
            #expect(rendered.visibleText.contains("SAMPLE HASHRATE"))
        case .missing:
            #expect(rendered.visibleText.contains("Not reported"))
            // Recorded history remains valid when the current sensor stops reporting.
            #expect(rendered.visibleText.contains("Hashrate trend"))
            // Vision can read the monospaced lowercase s in TH/s as S. Keep the
            // numeric rate and unit exact while ignoring only that OCR casing.
            #expect(rendered.visibleText.localizedCaseInsensitiveContains(
                FleetFormat.hashrateWithUnit(originalInfo.hashRate)
            ))
            let missingHero = try await FleetViewRenderHarness.render(detail.hashrateHero(try #require(snapshot.info)))
            let reportedHero = try await FleetViewRenderHarness.render(detail.hashrateHero(originalInfo))
            let originalRate = FleetFormat.hashrate(originalInfo.hashRate)
            #expect(reportedHero.visibleText.contains(originalRate))
            #expect(missingHero.visibleText.contains("Not reported"))
            #expect(!missingHero.visibleText.contains(originalRate))
            #expect(missingHero.pngData != reportedHero.pngData)
        case .offline:
            #expect(rendered.visibleText.contains("Fixture connection unavailable"))
            #expect(rendered.visibleText.contains("LAST KNOWN HASHRATE"))
        case .reconnecting:
            #expect(rendered.visibleText.contains("RECONNECTING"))
        case .live:
            #expect(rendered.visibleText.contains("LIVE HASHRATE"))
        case .cpu:
            #expect(rendered.visibleText.contains("XMRIG CPU"))
            #expect(rendered.visibleText.contains("XMRig control"))
        }
    }

    @Test
    func detailShowsToolsDirectly() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let detail = MinerDetailView(device: device, store: fixture.store, insights: fixture.insights)
        let rendered = try await FleetViewRenderHarness.render(NavigationStack { detail.controls }, height: 1_600)
        #expect(rendered.visibleText.contains("Settings"))
        #expect(rendered.visibleText.contains("Check compatibility"))
        #expect(rendered.visibleText.contains("Endpoint explorer"))
        #expect(fixture.store.isDemo)
    }

    @Test(arguments: [false, true])
    func collapsedCardsDoNotEagerlyExposeTheirTelemetry(_ expanded: Bool) async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let spec = MinerDetailCardSpec(title: "Fixture cooling", subtitle: "Reported sensors only",
            symbol: "fan", id: "render.cooling", settings: .cooling, settingsID: "render.cooling.settings")
        let card = MinerDetailCollapsibleCard(spec: spec, expanded: .constant(expanded), device: device,
            store: fixture.store, insights: fixture.insights) {
                Text("Reported temperature 53 Celsius")
            }
        let rendered = try await FleetViewRenderHarness.render(NavigationStack { card })
        #expect(rendered.visibleText.contains("Fixture cooling"))
        #expect(rendered.visibleText.contains("Reported temperature 53 Celsius") == expanded)
        #expect(rendered.visibleText.contains("Reported sensors only"))
        // Expanded/Collapsed is an accessibilityValue, not drawn text. Native disclosure tests
        // assert that value. Here, content presence above is the visible expansion contract.
    }

    @Test(arguments: [nil, 0.0, 53.5] as [Double?])
    func missingMetricIsNotInventedAsZero(_ value: Double?) async throws {
        let metric = MinerDetailMetric(title: "Fixture temperature", value: value, unit: "C", symbol: "thermometer")
        // OCR cannot reliably distinguish this font's isolated zero from the letter O.
        // Missing-versus-zero is checked with paired actual images, not character repair.
        let rendered = try await FleetViewRenderHarness.render(
            metric.environment(\.dynamicTypeSize, .accessibility3), width: 800, height: 600)
        #expect(rendered.visibleText.contains("Fixture temperature"))
        if let value {
            #expect(!rendered.visibleText.contains("N/A"))
            if value == 0 {
                let missing = try await FleetViewRenderHarness.render(
                    MinerDetailMetric(title: "Fixture temperature", value: nil, unit: "C", symbol: "thermometer")
                        .environment(\.dynamicTypeSize, .accessibility3), width: 800, height: 600)
                #expect(missing.visibleText.contains("N/A"))
                #expect(rendered.pngData != missing.pngData)
                #expect(metric.value == 0)
                // This does not claim exact zero-glyph recognition or accessibility semantics.
            } else {
                #expect(rendered.visibleText.contains(value.formatted(.number.precision(.fractionLength(0...1)))))
            }
        } else {
            #expect(rendered.visibleText.contains("N/A"))
            #expect(!rendered.visibleText.contains("0"))
        }
    }

    @Test func coolingComparisonRendersOnlyRealPreviousValues() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let current = MinerInfo(raw: ["temp": .number(55), "temp2": .number(57), "vrTemp": .number(60),
            "fanspeed": .number(70), "fanrpm": .number(4_500)])
        let previous = MinerInfo(raw: ["temp": .number(50), "temp2": .number(59), "vrTemp": .number(60),
            "fanspeed": .number(65), "fanrpm": .number(4_200)])
        fixture.store.snapshots[device.id] = MinerSnapshot(info: current, previousInfo: previous)
        let detail = MinerDetailView(device: device, store: fixture.store)
        let readings = MinerCoolingComparison.readings(current: current, previous: previous)
        #expect(readings.map(\.id) == ["chipTemp", "vrTemp", "fanSpeed"])
        #expect(readings.map(\.direction) == [.increased, .unchanged, .increased])
        let rendered = try await FleetViewRenderHarness.render(detail.coolingComparison(current))
        #expect(rendered.visibleText.contains("Since previous sample"))
        // Direction words are spoken metadata. Preserve their generator contract separately,
        // without claiming OCR has validated the platform accessibility tree.
        let chipComparison = try #require(readings.first { $0.id == "chipTemp" })
        let vrComparison = try #require(readings.first { $0.id == "vrTemp" })
        #expect(detail.comparisonLabel(chipComparison) == "Now 55°C, up 5°C, was 50°C")
        #expect(detail.comparisonLabel(vrComparison) == "Now 60°C, unchanged by 0°C, was 60°C")
        // The visible rows contain numbers and a direction symbol, not those spoken sentences.
        for fragment in ["Now 55°C", "5°C was 50°C", "Now 60°C", "0°C was 60°C"] {
            #expect(rendered.visibleText.contains(fragment))
        }
        #expect(!rendered.visibleText.contains("Temperature 2"))
        #expect(rendered.visibleText.contains("not a firmware health verdict"))
    }

    @Test(arguments: [false, true])
    func thermalAndTuningCardsRenderBothReportedAndMissingSensors(_ populated: Bool) async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        var fields = populated ? try #require(fixture.store.snapshots[device.id]?.info?.raw) : [:]
        if populated { fields["temp2"] = .number(59) }
        let info = MinerInfo(raw: fields)
        let detail = MinerDetailView(device: device, store: fixture.store)
        let diagnostics = MinerDiagnosticsModel(info: info)
        let rendered = try await FleetViewRenderHarness.render(
            VStack {
                detail.primaryMetrics(info, diagnostics: diagnostics)
                detail.coolingCard(info)
                detail.tuningCard(info)
                detail.secondaryMetrics(info, diagnostics: diagnostics)
            }, height: 1_600)
        #expect(rendered.visibleText.contains("Cooling"))
        #expect(rendered.visibleText.contains("Tuning"))
        #expect(rendered.visibleText.contains("Temperature 2") == populated)
        #expect(MinerThermalPresentation.reportedTemperatures(info).count == (populated ? 2 : 1))
        // Compact metric cards draw N/A, while their native accessibility label says not reported.
        if !populated { #expect(rendered.visibleText.contains("N/A")) }
    }

    @Test func missingHashrateHasNoInventedUnit() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let detail = MinerDetailView(device: device, store: fixture.store)
        let missing = try await FleetViewRenderHarness.render(detail.hashrateHeroValue(nil))
        let reported = try await FleetViewRenderHarness.render(detail.hashrateHeroValue(1_250))
        #expect(missing.visibleText.contains("Not reported"))
        #expect(!missing.visibleText.contains("TH/s"))
        #expect(reported.visibleText.contains("TH/s"))
        #expect(missing.pngData != reported.pngData)
    }

    @Test func firmwareNoticeIsInformationalAndLimitsReleaseRows() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.first)
        let detail = MinerDetailView(device: device, store: fixture.store)
        let releases = (1...7).map { index in
            FirmwareRelease(version: "v2.15.\(index)",
                url: URL(string: "https://releases.invalid/\(index)"))
        }
        let notice = FirmwareUpdateNotice(currentVersion: "v2.14.0", releases: releases,
            checkedAt: Date(timeIntervalSince1970: 1_700_000_000), checkFailed: false)
        let rendered = try await FleetViewRenderHarness.render(detail.firmwareUpdateSection(notice))
        #expect(rendered.visibleText.contains("Firmware updates"))
        #expect(rendered.visibleText.contains("Newest v2.15.7"))
        #expect(rendered.visibleText.contains("View release"))
        #expect(rendered.visibleText.contains("v2.15.5"))
        #expect(!rendered.visibleText.contains("v2.15.6"))
        #expect(fixture.store.firmwareUpdates.notices.isEmpty, "Rendering a notice must not perform a release check or dismiss it")
    }

    @Test func detailNavigationIdentityUsesSelectedDeviceAndItsPool() throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let device = try #require(fixture.store.devices.last)
        let detail = MinerDetailView(device: device, store: fixture.store, insights: fixture.insights)
        #expect(detail.navigationIdentity.deviceName == device.name)
        #expect(detail.navigationIdentity.coin == .btc)
        #expect(detail.navigationIdentity.poolName != nil)
        fixture.store.snapshots[device.id] = MinerSnapshot(info: MinerInfo(raw: [:]))
        #expect(detail.navigationIdentity.poolName == nil)
        #expect(detail.navigationIdentity.coin == nil)
    }

    @Test func addMinerFormDoesNotBeginDiscoveryOrChangeFleetOnAppearance() async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let originalDevices = fixture.store.devices
        let form = AddMinerView(store: fixture.store)
        let rendered = try await FleetViewRenderHarness.render(form, height: 1_600)
        // Input labels and placeholders are visible. The longer spoken field names are AX-only.
        #expect(rendered.visibleText.contains("MINER NAME (OPTIONAL)"))
        #expect(rendered.visibleText.contains("Desk miner"))
        #expect(rendered.visibleText.contains("NETWORK ADDRESS"))
        #expect(rendered.visibleText.contains("192.168.1.42 or bitaxe.local"))
        #expect(rendered.visibleText.contains("Add miner"))
        #expect(fixture.store.devices == originalDevices)
        #expect(form.discovery.state == .idle)
    }

    @Test(arguments: ["No compatible miners found", "Wi-Fi scan unavailable"])
    func discoveryFailureKeepsManualEntryAndRetryHonest(_ title: String) async throws {
        let fixture = try FleetRenderFixture()
        defer { fixture.cleanup() }
        let form = AddMinerView(store: fixture.store)
        let rendered = try await FleetViewRenderHarness.render(
            form.discoveryEmptyState(title: title, message: "Fixture network is unavailable. Enter an address manually."))
        #expect(rendered.visibleText.contains(title))
        #expect(rendered.visibleText.contains("Try again"))
        #expect(rendered.visibleText.contains("Enter an address manually"))
        #expect(form.discovery.state == .idle)
    }
}
