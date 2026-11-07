import Foundation
import SwiftUI
import Testing
import HashFleetCore
@testable import HashFleet

/// Exercises the real public store API and mounted production views. The protocol claims every
/// request, supplies only local fixture responses, and fails closed for all other destinations.
/// No buttons, browsers, miner endpoints, shared preferences, or real wallet secrets are used.
@Suite(.serialized)
@MainActor
struct PoolLookupSourceRenderingCoverageTests {
    enum LookupState: CaseIterable, Sendable {
        case found, sparse, notFound, unavailable, malformed
    }

    enum SourceState: CaseIterable, Sendable {
        case fresh, stale, sourceTimestamp, sparse, unavailable, malformed, demo
    }

    @Test(arguments: LookupState.allCases)
    func explicitLookupRendersParsedAccountOrHonestFailure(_ state: LookupState) async throws {
        let fixture = PoolSourceRenderFixture()
        defer { fixture.cleanup() }
        prepareLookup(state, fixture: fixture)
        await fixture.insights.lookup(address: PoolSourceRenderFixture.publicTestAddress)
        let result = try #require(fixture.insights.userLookup)
        switch (state, result) {
        case (.found, .found(let account)):
            #expect(account.value?.workers == 7)
            #expect(account.value?.hashrate1HourHPS == 2e12)
            #expect(account.value?.shares == 42)
            #expect(account.sourceTimestamp == nil, "Last share is not a provider snapshot timestamp")
        case (.sparse, .found(let account)):
            #expect(account.value?.workers == 7)
            #expect(account.value?.hashrate1HourHPS == nil)
        case (.notFound, .notFound): break
        case (.unavailable, .failed(.http(statusCode: 503))): break
        case (.malformed, .failed(.invalidData)): break
        default: Issue.record("Lookup state did not match the actual parsed response")
        }
        let rendered = try await FleetViewRenderHarness.render(NavigationStack {
            CKPoolLookupView(insights: fixture.insights)
                .environment(\.scenePhase, .active)
        }, width: 600, height: 2_000)
        #expect(rendered.visibleText.contains("Your side of the pool"))
        #expect(rendered.visibleText.contains("No wallet balance or expected payout is inferred."))
        #expect(!rendered.visibleText.contains("FIXTURE_BODY_MUST_NOT_RENDER"))
        // Programmatic lookup never populates the view's private submitted-address field.
        #expect(!rendered.visibleText.contains(PoolSourceRenderFixture.publicTestAddress))
        switch state {
        case .found:
            #expect(rendered.visibleText.contains("CKPool account"))
            #expect(rendered.visibleText.contains("Pool-reported shares"))
            #expect(rendered.recognizesMetric("2.00", unit: "TH/s"))
            #expect(!rendered.visibleText.contains("Lookup unavailable"))
        case .sparse:
            #expect(rendered.visibleText.contains("CKPool account"))
            #expect(rendered.visibleText.contains("Not reported"))
            #expect(!rendered.visibleText.contains("0.00 TH/s"))
        case .notFound:
            #expect(rendered.visibleText.contains("No CKPool statistics found for this address."))
            #expect(rendered.visibleText.contains("does not mean your miner or another pool is offline"))
            #expect(!rendered.visibleText.contains("CKPool account"))
        case .unavailable:
            #expect(rendered.visibleText.contains("Lookup unavailable"))
            #expect(rendered.visibleText.contains("HTTP 503"))
            #expect(!rendered.visibleText.contains("No CKPool statistics found"))
        case .malformed:
            #expect(rendered.visibleText.contains("Lookup unavailable"))
            #expect(rendered.visibleText.contains("did not return recognizable, valid statistics"))
        }
        #expect(PoolSourceRenderProtocol.state.requests.count == 1)
        #expect(PoolSourceRenderProtocol.state.requests.first?.url?.path ==
                "/users/\(PoolSourceRenderFixture.publicTestAddress)")
        #expect(fixture.insights.network == nil && fixture.insights.pool == nil)
        fixture.assertReadOnlyRequests()
    }

    @Test(arguments: [false, true])
    func invalidInputAndDemoNeverIssueALookup(_ demo: Bool) async throws {
        let fixture = PoolSourceRenderFixture()
        defer { fixture.cleanup() }
        fixture.insights.setDemo(demo)
        await fixture.insights.lookup(address: demo ? PoolSourceRenderFixture.publicTestAddress : "not-an-address")
        if demo {
            #expect(fixture.insights.userLookup == nil)
        } else {
            #expect(fixture.insights.userLookup == .failed(.invalidBitcoinAddress))
        }
        let rendered = try await FleetViewRenderHarness.render(NavigationStack {
            CKPoolLookupView(insights: fixture.insights)
                .environment(\.scenePhase, .active)
        }, width: 600, height: 1_400)
        if demo {
            #expect(rendered.visibleText.contains("Address lookup is disabled in demo. No address is sent."))
        } else {
            #expect(rendered.visibleText.contains("Lookup unavailable"))
            #expect(rendered.visibleText.contains("Enter a valid Bitcoin mainnet address only."))
        }
        #expect(PoolSourceRenderProtocol.state.requests.isEmpty)
    }

    @Test(arguments: SourceState.allCases)
    func poolSummaryKeepsSourceAgeMissingFieldsAndFailuresDistinct(_ state: SourceState) async throws {
        let fixture = PoolSourceRenderFixture()
        let fleet = try FleetRenderFixture()
        defer { fixture.cleanup(); fleet.cleanup() }
        prepareSummary(state, fixture: fixture)
        fixture.insights.setDemo(state == .demo)
        await fixture.insights.refresh()
        let result = try #require(fixture.insights.pool)
        let now = result.fetchedAt.addingTimeInterval(state == .stale ? 301 : 0)
        let view = NetworkInsightsView(fleet: fleet.store, insights: fixture.insights)
        // Mount the production card itself, not NetworkInsightsView's automatic refresh task.
        let rendered = try await FleetViewRenderHarness.render(view.poolCard(result, now: now), width: 600, height: 900)
        #expect(rendered.visibleText.contains("CKPool"))
        #expect(rendered.visibleText.contains("public pool"))
        #expect(!rendered.visibleText.contains("FIXTURE_BODY_MUST_NOT_RENDER"))
        if state == .unavailable || state == .malformed {
            #expect(result.value == nil)
            #expect(rendered.visibleText.contains("Unavailable"))
            #expect(rendered.visibleText.contains("Failed attempt"))
            #expect(!rendered.visibleText.contains("Pool-wide estimates"))
            let expected: MiningInsightsError = state == .unavailable ? .http(statusCode: 503) : .invalidData
            #expect(result.error == expected)
        } else {
            #expect(result.value != nil && result.error == nil)
            #expect(rendered.visibleText.contains("Pool-wide estimates, not your miner's local hashrate or a payout balance."))
            #expect(!rendered.visibleText.contains("Failed attempt"))
            if state == .sparse {
                #expect(result.value?.users == nil && result.value?.hashrate1HourHPS == nil)
                #expect(rendered.visibleText.contains("Not reported"))
            }
        }
        if state == .demo {
            #expect(rendered.visibleText.contains("Sample data"))
            #expect(rendered.visibleText.contains("not live"))
            #expect(!rendered.visibleText.contains("Source:"))
            #expect(!rendered.visibleText.contains("Fetched"))
            #expect(PoolSourceRenderProtocol.state.requests.isEmpty)
        } else {
            #expect(rendered.visibleText.contains("Source: raw.stats.ckpool.org"))
            #expect(rendered.visibleText.contains("Fetched"))
            #expect(rendered.visibleText.contains("Stale") == (state == .stale || state == .sourceTimestamp))
            #expect(rendered.visibleText.contains("Source time:") == (state == .sourceTimestamp))
            if state == .sourceTimestamp {
                #expect(result.sourceTimestamp == Date(timeIntervalSince1970: 1_700_000_000))
            }
            #expect(!PoolSourceRenderProtocol.state.requests.contains { $0.url?.path.hasPrefix("/users/") == true })
            #expect(PoolSourceRenderProtocol.state.requests.filter { $0.url?.path == "/pool/pool.status" }.count == 1)
        }
        fixture.assertReadOnlyRequests()
    }

    private func prepareLookup(_ state: LookupState, fixture: PoolSourceRenderFixture) {
        switch state {
        case .found:
            let body = #"{"workers":7,"hashrate5m":"3T","hashrate1hr":"2T","hashrate1d":"1T","hashrate7d":"4T","shares":42,"# +
                #""bestshare":5000,"bestever":9000,"lastshare":1700000000}"#
            fixture.respond(body: body)
        case .sparse:
            fixture.respond(body: #"{"workers":7}"#)
        case .notFound:
            fixture.respond(status: 404, body: #"{"private_body":"FIXTURE_BODY_MUST_NOT_RENDER"}"#)
        case .unavailable:
            fixture.respond(status: 503, body: #"{"private_body":"FIXTURE_BODY_MUST_NOT_RENDER"}"#)
        case .malformed:
            fixture.respond(body: #"{"unrecognized":"FIXTURE_BODY_MUST_NOT_RENDER"}"#)
        }
    }

    private func prepareSummary(_ state: SourceState, fixture: PoolSourceRenderFixture) {
        switch state {
        case .sourceTimestamp:
            fixture.respond(body: #"{"Users":5,"Workers":7,"hashrate1hr":"12P","lastupdate":1700000000}"#)
        case .sparse:
            fixture.respond(body: #"{"Workers":7}"#)
        case .unavailable:
            fixture.respond(status: 503, body: "FIXTURE_BODY_MUST_NOT_RENDER")
        case .malformed:
            fixture.respond(body: "FIXTURE_BODY_MUST_NOT_RENDER")
        case .fresh, .stale, .demo:
            fixture.respond(body: #"{"Users":5,"Workers":7,"hashrate1hr":"12P","hashrate1d":"11P"}"#)
        }
    }

    @Test func failedRefreshReplacesSuccessfulPoolReadingInsteadOfRelabelingItFresh() async throws {
        let fixture = PoolSourceRenderFixture()
        let fleet = try FleetRenderFixture()
        defer { fixture.cleanup(); fleet.cleanup() }
        fixture.respond(body: #"{"Workers":7,"hashrate1hr":"12P"}"#)
        await fixture.insights.refresh()
        #expect(fixture.insights.pool?.value?.hashrate1HourHPS == 12e15)
        let view = NetworkInsightsView(fleet: fleet.store, insights: fixture.insights)
        let successful = try #require(fixture.insights.pool)
        let previous = try await FleetViewRenderHarness.render(view.poolCard(successful, now: successful.fetchedAt))
        #expect(previous.visibleText.contains("12.00 PH/s"))
        fixture.respond(status: 503, body: "FIXTURE_BODY_MUST_NOT_RENDER")
        await fixture.insights.refresh(force: true)
        let failed = try #require(fixture.insights.pool)
        #expect(failed.value == nil && failed.error == .http(statusCode: 503))
        let rendered = try await FleetViewRenderHarness.render(view.poolCard(failed, now: failed.fetchedAt))
        #expect(rendered.visibleText.contains("Unavailable"))
        #expect(rendered.visibleText.contains("HTTP 503"))
        #expect(rendered.visibleText.contains("Failed attempt"))
        #expect(!rendered.visibleText.contains("12.00 PH/s"))
        #expect(rendered.pngData != previous.pngData)
        fixture.assertReadOnlyRequests()
    }
}

@MainActor
private final class PoolSourceRenderFixture {
    // Public checksum-valid documentation fixture already used throughout the repository.
    // No key, wallet ownership, balance, miner configuration or real account data is involved.
    static let publicTestAddress = "1BoatSLRHtKNngkdXEeobR76b53LETtpyT"
    let session: URLSession
    let insights: MiningInsightsStore

    init() {
        PoolSourceRenderProtocol.state.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PoolSourceRenderProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 2
        session = URLSession(configuration: configuration)
        insights = MiningInsightsStore(session: session, cooldown: 0)
    }

    func respond(status: Int = 200, body: String) {
        PoolSourceRenderProtocol.state.setResponse(status: status, body: body)
    }

    func assertReadOnlyRequests() {
        #expect(PoolSourceRenderProtocol.state.requests.allSatisfy {
            $0.httpMethod == "GET" && $0.httpBody == nil && $0.url?.scheme == "https" &&
            $0.value(forHTTPHeaderField: "Authorization") == nil &&
            $0.value(forHTTPHeaderField: "Cookie") == nil
        })
    }

    func cleanup() {
        insights.cancel()
        session.invalidateAndCancel()
    }
}

/// This private state is used only by the serialized suite above, never by other fixture classes.
private final class PoolSourceRenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var journal: [URLRequest] = []
    private var response: (Int, String) = (503, "")
    var requests: [URLRequest] { lock.withLock { journal } }
    func reset() { lock.withLock { journal = []; response = (503, "") } }
    func setResponse(status: Int, body: String) { lock.withLock { response = (status, body) } }
    func record(_ request: URLRequest) -> (Int, String) {
        lock.withLock { journal.append(request); return response }
    }
}

private final class PoolSourceRenderProtocol: URLProtocol, @unchecked Sendable {
    static let state = PoolSourceRenderState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.state.record(request)
        guard let url = request.url, request.httpMethod == "GET", url.scheme == "https",
              url.host == "raw.stats.ckpool.org",
              url.path == "/pool/pool.status" || url.path.hasPrefix("/users/"),
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
