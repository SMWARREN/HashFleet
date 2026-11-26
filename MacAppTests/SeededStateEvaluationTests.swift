import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

#if DEBUG
/// Hosts views in DEBUG-only seeded states that no other evaluation reaches: tuning review and
/// advanced disclosure, cooling failure, add-miner validation and discovery errors, and developer
/// support in direct distribution. Every view is laid out off-screen. No request is sent and no
/// socket is opened.
@Suite("Seeded state evaluation", .serialized)
@MainActor
struct SeededStateEvaluationTests {
    private func makeStore(demo: Bool) -> (FleetStore, UserDefaults, String) {
        let suite = "app.hashfleet.mac.seeded.\(UUID().uuidString)"
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

    private func fields() -> [String: JSONValue] {
        [
            "hostname": .string("Rig"), "firmwareFamily": .string("bitaxe"),
            "ASICModel": .string("BM1370"), "deviceModel": .string("Gamma"),
            "version": .string("2.12.0"), "macAddr": .string("aa:bb:cc:dd:ee:ff"),
            "frequency": .number(525), "coreVoltage": .number(1060),
            "temp": .number(62), "vrTemp": .number(55), "power": .number(14),
            "fanspeed": .number(60), "manualFanSpeed": .number(60), "minFanSpeed": .number(20),
            "autofanspeed": .bool(false), "temptarget": .number(65),
            "hashRate": .number(900), "expectedHashrate": .number(950),
            "sharesAccepted": .integer(120), "sharesRejected": .integer(2),
            "uptimeSeconds": .integer(3600), "wifiRSSI": .integer(-55)
        ]
    }

    private func info(_ raw: [String: JSONValue]) -> MinerInfo { MinerInfo(raw: raw) }

    private func snapshot(_ info: MinerInfo) -> MinerSnapshot {
        MinerSnapshot(
            info: info, previousInfo: nil, error: nil, updatedAt: Date(),
            completeSnapshotAt: Date(), powerObservedAt: Date(),
            history: [], isCached: false, isReconnecting: false
        )
    }

    private func makeDevice(_ store: FleetStore) -> MinerDevice {
        let miner = MinerDevice(name: "Rig", address: "192.168.1.40", kind: .espMiner, firmwareFamily: "bitaxe")
        store.devices = [miner]
        store.snapshots[miner.id] = snapshot(info(fields()))
        return miner
    }

    // MARK: - MinerTuningPreview seeded states

    @Test func evaluateTuningPreviewSeededStates() {
        let (store, defaults, suite) = makeStore(demo: false)
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = makeDevice(store)
        let minerInfo = info(fields())

        // Editable draft with an error and a status message.
        evaluate(MinerTuningPreview(
            mode: .full, device: miner, store: store, info: minerInfo, isDemo: false,
            canEdit: true, insights: nil, error: "Frequency is outside the allowed range.",
            statusMessage: "Draft saved locally."
        ))
        // Read-only preview, demo mode, essentials layout.
        evaluate(MinerTuningPreview(
            mode: .essentials, device: miner, store: store, info: minerInfo, isDemo: true,
            canEdit: false, insights: nil
        ))
        // Inline and full advanced disclosures.
        evaluate(MinerTuningPreview(
            mode: .full, device: miner, store: store, info: minerInfo, isDemo: false,
            canEdit: true, insights: nil, showsInlineAdvanced: true, showsFullAdvanced: true
        ))
        // Applied result and a pending review, both with payloads.
        let change = MinerTuningPreviewDraft.Change(field: .frequency, old: 525, new: 550)
        let review = MinerTuningPreviewDraft.Review(
            changes: [change], payload: .object(["frequency": .number(550)])
        )
        evaluate(MinerTuningPreview(
            mode: .full, device: miner, store: store, info: minerInfo, isDemo: false,
            canEdit: true, insights: nil, applied: review, review: review
        ))
        // Voltage change for the second field.
        let voltage = MinerTuningPreviewDraft.Review(
            changes: [MinerTuningPreviewDraft.Change(field: .coreVoltage, old: 1060, new: 1080)],
            payload: .object(["coreVoltage": .number(1080)])
        )
        evaluate(MinerTuningPreview(
            mode: .full, device: miner, store: store, info: minerInfo, isDemo: false,
            canEdit: true, insights: nil, review: voltage
        ))
    }

    // MARK: - MinerCoolingPreview failure state

    @Test func evaluateCoolingPreviewFailureState() {
        let minerInfo = info(fields())
        evaluate(MinerCoolingPreview(
            mode: .full, info: minerInfo, canEdit: true, live: nil, failure: "The miner rejected the fan change."
        ))
        evaluate(MinerCoolingPreview(
            mode: .essentials, info: minerInfo, canEdit: false, live: nil, failure: nil
        ))
        evaluate(MinerCoolingPreview(
            mode: .full, info: nil, canEdit: true, live: nil, failure: "Telemetry unavailable."
        ))
    }

    // MARK: - AddMinerView seeded states

    @Test func evaluateAddMinerSeededStates() {
        let (store, defaults, suite) = makeStore(demo: false)
        defer { defaults.removePersistentDomain(forName: suite) }

        // Validation error with a populated name, address and token.
        evaluate(AddMinerView(
            store: store, name: "Rig", address: "192.168.1.50", bearerToken: "token",
            validationError: "Could not reach the miner at that address."
        ))
        // Discovery failure surfaced on the add flow.
        evaluate(AddMinerView(
            store: store, discoveryAddError: "This miner is already in the fleet."
        ))
        // Validating and "find this Mac" in progress.
        evaluate(AddMinerView(store: store, isValidating: true, isFindingThisMac: true))
        // Manual input expanded, with addresses already added during bulk flow.
        evaluate(AddMinerView(
            store: store, minerKind: .xmrig, isManualExpanded: true,
            addedAddresses: ["192.168.1.60", "192.168.1.61"]
        ))
    }

    // MARK: - Developer support in direct distribution

    @Test func evaluateDeveloperSupportDirectDistributionSection() {
        let availability = DeveloperSupportAvailability(currentCountryCode: { nil })
        availability.directDistributionForTesting = true
        evaluate(DeveloperSupportSection(showsUnavailableMessage: true, availability: availability))
        evaluate(DeveloperSupportSection(showsUnavailableMessage: false, availability: availability))
    }

    // MARK: - Reviewed cooling page for xmrig devices (usesCoolingPreview == false)

    @Test func evaluateReviewedCoolingPageForXmrigDevice() {
        let (store, defaults, suite) = makeStore(demo: false)
        defer { defaults.removePersistentDomain(forName: suite) }
        let xmrig = MinerDevice(name: "Xmrig Rig", address: "192.168.1.70", kind: .xmrig, firmwareFamily: "xmrig")
        store.devices = [xmrig]
        store.snapshots[xmrig.id] = snapshot(info(fields()))
        evaluate(MinerSettingsView(device: xmrig, store: store, initialCategory: .cooling))
        evaluate(MinerSettingsView(device: xmrig, store: store, initialCategory: .cooling), width: 420, height: 1400)
    }

    // MARK: - LocalNetworkAuthorization status transitions (no browser or listener started)

    @Test func evaluateLocalNetworkAuthorizationStatusTransitions() {
        let authorization = LocalNetworkAuthorization(defaults: UserDefaults(suiteName: "app.hashfleet.mac.lna.\(UUID().uuidString)")!)
        #expect(authorization.status == .notRequested)
        #expect(!authorization.isGranted)
        authorization.markDenied()
        #expect(authorization.status == .denied)
        #expect(!authorization.isGranted)
        authorization.cancel()
        #expect(LocalNetworkAuthorization.isPolicyDenied(.dns(-65570)))
        #expect(!LocalNetworkAuthorization.isPolicyDenied(.dns(-1)))
        #expect(!LocalNetworkAuthorization.isPolicyDenied(.posix(.ECONNREFUSED)))
    }
}
#endif
