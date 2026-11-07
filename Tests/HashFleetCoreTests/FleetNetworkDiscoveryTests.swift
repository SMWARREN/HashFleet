import Foundation
import XCTest
@testable import HashFleetCore

final class FleetNetworkDiscoveryTests: XCTestCase {
    func testScanPlanIsBoundedAndSkipsLocalAddress() {
        let plan = FleetDiscoveryScanPlan.plan(forIPv4Address: "192.168.1.42")

        XCTAssertEqual(plan?.localAddress, "192.168.1.42")
        XCTAssertEqual(plan?.hosts.count, 253)
        XCTAssertEqual(plan?.hosts.first, "192.168.1.1")
        XCTAssertEqual(plan?.hosts.last, "192.168.1.254")
        XCTAssertFalse(plan?.hosts.contains("192.168.1.42") == true)
    }

    func testScanPlanRejectsPublicAndMalformedAddresses() {
        for address in ["8.8.8.8", "172.15.0.4", "172.32.0.4", "192.0.2.7", "not-an-ip", "192.168.1.999"] {
            XCTAssertNil(FleetDiscoveryScanPlan.plan(forIPv4Address: address), address)
        }
    }

    func testValidSystemInfoBecomesAReadOnlyCandidate() throws {
        let body = Data(#"{"hostname":"Desk Gamma","ASICModel":"BM1370","hashRate":1220,"power":19}"#.utf8)
        let candidate = FleetNetworkDiscovery.candidate(
            host: "192.168.1.17",
            statusCode: 200,
            contentType: "application/json",
            body: body
        )

        XCTAssertEqual(candidate?.name, "Desk Gamma")
        XCTAssertEqual(candidate?.model, "BM1370")
        XCTAssertEqual(candidate?.address, "192.168.1.17")
        XCTAssertEqual(candidate?.device.kind, .espMiner)
        XCTAssertEqual(candidate?.info.hashRate, 1220)
    }

    func testCaptivePortalAndUnknownResponsesAreExcluded() {
        let html = Data("<html>sign in</html>".utf8)
        XCTAssertNil(FleetNetworkDiscovery.candidate(
            host: "192.168.1.17", statusCode: 200, contentType: "text/html", body: html
        ))

        let unknown = Data(#"{"message":"hello"}"#.utf8)
        XCTAssertNil(FleetNetworkDiscovery.candidate(
            host: "192.168.1.18", statusCode: 200, contentType: "application/json", body: unknown
        ))
        XCTAssertNil(FleetNetworkDiscovery.candidate(
            host: "192.168.1.19", statusCode: 503, contentType: "application/json", body: unknown
        ))
    }

    func testCandidatesSortByNumericAddressThenName() {
        let info = MinerInfo(raw: ["hashRate": .number(1)])
        let candidates = [
            FleetDiscoveryCandidate(address: "192.168.1.10", name: "m", info: info),
            FleetDiscoveryCandidate(address: "192.168.1.2", name: "m", info: info),
            FleetDiscoveryCandidate(address: "192.168.1.9", name: "m", info: info)
        ]

        XCTAssertEqual(
            FleetNetworkDiscovery.sorted(candidates).map(\.address),
            ["192.168.1.2", "192.168.1.9", "192.168.1.10"]
        )
    }

    func testEmptyScanReturnsNoCandidatesWithoutInventingDevices() async {
        let plan = FleetDiscoveryScanPlan(localAddress: "192.168.1.42", hosts: ["127.0.0.1"])
        let candidates = await FleetNetworkDiscovery.scan(plan: plan)

        XCTAssertTrue(candidates.isEmpty)
    }
}
