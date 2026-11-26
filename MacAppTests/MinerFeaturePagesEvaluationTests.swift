import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Hosts the firmware-specific miner pages that previously rendered in no test:
/// Harlo OS tools, firmware extras, Avalon controls, compatibility, custom JSON,
/// diagnostics and the raw endpoint editor. Each page is laid out off-screen across
/// the firmware families and dashboard modes that change its body. Nothing is written
/// and no socket is opened.
@Suite("Miner feature pages evaluation", .serialized)
@MainActor
struct MinerFeaturePagesEvaluationTests {
    private func makeStore(demo: Bool) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.featurepages.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        if demo { store.loadDemo() }
        return (store, defaults, suite)
    }

    private func evaluate<V: View>(_ view: V, width: CGFloat = 900, height: CGFloat = 1600) {
        let host = NSHostingView(rootView: NavigationStack { view })
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    private func info(_ fields: [String: JSONValue]) -> MinerInfo { MinerInfo(raw: fields) }

    private func snapshot(_ info: MinerInfo) -> MinerSnapshot {
        MinerSnapshot(
            info: info, previousInfo: nil, error: nil, updatedAt: Date(),
            completeSnapshotAt: Date(), powerObservedAt: Date(),
            history: [], isCached: false, isReconnecting: false
        )
    }

    private func live(
        name: String, family: String, kind: MinerDevice.Kind = .espMiner, fields: [String: JSONValue]
    ) -> (FleetStore, MinerDevice, UserDefaults, String) {
        let (store, defaults, suite) = makeStore(demo: false)
        let device = MinerDevice(name: name, address: "192.168.1.40", kind: kind, firmwareFamily: family)
        store.devices = [device]
        store.snapshots[device.id] = snapshot(info(fields))
        return (store, device, defaults, suite)
    }

    private func diagnosticsFields() -> [String: JSONValue] {
        var fields = baseFields(family: "bitaxe")
        fields["hashRate_1m"] = .number(890)
        fields["hashRate_10m"] = .number(870)
        fields["hashRate_1h"] = .number(860)
        fields["expectedHashrate"] = .number(950)
        fields["errorPercentage"] = .number(0.4)
        fields["sharesPending"] = .integer(2)
        fields["current"] = .number(3600)
        fields["nominalVoltage"] = .number(5)
        fields["coreVoltageActual"] = .number(1090)
        fields["fanSpeed"] = .number(42)
        fields["minFanSpeed"] = .number(25)
        fields["responseTime"] = .number(180)
        fields["responseShareBatch"] = .integer(4)
        fields["poolDifficulty"] = .number(1_000_000)
        fields["poolConnectionInfo"] = .string("IPv4")
        fields["primaryPoolIndex"] = .integer(0)
        fields["secondaryPoolIndex"] = .integer(1)
        fields["isUsingFallbackStratum"] = .bool(false)
        fields["stratumURL"] = .string("solo.ckpool.org")
        fields["stratumPort"] = .integer(3333)
        fields["fallbackStratumURL"] = .string("backup.pool")
        fields["fallbackStratumPort"] = .integer(3334)
        fields["sharesRejectedReasons"] = .array([.object(["message": .string("stale"), "count": .integer(3)])])
        fields["freeHeap"] = .integer(120_000)
        fields["cpuUsage"] = .number(12)
        return fields
    }

    private func baseFields(family: String) -> [String: JSONValue] {
        [
            "hostname": .string("Rig"), "firmwareFamily": .string(family),
            "ASICModel": .string("BM1370"), "deviceModel": .string("Gamma"),
            "hashRate": .number(900), "power": .number(18), "voltage": .number(5000),
            "temp": .number(52), "vrTemp": .number(60), "frequency": .number(500),
            "coreVoltage": .number(1100), "fanspeed": .number(40), "fanrpm": .number(3000),
            "overclockEnabled": .integer(1), "useNTP": .integer(0),
            "overheat_temp": .integer(75), "flipscreen": .bool(false), "autoscreenoff": .bool(true),
            "workmode": .integer(1), "power_fault": .string("PSU sag"),
            "fault_notice_title": .string("Thermal"), "fault_notice_reason": .string("ASIC"),
            "fault_notice_pending": .bool(true), "fault_notice_id": .string("n1")
        ]
    }

    @Test func evaluateHarloToolsLoaded() {
        let (store, device, defaults, suite) = live(name: "Harlo", family: "harloos", fields: baseFields(family: "harloos"))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preview = HarloPreview(
            updates: ["installed_version": .string("0.2.101"), "available": .bool(true),
                      "version": .string("0.2.110"), "phase": .string("ready"), "ignored": .bool(false)],
            time: ["local_time": .string("14:02"), "synced": .bool(true)],
            schedules: [["id": .integer(1), "enabled": .bool(true), "time": .string("21:00"),
                         "path": .string("/api/mining/stop"), "days": .array([.integer(1), .integer(2)])]],
            lighting: ["zones": .array([.object(["zone": .integer(1), "effect": .integer(2), "color": .string("ffffff"), "brightness": .integer(40)])]),
                       "rules": .object(["enabled": .bool(true)])],
            discord: ["webhook_configured": .bool(true), "last_delivery": .string("ok")],
            matter: ["configured": .bool(true), "power_w": .number(19.4), "state": .string("on")],
            network: ["interfaces": .array([.object(["id": .string("wifi"), "active": .bool(true), "ip": .string("192.168.1.40"), "ssid": .string("fleet")])])],
            fleet: ["scanning": .bool(false), "devices": .array([.object(["name": .string("Gamma"), "ip": .string("192.168.1.20"), "online": .bool(true)])])],
            wifiNetworks: ["fleet", "guest"], message: "Saved", failure: nil,
            minerName: "Harlo", ntpServer: "pool.ntp.org", timezone: "America/New_York",
            webhook: "", plugCode: "1234-567", plugAddress: "192.168.1.9", wifiSSID: "fleet"
        )
        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            evaluate(MinerHarloToolsPage(device: device, store: store, preview: preview), height: 2400)
        }
        let unpaired = HarloPreview(
            updates: ["installed_version": .string("0.2.101"), "available": .bool(false)],
            schedules: [], lighting: [:], discord: ["webhook_configured": .bool(false)],
            matter: ["configured": .bool(false)], failure: "Could not reach the miner"
        )
        evaluate(MinerHarloToolsPage(device: device, store: store, preview: unpaired), height: 2000)
    }

    @Test func evaluateHarloToolsInBothModes() {
        for mode in FleetPreferences.DashboardMode.allCases {
            let (store, device, defaults, suite) = live(name: "Harlo", family: "harloos", fields: baseFields(family: "harloos"))
            defer { defaults.removePersistentDomain(forName: suite) }
            store.preferences.dashboardMode = mode
            evaluate(MinerHarloToolsPage(device: device, store: store))
            let (demo, demoDefaults, demoSuite) = makeStore(demo: true)
            defer { demoDefaults.removePersistentDomain(forName: demoSuite) }
            demo.preferences.dashboardMode = mode
            if let sample = demo.devices.first {
                evaluate(MinerHarloToolsPage(device: sample, store: demo), width: 420, height: 900)
            }
        }
    }

    @Test func evaluateFirmwareExtrasAcrossFamilies() {
        let families = ["bitaxe", "nerdqaxe", "nerdoctaxe", "bitfortun", "warpaxe", "axeforge", "harloos", "unknown"]
        for family in families {
            for mode in FleetPreferences.DashboardMode.allCases {
                let (store, device, defaults, suite) = live(name: family, family: family, fields: baseFields(family: family))
                defer { defaults.removePersistentDomain(forName: suite) }
                store.preferences.dashboardMode = mode
                evaluate(MinerFirmwareExtrasPage(device: device, store: store))
            }
        }
        let (demo, defaults, suite) = makeStore(demo: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        if let sample = demo.devices.first {
            evaluate(MinerFirmwareExtrasPage(device: sample, store: demo))
        }
        let documents: [String: [String: JSONValue]] = [
            "settings": [
                "atune": .bool(true), "tgoal": .integer(1), "pcap": .integer(40),
                "overclock": .object(["unlocked": .bool(false)])
            ],
            "/api/protections": ["asic_fan_c": .integer(60), "asic_shutdown_c": .integer(80),
                                  "vr_fan_c": .integer(70), "vr_shutdown_c": .integer(90)],
            "/api/display": ["mode": .string("dashboard"), "rotation": .integer(0)],
            "/api/collection": ["enabled": .bool(true)],
            "/api/power-supply": ["power_supply_rating_w": .integer(120)],
            "/api/temperature-unit": ["temperature_unit": .string("C")]
        ]
        for family in ["axeforge", "harloos"] {
            let (fleet, miner, minerDefaults, minerSuite) = live(name: family, family: family, fields: baseFields(family: family))
            defer { minerDefaults.removePersistentDomain(forName: minerSuite) }
            evaluate(MinerFirmwareExtrasPage(device: miner, store: fleet, documents: documents,
                                             message: "Applied", failure: "Not applied"))
        }
    }

    @Test func evaluateAvalonControlsAcrossModels() {
        let variants: [(String, [String: JSONValue])] = [
            ("canaan", ["deviceModel": .string("Avalon A10"), "workmode": .integer(2)]),
            ("canaan", ["deviceModel": .string("Avalon Nano 3s"), "ASICModel": .string("nano"), "workmode": .integer(0)]),
            ("canaannano3", ["deviceModel": .string("Avalon Nano 3")]),
            ("bitaxe", [:])
        ]
        for (family, extra) in variants {
            var fields = baseFields(family: family)
            for (key, value) in extra { fields[key] = value }
            for mode in FleetPreferences.DashboardMode.allCases {
                let (store, device, defaults, suite) = live(
                    name: family, family: family, kind: .espMiner, fields: fields
                )
                defer { defaults.removePersistentDomain(forName: suite) }
                store.preferences.dashboardMode = mode
                evaluate(MinerAvalonControlsPage(device: device, store: store))
            }
        }
    }

    @Test func evaluateCompatibilityCustomJSONAndDiagnostics() {
        let (store, device, defaults, suite) = live(name: "Probe", family: "bitaxe", fields: baseFields(family: "bitaxe"))
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = MiningInsightsStore()
        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            evaluate(MinerCompatibilityView(device: device, store: store, insights: insights))
            evaluate(MinerCustomJSONView(device: device, isDemo: false, isOffline: false, initialJSON: "{\n  \"fan\": 40\n}") { _ in })
            evaluate(MinerCustomJSONView(device: device, isDemo: true, isOffline: true) { _ in }, width: 500, height: 700)
            evaluate(MinerDiagnosticsView(model: MinerDiagnosticsModel(info: info(baseFields(family: "bitaxe"))), isExpanded: true))
            evaluate(MinerDiagnosticsView(model: MinerDiagnosticsModel(raw: [:]), isExpanded: false), width: 360, height: 200)
            evaluate(MinerDiagnosticsView(model: MinerDiagnosticsModel(info: info(diagnosticsFields())), isExpanded: true), width: 900, height: 2200)
        }
        let (demo, demoDefaults, demoSuite) = makeStore(demo: true)
        defer { demoDefaults.removePersistentDomain(forName: demoSuite) }
        if let sample = demo.devices.first {
            evaluate(MinerCompatibilityView(device: sample, store: demo, insights: insights))
        }
    }

    @Test func evaluateTuningPreviewAndSession() {
        let insights = MiningInsightsStore()
        let (store, device, defaults, suite) = live(name: "Tune", family: "bitaxe", fields: diagnosticsFields())
        defer { defaults.removePersistentDomain(forName: suite) }
        let info = store.snapshot(for: device.id)!.info!
        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            evaluate(MinerTuningPreviewRoute(device: device, store: store, insights: insights), width: 900, height: 1600)
            evaluate(
                MinerTuningPreview(mode: mode, device: device, store: store, info: info,
                                   isDemo: false, canEdit: true, insights: insights),
                width: 900, height: 1800
            )
            evaluate(
                MinerTuningPreview(mode: mode, device: device, store: store, info: info,
                                   isDemo: true, canEdit: false, insights: insights),
                width: 420, height: 1400
            )
            evaluate(MinerTuningSessionView(device: device, store: store, insights: insights), width: 900, height: 1600)
        }
    }

    @Test func evaluateMinerDetailLayouts() {
        let insights = MiningInsightsStore()
        let fields = diagnosticsFields()
        for kind in [MinerDevice.Kind.espMiner, .xmrig] {
            let (store, device, defaults, suite) = live(name: "Detail", family: "bitaxe", kind: kind, fields: fields)
            defer { defaults.removePersistentDomain(forName: suite) }
            for mode in FleetPreferences.DashboardMode.allCases {
                store.preferences.dashboardMode = mode
                evaluate(MinerDetailView(device: device, store: store, insights: insights), width: 1280, height: 1100)
                var classic = MinerDetailView(device: device, store: store, insights: insights)
                classic.showsClassicDetailForTesting = true
                evaluate(classic, width: 1280, height: 1400)
                evaluate(classic, width: 420, height: 2000)
            }
        }
    }

    @Test func evaluateSettingsPagesPopulated() {
        let (store, device, defaults, suite) = live(name: "Bench", family: "bitaxe", fields: [
            "hostname": .string("bench"), "version": .string("v2.15.2"), "ASICModel": .string("BM1370"),
            "hashRate": .number(900), "power": .number(18), "temp": .number(52), "vrTemp": .number(60),
            "frequency": .integer(550), "coreVoltage": .integer(1100), "actualFrequency": .integer(548),
            "coreVoltageActual": .integer(1090), "fanspeed": .integer(60), "fanrpm": .integer(4000),
            "autofanspeed": .integer(1), "temptarget": .integer(55), "minFanSpeed": .integer(25),
            "rotation": .integer(90), "invertscreen": .integer(1), "displayTimeout": .integer(12),
            "statsFrequency": .integer(30), "stratumURL": .string("solo.ckpool.org"),
            "stratumPort": .integer(3333), "stratumUser": .string("worker"),
            "fallbackStratumURL": .string("backup.pool"), "fallbackStratumPort": .integer(3333),
            "primaryPoolIndex": .integer(0), "secondaryPoolIndex": .integer(1),
            "pools": .array([
                .object(["id": .integer(0), "stratumURL": .string("solo.ckpool.org"), "stratumPort": .integer(3333), "stratumUser": .string("worker.0")]),
                .object(["id": .integer(1), "stratumURL": .string("backup.pool"), "stratumPort": .integer(3333), "stratumUser": .string("worker.1")])
            ])
        ])
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = MiningInsightsStore()
        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            for category in MinerSettingsCategory.allCases {
                evaluate(
                    MinerSettingsView(device: device, store: store, insights: insights, initialCategory: category),
                    width: 760, height: 1800
                )
            }
        }
    }

    @Test func evaluateEndpointEditorAcrossCatalog() {
        let (store, device, defaults, suite) = live(name: "API", family: "bitaxe", fields: baseFields(family: "bitaxe"))
        defer { defaults.removePersistentDomain(forName: suite) }
        let insights = MiningInsightsStore()
        for mode in FleetPreferences.DashboardMode.allCases {
            store.preferences.dashboardMode = mode
            for endpoint in MinerEndpoint.catalog {
                evaluate(
                    MinerEndpointView(device: device, store: store, endpoint: endpoint, insights: insights, onWriteCompleted: {}),
                    width: 760, height: 900
                )
            }
        }
    }
}
