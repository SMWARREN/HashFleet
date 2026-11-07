import Foundation
import SwiftUI
import Testing
import UIKit
import HashFleetCore
@testable import HashFleet

/// Comprehensive rendering and behavior test suite covering all six settings categories,
/// hub cards, pool connection configurations, read-only/demo/offline/missing-field states,
/// unified quick changes, guided mining setup, and underlying model/validation branches.
@Suite("Miner Settings Rendering Coverage Tests", .serialized)
@MainActor
struct MinerSettingsRenderingCoverageTests {

    private func makeTestDevice(
        name: String = "Bitaxe Ultra Test",
        address: String = "miner-alpha.test.invalid"
    ) -> MinerDevice {
        MinerDevice(name: name, address: address)
    }

    private func makeCompleteRawInfo(
        hostname: String = "rig-alpha-01",
        autoFan: Bool = true,
        statsFrequency: Int64 = 30,
        temp: Int64 = 56,
        fanSpeed: Int64 = 68
    ) -> [String: JSONValue] {
        [
            "hostname": .string(hostname), "autofanspeed": .integer(autoFan ? 1 : 0),
            "manualFanSpeed": .integer(75), "minFanSpeed": .integer(25),
            "temptarget": .integer(58), "temp": .integer(temp), "vrTemp": .integer(52),
            "fanspeed": .integer(fanSpeed), "fanRPM": .integer(4250), "statsFrequency": .integer(statsFrequency),
            "rotation": .integer(90), "invertscreen": .integer(0), "displayTimeout": .integer(5),
            "primaryPoolIndex": .integer(0), "secondaryPoolIndex": .integer(1),
            "frequency": .number(525.0), "coreVoltage": .integer(1060),
            "boardVersion": .string("Gamma 601a"), "version": .string("v2.15.2"),
            "ASICModel": .string("BM1370"), "hashRate": .number(530.0), "hardwareErrors": .integer(4),
            "pools": .array([
                .object([
                    "id": .integer(0), "stratumURL": .string("primary.pool.test.invalid"),
                    "stratumPort": .string("3333"), "stratumUser": .string("miner.worker1"),
                    "stratumProtocol": .string("SV1"), "active": .bool(true)
                ]),
                .object([
                    "id": .integer(1), "stratumURL": .string("fallback.pool.test.invalid"),
                    "stratumPort": .string("8004"), "stratumUser": .string("dgb-wallet.worker2"),
                    "stratumProtocol": .string("SV1"), "active": .bool(false)
                ])
            ])
        ]
    }

    // MARK: - 1. Models, Drafts, and Matrix Validation

    @Test("MinerSettingsCategory, Draft, direct-save policy, and settings review models")
    func testModelsAndDraftsMatrix() throws {
        let all = MinerSettingsCategory.allCases
        #expect(all.count == 6 && all.map(\.id) == ["general", "cooling", "display", "pools", "tuning", "advanced"])

        let d1 = MinerSettingsDraft(endpoint: .settings, json: "{\"hostname\":\"rig1\"}", notice: nil)
        let d2 = MinerSettingsDraft(endpoint: .settings, json: "{\"hostname\":\"rig1\"}", notice: nil)
        let d3 = MinerSettingsDraft(endpoint: .settings, json: "{\"hostname\":\"rig2\"}", notice: "Reset")
        #expect(d1 == d2 && d1 != d3 && d1.hashValue == d2.hashValue && d3.notice == "Reset")
        #expect(MinerSettingsReference.fields.contains("Pool routing") && MinerSettingsReference.fields.contains("Nested Pool fields"))

        for key in ["hostname", "statsFrequency", "rotation", "invertscreen", "displayTimeout"] {
            #expect(MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: .object([key: .string("val")])))
        }
        let comb: JSONValue = .object(["hostname": .string("rig"), "statsFrequency": .integer(60), "rotation": .integer(180)])
        #expect(MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: comb))
        #expect(MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: comb))
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .restart, payload: comb))
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: .object([:])))
        for risky in ["frequency", "coreVoltage", "manualFanSpeed", "minFanSpeed", "temptarget", "stratumURL"] {
            #expect(!MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: .object(["hostname": .string("rig"), risky: .integer(1)])))
        }

        let baseInfo = MinerInfo(raw: ["hostname": .string("rig-orig"), "statsFrequency": .integer(30), "autofanspeed": .integer(1), "temptarget": .integer(58)])
        let rev = try MinerSettingsReview(original: baseInfo, hostname: "rig-next", statsFrequency: 60, autoFan: false, temperatureTarget: "62")
        #expect(rev.changes.count >= 3 && rev.message.contains("rig-orig → rig-next"))
        #expect(throws: (any Error).self) { try MinerSettingsReview(original: baseInfo, hostname: "invalid host!", statsFrequency: nil, autoFan: true, temperatureTarget: "") }
        #expect(throws: (any Error).self) { try MinerSettingsReview(original: baseInfo, hostname: "rig-orig", statsFrequency: nil, autoFan: true, temperatureTarget: "20") }
        #expect(throws: (any Error).self) { try MinerSettingsReview(original: baseInfo, hostname: "rig-orig", statsFrequency: 30, autoFan: true, temperatureTarget: "58") }
    }

    // MARK: - 2. Settings Hub State Variants

    @Test("Render Settings Hub across Demo, Live, Offline, Reconnecting, and Cached states")
    func testSettingsHubStateVariants() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let dev = try #require(fixture.store.devices.first)

        // 1. Demo state
        let rDemo = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: dev, store: fixture.store, insights: fixture.insights)
        }, width: 390, height: 1800)
        #expect(rDemo.pngData.count > 0 && rDemo.pixelVariation > 1)
        #expect(rDemo.visibleText.contains("DEMO") && rDemo.visibleText.contains("READ ONLY"))
        #expect(rDemo.visibleText.contains("Demo settings are previews only"))

        // 2. The unified settings flow keeps the tools route directly available.
        let rDev = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: dev, store: fixture.store, insights: fixture.insights)
        }, width: 390, height: 3600)
        #expect(rDev.visibleText.contains("Tools & firmware"))

        // Non-demo fixture for live and network status variants
        let liveFixture = try FleetRenderFixture(demo: false)
        defer { liveFixture.cleanup() }
        let liveDev = makeTestDevice(name: "Rig Live Miner", address: "miner-live.test.invalid")
        liveFixture.store.devices = [liveDev]

        // 3. Live online state
        liveFixture.store.snapshots[liveDev.id] = MinerSnapshot(info: MinerInfo(raw: makeCompleteRawInfo()), updatedAt: Date())
        let rLive = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: liveDev, store: liveFixture.store, insights: liveFixture.insights)
        }, width: 390, height: 1800)
        #expect(rLive.visibleText.contains("Rig Live Miner") && rLive.visibleText.contains("Save changes"))

        // 4. Offline state
        liveFixture.store.snapshots[liveDev.id] = MinerSnapshot(info: nil, error: "Connection refused", updatedAt: Date().addingTimeInterval(-600))
        let rOff = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: liveDev, store: liveFixture.store, insights: liveFixture.insights)
        }, width: 390, height: 1800)
        #expect(rOff.visibleText.contains("Offline or stale") && rOff.visibleText.contains("read only"))
        #expect(rOff.visibleText.contains("No current connection confirmed."))
        #expect(rDemo.pngData != rOff.pngData, "Visual snapshots must differ between demo and offline")

        // 5. Reconnecting state
        liveFixture.store.snapshots[liveDev.id] = MinerSnapshot(info: nil, isReconnecting: true)
        let rRecon = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: liveDev, store: liveFixture.store, insights: liveFixture.insights)
        }, width: 390, height: 1800)
        #expect(rRecon.visibleText.contains("Reconnecting") && rRecon.visibleText.contains("read only"))

        // 6. Cached state
        liveFixture.store.snapshots[liveDev.id] = MinerSnapshot(info: MinerInfo(raw: makeCompleteRawInfo()), updatedAt: Date().addingTimeInterval(-180), isCached: true)
        let rCache = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: liveDev, store: liveFixture.store, insights: liveFixture.insights)
        }, width: 390, height: 1800)
        #expect(rCache.visibleText.contains("Cached reading") && rCache.visibleText.contains("Passwords and wallet credentials are not stored in the cache."))
    }

    // MARK: - 3. General Page Rendering

    @Test("Render General category page with direct save, history notices, and field notes")
    func testGeneralPageRenderingAndDirectSave() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let dev = try #require(fixture.store.devices.first)

        // 1. Demo mode direct save
        let rDemo = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: dev, store: fixture.store, insights: fixture.insights, initialCategory: .general)
        }, width: 390, height: 1200)
        #expect(rDemo.visibleText.contains("General") && rDemo.visibleText.contains("Save name") && rDemo.visibleText.contains("Save interval"))

        // 2. Safe fields remain direct-save controls in the unified flow.
        let rDev = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: dev, store: fixture.store, insights: fixture.insights, initialCategory: .general)
        }, width: 390, height: 1200)
        #expect(rDev.visibleText.contains("Save name") && rDev.visibleText.contains("Save interval"))
        #expect(!rDev.visibleText.contains("Review hostname change"))

        // 3. Populated stats frequency history notice from real snapshot
        let liveFixture = try FleetRenderFixture(demo: false)
        defer { liveFixture.cleanup() }
        let histDev = makeTestDevice(name: "Rig History Miner", address: "miner-hist.test.invalid")
        liveFixture.store.devices = [histDev]
        liveFixture.store.snapshots[histDev.id] = MinerSnapshot(info: MinerInfo(raw: makeCompleteRawInfo(statsFrequency: 30)), updatedAt: Date())
        let rHistory = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: histDev, store: liveFixture.store, insights: liveFixture.insights, initialCategory: .general)
        }, width: 390, height: 1200)
        #expect(rHistory.visibleText.contains("rig-alpha-01"))
        #expect(rHistory.visibleText.contains("roughly 720 samples"))
        #expect(rHistory.visibleText.contains("about 6 hours of history at this interval"))

        // 4. Missing field notes when device info is nil
        let nilDev = makeTestDevice(name: "Rig Nil Info", address: "miner-nil.test.invalid")
        liveFixture.store.devices = [nilDev]
        liveFixture.store.snapshots[nilDev.id] = MinerSnapshot(info: nil, updatedAt: nil)
        let rNil = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: nilDev, store: liveFixture.store, insights: liveFixture.insights, initialCategory: .general)
        }, width: 390, height: 1200)
        #expect(rNil.visibleText.contains("No reading for the device name yet."))
    }

    // MARK: - 4. Cooling Page Rendering

    @Test("Render Cooling category page across AutoFan, ManualFan, Accessibility sizes, and missing readings")
    func testCoolingPageRenderingAndLayouts() async throws {
        let liveFixture = try FleetRenderFixture(demo: false)
        defer { liveFixture.cleanup() }
        let dev = makeTestDevice(name: "Rig Thermal Miner", address: "miner-thermal.test.invalid")
        liveFixture.store.devices = [dev]

        // 1. AutoFan enabled from snapshot
        liveFixture.store.snapshots[dev.id] = MinerSnapshot(info: MinerInfo(raw: makeCompleteRawInfo(autoFan: true)), updatedAt: Date())
        let rAuto = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: dev, store: liveFixture.store, insights: liveFixture.insights, initialCategory: .cooling)
        }, width: 600, height: 1800)
        #expect(rAuto.visibleText.contains("Cooling") && rAuto.visibleText.contains("Temperature target") && rAuto.visibleText.contains("Minimum fan speed"))
        #expect(rAuto.recognizesMetric("56", unit: "°C") && rAuto.visibleText.contains("Temperature target")
            && rAuto.visibleText.contains("°C"),
                "Mounted cooling controls should show the reported reading and temperature unit: \(rAuto.visibleText)")
        #expect(rAuto.visibleText.contains("Review cooling change") && rAuto.visibleText.contains("Review minimum fan speed"))

        // 2. ManualFan enabled from snapshot
        liveFixture.store.snapshots[dev.id] = MinerSnapshot(info: MinerInfo(raw: makeCompleteRawInfo(autoFan: false)), updatedAt: Date())
        let rManual = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: dev, store: liveFixture.store, insights: liveFixture.insights, initialCategory: .cooling)
        }, width: 390, height: 1200)
        #expect(rManual.visibleText.contains("Manual fan speed") && !rManual.visibleText.contains("Minimum fan speed"))
        #expect(rManual.recognizesMetric("75", unit: "%"), "Mounted manual fan field should show its unit-bearing reported value")

        // 3. Dynamic type size accessibility layout
        let rA11y = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: dev, store: liveFixture.store, insights: liveFixture.insights, initialCategory: .cooling)
                .environment(\.dynamicTypeSize, .accessibility3)
        }, width: 420, height: 1500)
        #expect(rA11y.visibleText.contains("Chip temperature") && rA11y.visibleText.contains("Fan speed"))

        // 4. Missing readings
        liveFixture.store.snapshots[dev.id] = MinerSnapshot(info: MinerInfo(raw: [:]), updatedAt: Date())
        let rEmpty = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: dev, store: liveFixture.store, insights: liveFixture.insights, initialCategory: .cooling)
        }, width: 390, height: 1200)
        #expect(rEmpty.visibleText.contains("Not reported"))
    }

    // MARK: - 5. Display Page Rendering

    @Test("Render Display category page with direct save")
    func testDisplayPageRenderingAndSave() async throws {
        let liveFixture = try FleetRenderFixture(demo: false)
        defer { liveFixture.cleanup() }
        let dev = makeTestDevice(name: "Rig Display Miner", address: "miner-display.test.invalid")
        liveFixture.store.devices = [dev]
        liveFixture.store.snapshots[dev.id] = MinerSnapshot(info: MinerInfo(raw: makeCompleteRawInfo()), updatedAt: Date())

        // 1. Direct save
        let rSave = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: dev, store: liveFixture.store, insights: liveFixture.insights, initialCategory: .display)
        }, width: 390, height: 1200)
        #expect(rSave.visibleText.contains("Display") && rSave.visibleText.contains("Save rotation") && rSave.visibleText.contains("Save screen colors"))

        // 2. Safe display settings remain direct-save controls in the unified flow.
        let rRev = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: dev, store: liveFixture.store, insights: liveFixture.insights, initialCategory: .display)
        }, width: 390, height: 1200)
        #expect(rRev.visibleText.contains("Save rotation") && rRev.visibleText.contains("Save screen colors"))
        #expect(!rRev.visibleText.contains("Review rotation change"))
    }

    // MARK: - 6. Pools Page & Cards Rendering

    @Test("Render Pools category page, cards, fallback warnings, presets, and connection modes")
    func testPoolsPageAndCardVariants() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let dev = try #require(fixture.store.devices.first)

        // 1. Standard pools page
        let rPools = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: dev, store: fixture.store, insights: fixture.insights, initialCategory: .pools)
        }, width: 390, height: 3000)
        #expect(rPools.visibleText.contains("Pools") && rPools.visibleText.contains("Guided pool & coin setup") && rPools.visibleText.contains("Active pool slots"))

        // 2. Solo pool presets and configured slots cards
        let settingsView = MinerSettingsView(device: dev, store: fixture.store, insights: fixture.insights)
        let rPresets = try await FleetViewRenderHarness.render(settingsView.soloPoolPresets, width: 390, height: 600)
        #expect(rPresets.visibleText.contains("Guided pool & coin setup") && rPresets.visibleText.contains("Solo pool preset"))

        let rCfg = try await FleetViewRenderHarness.render(settingsView.configuredPoolSlots, width: 390, height: 500)
        #expect(rCfg.visibleText.contains("Configured slots"))
        let rAct = try await FleetViewRenderHarness.render(settingsView.activePoolSlots, width: 390, height: 500)
        #expect(rAct.visibleText.contains("Active pool slots") && rAct.visibleText.contains("Primary slot"))

        // 3. Fallback pool warning
        let liveFixture = try FleetRenderFixture(demo: false)
        defer { liveFixture.cleanup() }
        let fbDev = makeTestDevice(name: "Rig Fallback", address: "miner-fb.test.invalid")
        liveFixture.store.devices = [fbDev]
        liveFixture.store.snapshots[fbDev.id] = MinerSnapshot(info: MinerInfo(raw: [
            "isUsingFallbackStratum": .bool(true),
            "primaryPoolIndex": .integer(0), "secondaryPoolIndex": .integer(1),
            "pools": .array([.object(["id": .integer(0), "active": .bool(false)]), .object(["id": .integer(1), "active": .bool(true)])])
        ]), updatedAt: Date())
        let rFB = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: fbDev, store: liveFixture.store, insights: liveFixture.insights, initialCategory: .pools)
        }, width: 390, height: 1800)
        #expect(rFB.visibleText.contains("This miner reports its fallback pool is selected."))
    }
}

// MARK: - Extension Suite: Advanced, Reported State, Setup, and Execution Logic

extension MinerSettingsRenderingCoverageTests {

    // MARK: - 7. Tuning and Advanced Pages

    @Test("Render Tuning and Tools & firmware pages without a legacy mode gate")
    func testTuningAndAdvancedPages() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let dev = try #require(fixture.store.devices.first)

        // 1. Tuning page
        let rTune = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(device: dev, store: fixture.store, insights: fixture.insights, initialCategory: .tuning)
        }, width: 390, height: 1200)
        #expect(rTune.pngData.count > 0 && rTune.pixelVariation > 1)

        // 2. Tools & firmware is directly reachable without a mode switch.
        let advancedSettings = MinerSettingsView(device: dev, store: fixture.store, insights: fixture.insights)
        let rAdv = try await FleetViewRenderHarness.render(NavigationStack {
            advancedSettings.advancedPage
        }, width: 390, height: 1200)
        #expect(rAdv.visibleText.contains("Tools & firmware"))
        #expect(rAdv.visibleText.contains("Settings editor") && rAdv.visibleText.contains("Request JSON editor"))
        #expect(rAdv.visibleText.contains("Scan Wi-Fi networks") && rAdv.visibleText.contains("Firmware OTA update"))

        // 3. The category route and the hub route expose the same tools page.
        let vAdvDisabled = MinerSettingsView(device: dev, store: fixture.store, insights: fixture.insights, initialCategory: .advanced)
        let rFallback = try await FleetViewRenderHarness.render(NavigationStack { vAdvDisabled }, width: 390, height: 1800)
        #expect(rFallback.visibleText.contains("Request JSON editor"))
    }

    // MARK: - 8. Reported State and Compatibility Cards

    @Test("Render Reported State and Compatibility Cards across diagnostic and probe branches")
    func testReportedStateAndCompatibilityVariants() async throws {
        let fixture = try FleetRenderFixture(demo: false)
        defer { fixture.cleanup() }
        let dev = makeTestDevice(name: "Rig Pro State", address: "miner-pro.test.invalid")
        fixture.store.devices = [dev]
        let raw = makeCompleteRawInfo()

        // 1. Fresh reported state
        fixture.store.snapshots[dev.id] = MinerSnapshot(info: MinerInfo(raw: raw), updatedAt: Date())
        let rFresh = try await FleetViewRenderHarness.render(MinerSettingsView(device: dev, store: fixture.store).reportedStateCard, width: 390, height: 900)
        #expect(rFresh.visibleText.contains("Reported reading") && rFresh.visibleText.contains("525 MHz") && rFresh.visibleText.contains("1,060 mV"))

        // 2. Stale reported state
        fixture.store.snapshots[dev.id] = MinerSnapshot(info: MinerInfo(raw: raw), updatedAt: Date().addingTimeInterval(-600))
        let rStale = try await FleetViewRenderHarness.render(MinerSettingsView(device: dev, store: fixture.store).reportedStateCard, width: 390, height: 900)
        #expect(rStale.visibleText.contains("stale"))

        // 3. Compatibility card before and after a blocked read-only check
        let vUnchecked = MinerSettingsView(device: dev, store: fixture.store)
        #expect(vUnchecked.compatibilitySubtitle.contains("Not checked yet"))

        // The private report cache is populated only through its real read-only API.
        // This fixture session rejects every request, so failed checks must not claim support.
        await fixture.store.capabilities.check(device: dev, isDemo: false)
        #expect(MinerSettingsView(device: dev, store: fixture.store).compatibilitySubtitle.contains("Last check did not finish"))
        let rCard = try await FleetViewRenderHarness.render(
            MinerSettingsView(device: dev, store: fixture.store).compatibilityCard,
            width: 390, height: 100)
        #expect(rCard.visibleText.contains("Check compatibility"))
        fixture.store.capabilities.reset()
        #expect(MinerSettingsView(device: dev, store: fixture.store).compatibilitySubtitle.contains("Not checked yet"))
    }

    // MARK: - 9. Unified Quick Changes and Cooling Card

    @Test("Render unified Quick Changes and Cooling cards")
    func testUnifiedQuickChangesAndCoolingCards() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let dev = try #require(fixture.store.devices.first)

        // 1. The unified hub owns the everyday network/history controls.
        let demoSettings = MinerSettingsView(device: dev, store: fixture.store, insights: fixture.insights)
        let rDemo = try await FleetViewRenderHarness.render(
            NavigationStack { demoSettings.quickChangesCard },
            width: 390,
            height: 900
        )
        #expect(rDemo.visibleText.contains("Quick changes"))
        #expect(rDemo.visibleText.contains("Network hostname"))
        #expect(rDemo.visibleText.contains("On-device history"))

        let manualInfo = MinerInfo(raw: ["hostname": .string("rig"), "autofanspeed": .integer(0), "manualFanSpeed": .integer(80)])
        fixture.store.isDemo = false
        fixture.store.snapshots[dev.id] = MinerSnapshot(info: manualInfo, updatedAt: Date())
        let liveSettings = MinerSettingsView(
            device: dev,
            store: fixture.store,
            insights: fixture.insights,
            initialCategory: .cooling
        )
        let rLive = try await FleetViewRenderHarness.render(
            NavigationStack { liveSettings },
            width: 390,
            height: 1200
        )
        #expect(rLive.visibleText.contains("Cooling"))
        #expect(rLive.visibleText.contains("Fan control"))
        #expect(rLive.visibleText.contains("Manual fan speed"))

        // 2. Empty quick-change state remains explicit and actionable.
        let rZero = try await FleetViewRenderHarness.render(liveSettings.quickChangesCard, width: 390, height: 900)
        #expect(rZero.visibleText.contains("pending changes"))
        #expect(rZero.visibleText.contains("Adjust a value above, then tap Save."))
        // The zero glyph is not a reliable OCR oracle. Empty-draft validation is covered
        // independently in testModelsAndDraftsMatrix, without mapping the letter O to zero.
    }

    // MARK: - 10. MiningSetupView and Coin Compatibility

    @Test("Render MiningSetupView and test MiningCoin hardware compatibility and price quotes")
    func testMiningSetupViewAndCoinCompatibility() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let dev = try #require(fixture.store.devices.first)

        let rSetup = try await FleetViewRenderHarness.render(NavigationStack {
            MiningSetupView(device: dev, store: fixture.store, insights: fixture.insights, onSelectPreset: { _ in })
        }, width: 390, height: 1000)
        #expect(rSetup.visibleText.contains("Guided Pool Setup") && rSetup.visibleText.contains("1. Mining Mode") && rSetup.visibleText.contains("CKPool"))

        for model in ["BM1370", "BM1366", "BM1397", "BM1368", "BM1362", "BM1387"] {
            let res = MiningCoin.btc.checkCompatibility(reportedASIC: model)
            #expect(res.isCompatible)
            #expect(res.statusBadge == "Reported model uses SHA-256d (\(model))")
            #expect(res.description.contains("known SHA-256d hashing chip"))
        }
        let imp = MiningCoin.btc.checkCompatibility(reportedASIC: "BM1370FAKE")
        #expect(!imp.isCompatible && imp.statusBadge.contains("Unverified"))
        let empty = MiningCoin.btc.checkCompatibility(reportedASIC: nil)
        #expect(!empty.isCompatible && empty.statusBadge.contains("check compatibility"))

        #expect(CoinPriceQuote.fresh(usd: 90000, source: "mempool").displayText.contains("$90,000.00"))
        #expect(CoinPriceQuote.stale(usd: 90000, source: "mempool").displayText.contains("(stale)"))
        #expect(CoinPriceQuote.unavailable(reason: "none").displayText == "Price unavailable")
    }

    // MARK: - 11. Direct Save Status and Draft Destinations

    @Test("Render Direct Save Status and Draft Destination view with and without notice")
    func testDirectSaveStatusAndDraftDestinations() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let dev = try #require(fixture.store.devices.first)

        let sView = MinerSettingsView(device: dev, store: fixture.store, insights: fixture.insights)
        let rNormal = try await FleetViewRenderHarness.render(sView.draftDestination(MinerSettingsDraft(endpoint: .settings, json: "{}", notice: nil)), width: 390, height: 600)
        #expect(rNormal.pngData.count > 0)
        let rNotice = try await FleetViewRenderHarness.render(sView.draftDestination(MinerSettingsDraft(endpoint: .updatePool(0), json: "{}", notice: "Full reset")), width: 390, height: 600)
        #expect(rNotice.visibleText.contains("Full-slot replacement"))
    }

    // MARK: - 12. Mounted Form Fields and Observed-Data Safety Models

    @Test("Render observed settings fields and verify pure write-safety models")
    func testMountedSettingsFieldsAndObservedDataSafetyModels() async throws {
        let fixture = try FleetRenderFixture(demo: false)
        defer { fixture.cleanup() }
        let dev = makeTestDevice(name: "Rig Observed Miner", address: "miner-observed.test.invalid")
        fixture.store.devices = [dev]
        let info = MinerInfo(raw: makeCompleteRawInfo())
        let fresh = MinerSnapshot(info: info, updatedAt: Date())
        fixture.store.snapshots[dev.id] = fresh

        let mounted = try await FleetViewRenderHarness.render(NavigationStack {
            MinerSettingsView(
                device: dev,
                store: fixture.store,
                insights: fixture.insights,
                initialCategory: .general
            )
        }, width: 390, height: 1200)
        #expect(mounted.visibleText.contains("Hostname"))
        #expect(mounted.visibleText.contains("rig-alpha-01"))
        #expect(mounted.visibleText.contains("Statistics interval"))
        #expect(mounted.visibleText.contains("roughly 720 samples"))

        let observedView = MinerSettingsView(device: dev, store: fixture.store)
        #expect(observedView.reported("hostname"))
        #expect(observedView.reported("frequency"))
        #expect(!observedView.reported("wifiPass"))
        #expect(!observedView.offlineReadOnly)
        #expect(MinerWriteAvailability.allows(fresh))

        let safePayload: JSONValue = .object([
            "hostname": .string("rig-next"),
            "statsFrequency": .integer(60)
        ])
        #expect(MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: safePayload))
        #expect(MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: safePayload))
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .restart, payload: safePayload))
        #expect(!MinerDirectSavePolicy.qualifies(
            endpoint: .settings,
            payload: .object(["hostname": .string("rig-next"), "coreVoltage": .integer(1100)])
        ))

        let review = try MinerSettingsReview(
            original: info,
            hostname: "rig-next",
            statsFrequency: 60,
            autoFan: true,
            temperatureTarget: "58"
        )
        #expect(review.changes.map(\.key) == ["hostname", "statsFrequency"])
        let reviewFields = try #require(review.payload.objectValue)
        #expect(Set(reviewFields.keys) == Set(["hostname", "statsFrequency"]))
        #expect(reviewFields["coreVoltage"] == nil)
        #expect(reviewFields["stratumPassword"] == nil)

        let poolDraft = MinerTuningPoolDraft(
            slot: 1,
            server: "fallback.pool.test.invalid",
            port: "8004",
            user: "dgb-wallet.worker2",
            stratumProtocol: "SV1",
            replacePassword: false,
            password: "snapshot-password-must-not-be-copied"
        )
        #expect(throws: (any Error).self) { try poolDraft.payload(replacementAcknowledged: false) }
        let poolPayload = try poolDraft.payload(replacementAcknowledged: true)
        #expect(poolPayload["stratumURL"] == .string("fallback.pool.test.invalid"))
        #expect(poolPayload["stratumPort"] == .integer(8004))
        #expect(poolPayload["stratumPassword"] == .string("*****"))
        #expect(!(try poolPayload.prettyPrinted()).contains("snapshot-password-must-not-be-copied"))

        var cached = fresh
        cached.isCached = true
        fixture.store.snapshots[dev.id] = cached
        #expect(observedView.offlineReadOnly)
        #expect(!MinerWriteAvailability.allows(cached))
        fixture.store.snapshots.removeValue(forKey: dev.id)
        #expect(observedView.offlineReadOnly)
        #expect(!MinerWriteAvailability.allows(nil))
    }
}
