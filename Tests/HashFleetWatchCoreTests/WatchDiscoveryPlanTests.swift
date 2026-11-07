import Foundation
import Testing
@testable import HashFleetWatchCore

@Suite struct WatchDiscoveryPlanTests {
    // MARK: Numeric helpers

    @Test func strictIPv4ParsingAcceptsCanonicalDottedDecimal() {
        #expect(WatchDiscoveryPlan.parseStrictIPv4("192.168.1.50") == 0xC0A80132)
        #expect(WatchDiscoveryPlan.parseStrictIPv4("10.0.0.1") == 0x0A000001)
        #expect(WatchDiscoveryPlan.parseStrictIPv4("0.0.0.0") == 0)
        #expect(WatchDiscoveryPlan.parseStrictIPv4("255.255.255.255") == 0xFFFFFFFF)
    }

    @Test(arguments: [
        "0x7f.0.0.1", "0x7f000001", "2130706433", "017700000001",
        "192.168.001.5", "192.168.1", "192.168.1.1.1", "192.168.1.256",
        "::1", "[::1]", "", "1.2.3.", ".1.2.3", "a.b.c.d", "192.168.1.-1"
    ])
    func strictIPv4ParsingRejectsObfuscatedOrInvalid(text: String) {
        #expect(WatchDiscoveryPlan.parseStrictIPv4(text) == nil)
    }

    @Test func privateRangeClassification() {
        #expect(WatchDiscoveryPlan.isPrivateIPv4(WatchDiscoveryPlan.parseStrictIPv4("10.1.2.3")!))
        #expect(WatchDiscoveryPlan.isPrivateIPv4(WatchDiscoveryPlan.parseStrictIPv4("172.16.0.1")!))
        #expect(WatchDiscoveryPlan.isPrivateIPv4(WatchDiscoveryPlan.parseStrictIPv4("172.31.255.254")!))
        #expect(WatchDiscoveryPlan.isPrivateIPv4(WatchDiscoveryPlan.parseStrictIPv4("192.168.1.1")!))
        for publicAddress in ["8.8.8.8", "1.1.1.1", "172.15.0.1", "172.32.0.1", "192.169.1.1", "169.254.1.1", "127.0.0.1"] {
            #expect(!WatchDiscoveryPlan.isPrivateIPv4(WatchDiscoveryPlan.parseStrictIPv4(publicAddress)!), "\(publicAddress)")
        }
    }

    @Test func contiguousPrefixLengthRecognizesValidMasksAndRejectsHoles() {
        #expect(WatchDiscoveryPlan.contiguousPrefixLength(WatchDiscoveryPlan.parseStrictIPv4("255.255.255.0")!) == 24)
        #expect(WatchDiscoveryPlan.contiguousPrefixLength(WatchDiscoveryPlan.parseStrictIPv4("255.255.255.128")!) == 25)
        #expect(WatchDiscoveryPlan.contiguousPrefixLength(WatchDiscoveryPlan.parseStrictIPv4("255.255.0.0")!) == 16)
        #expect(WatchDiscoveryPlan.contiguousPrefixLength(WatchDiscoveryPlan.parseStrictIPv4("255.0.0.0")!) == 8)
        #expect(WatchDiscoveryPlan.contiguousPrefixLength(0xFFFFFFFF) == 32)
        #expect(WatchDiscoveryPlan.contiguousPrefixLength(0) == 0)
        // Non-contiguous masks (holes) are rejected.
        #expect(WatchDiscoveryPlan.contiguousPrefixLength(WatchDiscoveryPlan.parseStrictIPv4("255.255.0.255")!) == nil)
        #expect(WatchDiscoveryPlan.contiguousPrefixLength(WatchDiscoveryPlan.parseStrictIPv4("255.0.255.0")!) == nil)
    }

    @Test func dottedQuadRoundTrip() {
        let value = WatchDiscoveryPlan.parseStrictIPv4("192.168.1.207")!
        #expect(WatchDiscoveryPlan.dottedQuad(value) == "192.168.1.207")
    }

    // MARK: /24 plans

    @Test func slash24ExcludesSelfNetworkAndBroadcast() throws {
        let plan = try WatchDiscoveryPlan(address: "192.168.1.50", netmask: "255.255.255.0")
        #expect(plan.prefixLength == 24)
        #expect(!plan.isPartialSubnet)
        // 254 usable hosts minus self = 253 candidates.
        #expect(plan.hostCount == 253)
        #expect(plan.hostCount <= WatchDiscoveryPlan.maximumHosts)
        let addresses = Set(plan.candidateAddresses)
        #expect(!addresses.contains("192.168.1.0"))    // network
        #expect(!addresses.contains("192.168.1.255"))  // broadcast
        #expect(!addresses.contains("192.168.1.50"))   // self
        #expect(addresses.contains("192.168.1.1"))
        #expect(addresses.contains("192.168.1.254"))
    }

    @Test func candidatesAreAscending() throws {
        let plan = try WatchDiscoveryPlan(address: "192.168.1.50", netmask: "255.255.255.0")
        let addresses = plan.candidateAddresses
        let numeric = addresses.map { WatchDiscoveryPlan.parseStrictIPv4($0)! }
        #expect(numeric == numeric.sorted())
    }

    // MARK: Wider than /24

    @Test(arguments: [
        ("10.0.0.5", "255.0.0.0", "10.0.0."),
        ("10.9.9.9", "255.0.0.0", "10.9.9."),
        ("172.16.5.5", "255.255.0.0", "172.16.5."),
        ("192.168.1.10", "255.255.0.0", "192.168.1.")
    ])
    func widerThanSlash24ScansOnlyLocalSlash24(address: String, mask: String, prefix: String) throws {
        let plan = try WatchDiscoveryPlan(address: address, netmask: mask)
        #expect(plan.isPartialSubnet)
        #expect(plan.hostCount <= WatchDiscoveryPlan.maximumHosts)
        #expect(plan.candidateAddresses.allSatisfy { $0.hasPrefix(prefix) }, "all within local /24")
        #expect(!plan.candidateAddresses.contains(address)) // self excluded
    }

    // MARK: /25+ boundaries

    @Test func slash25RespectsBoundaries() throws {
        let plan = try WatchDiscoveryPlan(address: "192.168.1.10", netmask: "255.255.255.128")
        #expect(plan.prefixLength == 25)
        #expect(!plan.isPartialSubnet)
        // hosts .1...126 minus self = 125.
        #expect(plan.hostCount == 125)
        let addresses = Set(plan.candidateAddresses)
        #expect(!addresses.contains("192.168.1.0"))     // network
        #expect(!addresses.contains("192.168.1.127"))   // broadcast
        #expect(!addresses.contains("192.168.1.128"))   // other half
        #expect(addresses.contains("192.168.1.126"))
    }

    @Test func slash30HasTwoHostsMinusSelf() throws {
        let plan = try WatchDiscoveryPlan(address: "192.168.1.5", netmask: "255.255.255.252")
        #expect(plan.prefixLength == 30)
        #expect(plan.candidateAddresses == ["192.168.1.6"]) // .4 network, .7 broadcast, .5 self
    }

    @Test func slash31AndSlash32HaveNoCandidates() throws {
        let p31 = try WatchDiscoveryPlan(address: "192.168.1.4", netmask: "255.255.255.254")
        #expect(p31.prefixLength == 31)
        #expect(p31.hostCount == 0)
        #expect(!p31.isPartialSubnet)
        let p32 = try WatchDiscoveryPlan(address: "192.168.1.4", netmask: "255.255.255.255")
        #expect(p32.prefixLength == 32)
        #expect(p32.hostCount == 0)
    }

    // MARK: Rejections

    @Test(arguments: [
        ("8.8.8.8", "255.255.255.0"),      // public
        ("1.1.1.1", "255.255.255.0"),      // public
        ("169.254.1.1", "255.255.0.0"),    // link-local (not private)
        ("127.0.0.1", "255.0.0.0"),        // loopback
        ("172.15.0.1", "255.255.0.0"),     // just below private 172 range
        ("172.32.0.1", "255.255.0.0")      // just above private 172 range
    ])
    func rejectsNonPrivateAddresses(address: String, mask: String) {
        #expect(throws: WatchDiscoveryError.invalidPlan) { try WatchDiscoveryPlan(address: address, netmask: mask) }
    }

    @Test(arguments: [
        ("192.168.1.5", "255.255.0.255"),  // non-contiguous mask
        ("192.168.1.5", "255.0.255.0"),    // non-contiguous mask
        ("0x7f.0.0.1", "255.255.255.0"),   // obfuscated address
        ("2130706433", "255.255.255.0"),   // decimal-int address
        ("192.168.1.5", "0x.0.0"),         // obfuscated mask
        ("::1", "255.255.255.0")           // IPv6
    ])
    func rejectsInvalidAddressOrMask(address: String, mask: String) {
        #expect(throws: WatchDiscoveryError.invalidPlan) { try WatchDiscoveryPlan(address: address, netmask: mask) }
    }

    @Test func rejectsSelfBeingNetworkOrBroadcastAddress() {
        // Inconsistent metadata: a real host address is never the network or broadcast address on /30 or wider.
        #expect(throws: WatchDiscoveryError.invalidPlan) {
            try WatchDiscoveryPlan(address: "192.168.1.0", netmask: "255.255.255.0")   // network
        }
        #expect(throws: WatchDiscoveryError.invalidPlan) {
            try WatchDiscoveryPlan(address: "192.168.1.255", netmask: "255.255.255.0") // broadcast
        }
        #expect(throws: WatchDiscoveryError.invalidPlan) {
            try WatchDiscoveryPlan(address: "10.0.0.0", netmask: "255.0.0.0")          // network, wide
        }
    }
}
