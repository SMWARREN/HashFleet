import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif
@testable import HashFleetWatchCore

@Suite struct WatchDiscoveryInterfaceTests {
    private func iface(_ address: String, _ mask: String) -> WatchNetworkInterface {
        WatchNetworkInterface(
            address: WatchDiscoveryPlan.parseStrictIPv4(address)!,
            netmask: WatchDiscoveryPlan.parseStrictIPv4(mask)!
        )
    }

    @Test func selectsSoleEligibleInterface() {
        let chosen = WatchInterfaceSelection.sole(from: [iface("192.168.1.50", "255.255.255.0")])
        #expect(chosen == iface("192.168.1.50", "255.255.255.0"))
    }

    @Test func noEligibleInterfaceFailsClosed() {
        // All public or loopback: nothing eligible.
        let chosen = WatchInterfaceSelection.sole(from: [
            iface("8.8.8.8", "255.255.255.0"),
            iface("127.0.0.1", "255.0.0.0")
        ])
        #expect(chosen == nil)
    }

    @Test func emptyListFailsClosed() {
        #expect(WatchInterfaceSelection.sole(from: []) == nil)
    }

    @Test func identicalDuplicateRecordsDedupeToOne() {
        let records = [iface("192.168.1.50", "255.255.255.0"), iface("192.168.1.50", "255.255.255.0")]
        #expect(WatchInterfaceSelection.sole(from: records) == iface("192.168.1.50", "255.255.255.0"))
    }

    @Test func twoDistinctPrivateSubnetsAreAmbiguousAndFailClosed() {
        let records = [iface("192.168.1.50", "255.255.255.0"), iface("10.0.0.5", "255.255.255.0")]
        #expect(WatchInterfaceSelection.sole(from: records) == nil)
    }

    @Test func sameSubnetButDifferentOwnAddressesAreAmbiguous() {
        // Two Watch addresses inside the same /16 but different /24s: distinct records, fail closed.
        let records = [iface("10.0.1.5", "255.255.0.0"), iface("10.0.2.9", "255.255.0.0")]
        #expect(WatchInterfaceSelection.sole(from: records) == nil)
    }

    @Test func ignoresIneligibleRecordsAlongsideOneEligible() {
        // A VPN/public interface present but only one private, contiguous-mask record is eligible.
        let records = [
            iface("8.8.8.8", "255.255.255.0"),       // public, filtered out
            iface("169.254.1.1", "255.255.0.0"),     // link-local (not private), filtered out
            iface("192.168.1.50", "255.255.0.255"),  // non-contiguous mask, filtered out
            iface("192.168.1.50", "255.255.255.0")   // the one eligible record
        ]
        #expect(WatchInterfaceSelection.sole(from: records) == iface("192.168.1.50", "255.255.255.0"))
    }

    #if canImport(Darwin)
    @Test(arguments: [
        (2, UInt32(0x00000000)),
        (5, UInt32(0xFF000000)),
        (6, UInt32(0xFFFF0000)),
        (7, UInt32(0xFFFFFF00)),
        (8, UInt32(0xFFFFFFFF)),
        (16, UInt32(0xFFFFFF00))
    ])
    func decodesDarwinNetmaskIncludingOmittedTrailingZeroBytes(length: Int, expected: UInt32) {
        #expect(decodeMask(length: length, family: UInt8(AF_INET), value: expected) == expected)
    }

    @Test func compactMaskDoesNotReadPoisonBytesPastDeclaredLength() {
        // getifaddrs returned sa_len=7 for the real /24 LAN. Byte 7 and beyond are not part of that mask.
        #expect(decodeMask(length: 7, family: UInt8(AF_INET), value: 0xFFFFFF00) == 0xFFFFFF00)
    }

    @Test func compactNetmaskAllowsUnspecifiedFamilyBecauseAddressSuppliesIPv4Context() {
        #expect(decodeMask(length: 7, family: UInt8(AF_UNSPEC), value: 0xFFFFFF00) == 0xFFFFFF00)
    }

    @Test(arguments: [0, 1, 17, 255])
    func malformedNetmaskLengthFailsClosed(length: Int) {
        #expect(decodeMask(length: length, family: UInt8(AF_INET), value: 0xFFFFFF00) == nil)
    }

    @Test(arguments: [UInt8(AF_INET6), UInt8(AF_LINK)])
    func wrongNetmaskFamilyFailsClosed(family: UInt8) {
        #expect(decodeMask(length: 7, family: family, value: 0xFFFFFF00) == nil)
    }

    private func decodeMask(length: Int, family: UInt8, value: UInt32) -> UInt32? {
        var bytes = [UInt8](repeating: 0xA5, count: MemoryLayout<sockaddr_in>.size)
        bytes[0] = UInt8(length)
        bytes[1] = family
        bytes[2] = 0
        bytes[3] = 0
        for index in 0..<4 where 4 + index < min(length, bytes.count) {
            bytes[4 + index] = UInt8(truncatingIfNeeded: value >> (24 - index * 8))
        }
        return bytes.withUnsafeBytes { buffer in
            WatchSystemInterfaceProvider.decodeIPv4Netmask(buffer.baseAddress!.assumingMemoryBound(to: sockaddr.self))
        }
    }
    #endif

    // MARK: System provider (no live network: just confirms it never traps and stays type-filtered)

    @Test func systemProviderDoesNotTrapAndReturnsOnlyEligible() {
        // This enumerates the host's real interfaces read-only; it must never crash and any result must be a
        // private, contiguous-mask interface (fail-closed to nil otherwise). No probing happens.
        let result = WatchSystemInterfaceProvider().localInterface()
        if let result {
            #expect(WatchDiscoveryPlan.isPrivateIPv4(result.address))
            #expect(WatchDiscoveryPlan.contiguousPrefixLength(result.netmask) != nil)
        }
    }
}
