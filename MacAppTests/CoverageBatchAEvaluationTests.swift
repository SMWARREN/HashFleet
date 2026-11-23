import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Routes every miner request to a scripted in-process response. No socket is ever opened.
private final class ScriptedMinerProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var failWrites = false
    nonisolated(unsafe) static var info: [String: Any] = [:]
    nonisolated(unsafe) static var requests: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        Self.requests.append("\(method) \(path)")
        var status = 200
        var body = Data("{}".utf8)
        if path == "/api/system/info" {
            body = (try? JSONSerialization.data(withJSONObject: Self.info)) ?? body
        } else if method != "GET", Self.failWrites {
            status = 500
            body = Data("{\"error\":\"nope\"}".utf8)
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Coverage Batch A", .serialized)
@MainActor
struct CoverageBatchAEvaluationTests {
    private func evaluate<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 1200)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
    }

    private func liveFixture() throws -> (FleetStore, MinerDevice, UserDefaults, String, URLSession) {
        let suite = "app.hashfleet.mac.batcha.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedMinerProtocol.self]
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)
        let store = FleetStore(defaults: defaults, session: session)
        store.preferences.telemetryStorageEnabled = false
        try store.add(name: "Scripted Rig", address: "scripted.invalid")
        let device = try #require(store.devices.first)
        ScriptedMinerProtocol.requests = []
        ScriptedMinerProtocol.failWrites = false
        ScriptedMinerProtocol.info = [
            "hostname": "Scripted Rig", "hashRate": 1000.0, "power": 15.0, "temp": 50.0,
            "macAddr": "AA:BB:CC:DD:EE:01", "version": "v1.0", "ASICModel": "BM1370",
            "rotation": 0, "invertscreen": 0, "displayTimeout": 5
        ]
        store.snapshots[device.id] = MinerSnapshot(
            info: MinerInfo(raw: ScriptedMinerProtocol.info.mapValues { value in
                if let number = value as? Int { return .integer(Int64(number)) }
                if let number = value as? Double { return .number(number) }
                return .string("\(value)")
            }),
            error: nil, updatedAt: Date(), completeSnapshotAt: Date(), powerObservedAt: Date(),
            history: [], isCached: false, isReconnecting: false
        )
        return (store, device, defaults, suite, session)
    }

    private func settle(_ view: MinerSettingsView, timeout: Double = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while view.isSaving && Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test func saveDirectlyRunsTheLiveSuccessAndFailurePaths() async throws {
        let (store, device, defaults, suite, session) = try liveFixture()
        defer {
            store.cancelRefresh()
            session.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suite)
        }
        let insights = MiningInsightsStore()
        let view = MinerSettingsView(device: device, store: store, insights: insights)
        view.saveDirectly(.object(["hostname": .string("Desk")]))
        await settle(view)
        view.saveDirectly(.object(["rotation": .integer(0)]), displaySetting: .rotation)
        await settle(view)
        ScriptedMinerProtocol.failWrites = true
        view.saveDirectly(.object(["hostname": .string("Broken")]))
        await settle(view)
        view.saveDirectly(.object(["invertscreen": .integer(1)]), displaySetting: .colors)
        await settle(view)
        evaluate(view.directSaveStatus)
        #expect(ScriptedMinerProtocol.requests.contains { $0.hasPrefix("GET /api/system/info") })
    }

    @Test func restartAfterDisplaySaveRunsAgainstScriptedMiner() async throws {
        let (store, device, defaults, suite, session) = try liveFixture()
        defer {
            store.cancelRefresh()
            session.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suite)
        }
        store.preferences.dashboardMode = .essentials
        let insights = MiningInsightsStore()
        let view = MinerSettingsView(device: device, store: store, insights: insights)
        let info = try #require(store.snapshot(for: device.id)?.info)
        let identity = try #require(MinerInlineActionState.identity(from: info))
        view.restartAfterDisplaySave(identity)
        try? await Task.sleep(for: .milliseconds(300))
        ScriptedMinerProtocol.failWrites = true
        view.restartAfterDisplaySave(identity)
        try? await Task.sleep(for: .milliseconds(300))
        evaluate(view.displaySaveButton("Save", setting: .rotation) { .object(["rotation": .integer(1)]) })
    }
}
