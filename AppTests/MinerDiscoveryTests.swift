import Foundation
import Testing
@testable import HashFleet

@Suite("Miner discovery safety")
struct MinerDiscoveryTests {
    @Test func scanPlanIsBoundedToPrivateSlashTwentyFourAndSkipsThePhone() {
        let plan = MinerDiscoveryScanPlan.plan(forIPv4Address: "192.168.1.42")
        #expect(plan?.localAddress == "192.168.1.42")
        #expect(plan?.hosts.count == 253)
        #expect(plan?.hosts.first == "192.168.1.1")
        #expect(plan?.hosts.last == "192.168.1.254")
        #expect(plan?.hosts.contains("192.168.1.42") == false)
    }

    @Test(arguments: ["8.8.8.8", "172.15.0.4", "172.32.0.4", "192.0.2.7", "not-an-ip", "192.168.1.999"])
    func scanPlanRejectsPublicAndMalformedAddresses(_ address: String) {
        #expect(MinerDiscoveryScanPlan.plan(forIPv4Address: address) == nil)
    }

    @Test func validSystemInfoBecomesAReadOnlyCandidate() throws {
        let body = Data(#"{"hostname":"Desk Gamma","ASICModel":"BM1370","hashRate":1220,"power":19}"#.utf8)
        let candidate = MinerDiscoveryService.candidate(
            host: "192.168.1.17",
            statusCode: 200,
            contentType: "application/json",
            body: body
        )
        #expect(candidate?.name == "Desk Gamma")
        #expect(candidate?.model == "BM1370")
        #expect(candidate?.address == "192.168.1.17")
    }

    @Test func captivePortalHtmlAndUnknownJsonNeverBecomeMiners() {
        let html = Data("<html>sign in</html>".utf8)
        #expect(
            MinerDiscoveryService.candidate(
                host: "192.168.1.17",
                statusCode: 200,
                contentType: "text/html",
                body: html
            ) == nil
        )
        let unknown = Data(#"{"message":"hello"}"#.utf8)
        #expect(
            MinerDiscoveryService.candidate(
                host: "192.168.1.18",
                statusCode: 200,
                contentType: "application/json",
                body: unknown
            ) == nil
        )
        #expect(
            MinerDiscoveryService.candidate(
                host: "192.168.1.19",
                statusCode: 503,
                contentType: "application/json",
                body: unknown
            ) == nil
        )
    }
}

@Suite("Miner discovery ordering and grouping")
struct MinerDiscoveryOrderingTests {
    private func candidate(_ address: String, model: String? = nil, name: String = "m") -> MinerDiscoveryCandidate {
        MinerDiscoveryCandidate(address: address, name: name, model: model)
    }

    @Test func addressesSortNumericallyNotLexicographically() {
        let input = [
            candidate("192.168.1.10"),
            candidate("192.168.1.2"),
            candidate("192.168.1.9")
        ]
        // Lexicographic order would yield .10, .2, .9. A user comparing the list against
        // their rack expects numeric order.
        #expect(
            MinerDiscoveryService.sorted(input).map(\.address) ==
                ["192.168.1.2", "192.168.1.9", "192.168.1.10"]
        )
    }

    @Test func sameAddressTiesBreakByName() {
        let input = [
            candidate("192.168.1.7", name: "Zeta"),
            candidate("192.168.1.7", name: "Alpha")
        ]
        #expect(MinerDiscoveryService.sorted(input).map(\.name) == ["Alpha", "Zeta"])
    }

    @Test func groupingBucketingByModelSortsGroupsAndKeepsUnknownLast() {
        let groups = MinerDiscoveryGrouping.groups(for: [
            candidate("192.168.1.20", model: "BM1370"),
            candidate("192.168.1.9", model: "BM1368"),
            candidate("192.168.1.30", model: nil),
            candidate("192.168.1.2", model: "BM1370")
        ])
        #expect(groups.map(\.title) == ["BM1368", "BM1370", MinerDiscoveryGrouping.otherTitle])
        #expect(groups[1].candidates.map(\.address) == ["192.168.1.2", "192.168.1.20"])
        #expect(groups[2].candidates.map(\.address) == ["192.168.1.30"])
    }

    @Test func groupingMergesModelNamesThatDifferOnlyByCase() {
        let groups = MinerDiscoveryGrouping.groups(for: [
            candidate("192.168.1.2", model: "BM1370"),
            candidate("192.168.1.3", model: "bm1370")
        ])
        #expect(groups.count == 1)
        #expect(groups[0].candidates.count == 2)
    }

    @Test func singleGroupProducesOneSection() {
        let groups = MinerDiscoveryGrouping.groups(for: [
            candidate("192.168.1.2", model: "BM1370"),
            candidate("192.168.1.3", model: "BM1370")
        ])
        #expect(groups.count == 1)
    }
}
