import SwiftUI
import Testing
import HashFleetCore
@testable import HashFleet

/// Measures the runtime type name of the real production `DashboardView.body`.
///
/// Context: the November 7, 2026 physical iPhone scene-create watchdog report had a main-thread
/// sample with 160 of 328 frames in the Swift demangler under `swift_getTypeName`. The dashboard
/// carries the longest `fleetPagePresentation` chain in the app, so its body type is the most
/// relevant real type to measure.
///
/// What this observes: `_typeName` of the real `DashboardView.Body` generic type, and of the
/// value of `body` read once from a real instance built on an isolated store (unique preference
/// suite, ephemeral deny-all `URLProtocol` session shared with `FleetStore` and
/// `MiningInsightsStore`, no add/persist, no demo load, no App Group or standard-suite state).
/// The instance is never mounted, so no `.task`, `onAppear` or network request runs. This file is
/// self-contained: it deliberately does not depend on the large render harness.
///
/// Observed natively at 5d5a5ba (not assumed): the static metadata name of `DashboardView.Body`
/// is a 63 byte opaque placeholder, while the runtime instance body is an expanded 910 byte
/// `GeometryReader<ModifiedContent<...AnyView...>>`. The two spellings therefore differ. An earlier
/// version of this test asserted that they were equal. That was an invalid assumption about
/// opaque result types, not an application regression, and it has been replaced by the explicit
/// runtime scope checks below. Both names and sizes are still recorded as diagnostics.
///
/// Limitations, recorded deliberately:
/// - The checks apply to the runtime instance name only. They do not establish that every opaque
///   `some View` helper used inside the body (for example `dashboardContent(viewport:)`) is
///   expanded in that name, and they say nothing about the rendered view graph.
/// - It is not scene-create timing and not physical-device acceptance.
/// - The 4096 byte budget is 4.5 times the one native measurement (910 bytes). It is a regression
///   tripwire for this one observation, not a derived safe limit. Re-measure before relying on it
///   after intentional dashboard changes.
@Suite("Dashboard type boundary")
@MainActor
struct FleetDashboardTypeBoundaryTests {
    /// 4.5 times the measured 910 byte runtime instance name. The pre-d1f39b2 decoration shape
    /// reached 1.65 MB after only 11 presentations around a trivial leaf, so a regression of the
    /// same kind would exceed this by orders of magnitude.
    private static let instanceByteBudget = 4_096

    private final class DenyAllProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
        override func stopLoading() {}
    }

    /// Unique preferences suite and one deny-all session shared by both stores.
    @MainActor
    private final class IsolatedStores {
        let suite = "app.hashfleet.tests.dashboard-type.\(UUID().uuidString)"
        let defaults: UserDefaults
        let session: URLSession
        let store: FleetStore
        let insights: MiningInsightsStore

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DenyAllProtocol.self]
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 1
            session = URLSession(configuration: configuration)
            store = FleetStore(defaults: defaults, session: session)
            insights = MiningInsightsStore(session: session, cooldown: 0)
            store.preferences.externalDataEnabled = false
            store.preferences.realtimeMonitoring = false
        }

        func cleanup() {
            let probes = store.capabilities.cancelAll()
            store.cancelRefresh()
            insights.cancel()
            let session = session
            Task {
                for probe in probes { _ = await probe.result }
                session.invalidateAndCancel()
            }
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private static func bytes(_ name: String) -> Int { name.utf8.count }

    @Test("Real DashboardView body type name stays far below un-erased growth")
    func dashboardBodyTypeNameIsBounded() throws {
        let fixture = try IsolatedStores()
        defer { fixture.cleanup() }

        // Metadata only: no instance, no State, no AppStorage, no side effects. Diagnostic only.
        let staticName = _typeName(DashboardView.Body.self, qualified: true)

        // Real instance on the isolated stores. Reading `body` constructs a value and never mounts it.
        let dashboard = DashboardView(store: fixture.store, insights: fixture.insights)
        let instanceName = _typeName(type(of: dashboard.body), qualified: true)

        let staticBytes = Self.bytes(staticName)
        let instanceBytes = Self.bytes(instanceName)
        let report = """
            FLEET_TYPE_BOUNDARY dashboardBodyStaticTypeNameBytes=\(staticBytes)
            FLEET_TYPE_BOUNDARY dashboardBodyInstanceTypeNameBytes=\(instanceBytes)
            FLEET_TYPE_BOUNDARY instanceBudgetBytes=\(Self.instanceByteBudget)
            """
        print(report)
        Attachment.record(report, named: "dashboard-body-type-name-bytes.txt")
        Attachment.record(String(staticName.prefix(4_096)), named: "dashboard-body-static-type-name-prefix.txt")
        Attachment.record(String(instanceName.prefix(4_096)), named: "dashboard-body-instance-type-name-prefix.txt")

        // Runtime scope checks on the INSTANCE name. The static name is a diagnostic and is not
        // required to have the same spelling.
        #expect(!instanceName.isEmpty)
        #expect(instanceName.hasPrefix("SwiftUI.GeometryReader<"), "instance name: \(instanceName.prefix(200))")
        #expect(instanceName.contains("SwiftUI.AnyView"), "The AnyView boundary must appear in the runtime body type")
        #expect(instanceBytes < Self.instanceByteBudget, "DashboardView instance body type name was \(instanceBytes) bytes")
        #expect(fixture.store.devices.isEmpty, "The isolated stores must not have loaded any miners")
    }
}
