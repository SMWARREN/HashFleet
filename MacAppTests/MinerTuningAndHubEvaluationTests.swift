import AppKit
import HashFleetCore
import SwiftUI
import Testing
@testable import HashFleetMac

@Suite("Miner tuning and settings hub evaluation", .serialized)
@MainActor
struct MinerTuningAndHubEvaluationTests {
    private func withDemo(_ run: (FleetStore, MinerDevice) throws -> Void) throws {
        let suite = "app.hashfleet.mac.tuningAndHub.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        store.loadDemo()
        let device = try #require(store.devices.first)
        try run(store, device)
    }

    /// Mount controls in their navigation context, without ordering a window on screen.
    private func evaluate<V: View>(_ view: V, inspect: (NSView) -> Void = { _ in }) {
        let bounds = NSRect(x: 0, y: 0, width: 680, height: 1800)
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: NavigationStack { view })
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        inspect(host)
        window.contentView = nil
    }

    private func values(in view: NSView, placeholder: String) -> [String] {
        if let field = view as? NSTextField, field.placeholderString == placeholder { return [field.stringValue] }
        return view.subviews.flatMap { values(in: $0, placeholder: placeholder) }
    }

    private func info(slots: Int = 2) -> MinerInfo {
        let pools: [JSONValue] = (0..<slots).map { index in
            .object(["id": .integer(Int64(index)), "stratumURL": .string("slot\(index).example"),
                     "stratumPort": .integer(3333), "stratumUser": .string("worker.\(index)")])
        }
        return MinerInfo(raw: [
            "hostname": .string("bench"), "version": .string(NumberFirstPreview.sampleFirmwareVersion),
            "hashRate": .number(900), "temp": .integer(52), "statsFrequency": .integer(30),
            "frequency": .integer(550), "coreVoltage": .integer(1100),
            "actualFrequency": .integer(548), "coreVoltageActual": .integer(1090),
            "rotation": .integer(90), "invertscreen": .bool(true), "displayTimeout": .integer(12),
            "autofanspeed": .bool(true), "temptarget": .integer(55),
            "stratumURL": .string("primary.example"), "fallbackStratumURL": .string("fallback.example"),
            "primaryPoolIndex": .integer(1), "secondaryPoolIndex": .integer(0), "pools": .array(pools.reversed())
        ])
    }

    @Test func tuningRouteAndEditablePreview() throws {
        try withDemo { store, device in
            let info = info()
            store.snapshots[device.id]?.info = info
            // macOS intentionally routes to the session editor. Host the compact preview explicitly as well.
            evaluate(MinerTuningPreviewRoute(device: device, store: store, insights: nil))
            for mode in FleetPreferences.DashboardMode.allCases {
                store.preferences.dashboardMode = mode
                let preview = MinerTuningPreview(mode: mode, device: device, store: store, info: info,
                                                 isDemo: true, canEdit: true, insights: nil)
                #expect(preview.readings.clock == 548)
                #expect(preview.readings.voltage == 1090)
                evaluate(preview.environment(\.dynamicTypeSize, mode == .essentials ? .accessibility2 : .large)) { host in
                    // Draft inputs use configured values, not the two measured values in the header.
                    #expect(Set(values(in: host, placeholder: "Value")) == ["550", "1100"])
                }
            }
        }
    }

    @Test func readOnlyAndUnreportedTuningHaveNoEditors() throws {
        try withDemo { store, device in
            for (sample, editable) in [(info(), false), (MinerInfo(raw: [:]), true)] {
                let preview = MinerTuningPreview(mode: .full, device: device, store: store, info: sample,
                                                 isDemo: true, canEdit: editable, insights: nil)
                evaluate(preview) { host in #expect(values(in: host, placeholder: "Value").isEmpty) }
            }
        }
    }

    @Test func tuningReviewShowsOnlyChangedFields() throws {
        var draft = MinerTuningPreviewDraft(info: info())
        #expect(draft.review == nil)
        draft.edit(.frequency, "551")
        let request = try #require(draft.review)
        #expect(request.changes.map(\.field) == [.frequency])
        #expect(request.payload["coreVoltage"] == nil)
        evaluate(MinerTuningPreviewReview(request: request, canConfirm: true, isLive: false, attemptMessage: nil) {})
    }

    @Test func compactHubWithControlsRestartAndDiagnostics() throws {
        try withDemo { store, device in
            let info = info()
            store.snapshots[device.id]?.info = info
            let settings = MinerSettingsView(device: device, store: store)
            let supported = MinerNumberFirstAvailability(info: info, infoStatus: .supported, settingsStatus: .supported,
                                                         firmwareStatus: .supported, actionStatuses: [.restart: .supported])
            #expect(supported.settingsCategories() == [.general, .pools, .display, .cooling, .tuning])
            #expect(supported.quickActions == [.restart])
            // Essentials embeds the restart button. Full uses a review link and exposes the Tools group.
            for mode in FleetPreferences.DashboardMode.allCases {
                store.preferences.dashboardMode = mode
                evaluate(settings.compactSettingsHub(supported))
            }
            let unchecked = MinerNumberFirstAvailability(info: info, infoStatus: .notChecked,
                                                         settingsStatus: .notChecked, firmwareStatus: .notChecked)
            evaluate(settings.compactSettingsHub(unchecked))
        }
    }

    @Test func poolEditorLoadsPrimarySlotByID() throws {
        try withDemo { store, device in
            store.snapshots[device.id]?.info = info()
            let settings = MinerSettingsView(device: device, store: store, initialCategory: .pools)
            #expect(settings.poolInventory.firstEmptySlot == 2)
            #expect(settings.poolSlotTitle(7) == "Slot 7")
            evaluate(settings) { host in
                #expect(values(in: host, placeholder: "Stratum server") == ["slot1.example"])
                #expect(values(in: host, placeholder: "User / worker") == ["worker.1"])
            }
        }
    }

    @Test func poolPresetsWithFullAndUnknownInventories() throws {
        try withDemo { store, device in
            let settings = MinerSettingsView(device: device, store: store, initialCategory: .pools)
            store.snapshots[device.id]?.info = info(slots: 8)
            #expect(settings.poolInventory.availability == .full)
            evaluate(settings)
            store.snapshots[device.id]?.info = MinerInfo(raw: ["hostname": .string("legacy")])
            #expect(settings.poolInventory.availability == .unknown)
            evaluate(settings)
        }
    }

    @Test func displaySettingsLoadReportedTimeout() throws {
        try withDemo { store, device in
            store.snapshots[device.id]?.info = info()
            let settings = MinerSettingsView(device: device, store: store, initialCategory: .display)
            evaluate(settings) { host in
                #expect(values(in: host, placeholder: "Display timeout (minutes)") == ["12"])
            }
        }
    }

    @Test func directSaveRejectsRiskyKeysEvenWhenMixedWithSafeOnes() {
        let safe: JSONValue = .object(["hostname": .string("bench"), "rotation": .integer(90), "invertscreen": .bool(false),
                                      "displayTimeout": .integer(5), "statsFrequency": .integer(30)])
        #expect(MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: safe))
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .restart, payload: safe))
        for unsafe in ["frequency", "coreVoltage", "autofanspeed", "temptarget", "stratumPassword", "unknown"] {
            let mixed: JSONValue = .object(["hostname": .string("bench"), unsafe: .integer(1)])
            #expect(!MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: mixed))
        }
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: .object([:])))
        #expect(!MinerDirectSavePolicy.qualifies(endpoint: .settings, payload: .array([])))
    }

    @Test func displayReadbackNeedsTheRequestedValue() {
        let reported = info()
        #expect(MinerDisplaySetting.colors.matches(.object(["invertscreen": .integer(1)]), in: reported))
        #expect(!MinerDisplaySetting.colors.matches(.object(["invertscreen": .bool(false)]), in: reported))
        #expect(MinerDisplaySetting.rotation.matches(.object(["rotation": .integer(90)]), in: reported))
        #expect(!MinerDisplaySetting.timeout.matches(.object(["displayTimeout": .integer(5)]), in: reported))
        #expect(!MinerDisplaySetting.timeout.matches(.object([:]), in: reported))
        #expect(!MinerDisplaySetting.timeout.matches(.object(["displayTimeout": .integer(0)]), in: MinerInfo(raw: [:])))
    }
}
