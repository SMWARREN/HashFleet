import Foundation
import Testing
@testable import HashFleetMac

@Suite("Native demo public-data isolation")
@MainActor
struct FleetNativeDemoChainTests {
    @Test func localFixturesDoNotOverrideTheRealPublicDataPreference() {
        #expect(FleetChainDataPolicy.canDisplay(isDemo: true, externalDataEnabled: false))
        #expect(FleetChainDataPolicy.canDisplay(isDemo: true, externalDataEnabled: true))
        #expect(!FleetChainDataPolicy.canDisplay(isDemo: false, externalDataEnabled: false))
        #expect(FleetChainDataPolicy.canDisplay(isDemo: false, externalDataEnabled: true))
    }

    @Test func demoRefreshSucceedsWithAllNetworkRequestsRejected() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RejectDemoNetworkRequests.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let insights = MiningInsightsStore(session: session)
        insights.setDemo(true)
        await insights.refresh(force: true)
        #expect(insights.isDemo)
        #expect(insights.network?.mining.value != nil)
        #expect(insights.network?.mining.error == nil)
        #expect(insights.network?.price.value != nil)
        #expect(insights.network?.price.error == nil)
    }
}

private final class RejectDemoNetworkRequests: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
