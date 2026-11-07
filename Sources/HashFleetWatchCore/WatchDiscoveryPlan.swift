import Foundation

/// A validated, bounded plan describing which numeric hosts a local scan may probe.
///
/// A plan can only be built from a private RFC1918 IPv4 address and a contiguous netmask. The candidate hosts
/// are always computed from that pair, never supplied directly, so a caller can never inject an arbitrary or
/// unsafe host. The scan is capped at a single `/24` (at most 254 candidates); on a wider LAN only the Watch's
/// own `/24` is scanned and `isPartialSubnet` is `true`.
public struct WatchDiscoveryPlan: Sendable, Equatable {
    /// Largest number of candidate hosts a single scan may probe (a full `/24` minus network and broadcast).
    public static let maximumHosts = 254

    /// The Watch's own address on the chosen interface (excluded from the candidates).
    public let selfAddress: UInt32
    /// CIDR prefix length of the interface's subnet (0...32).
    public let prefixLength: Int
    /// True when the real subnet is wider than a `/24` and only the local `/24` was planned.
    public let isPartialSubnet: Bool
    /// Numeric candidate hosts, ascending, excluding self, network and broadcast.
    let hosts: [UInt32]

    /// Number of candidate hosts to probe.
    public var hostCount: Int { hosts.count }
    /// Candidate hosts as dotted-quad strings, ascending.
    public var candidateAddresses: [String] { hosts.map(Self.dottedQuad) }

    /// Builds a plan from a numeric address and netmask. Throws `WatchDiscoveryError.invalidPlan` when the
    /// address is not private or the mask is not contiguous.
    init(ipv4 address: UInt32, netmask: UInt32) throws {
        guard Self.isPrivateIPv4(address) else { throw WatchDiscoveryError.invalidPlan }
        guard let prefix = Self.contiguousPrefixLength(netmask) else { throw WatchDiscoveryError.invalidPlan }

        let network = address & netmask
        let broadcast = network | ~netmask
        self.selfAddress = address
        self.prefixLength = prefix

        // /31 (RFC 3021 point-to-point) and /32 (single host) have no usable scan candidates: treated as empty.
        if prefix >= 31 {
            self.isPartialSubnet = false
            self.hosts = []
            return
        }

        // On a normal subnet (/30 or wider) a real host address is never the network or broadcast address.
        // If the metadata claims the Watch itself is one of those, it is inconsistent: reject rather than scan.
        guard address != network, address != broadcast else { throw WatchDiscoveryError.invalidPlan }

        let subnetFirst = network &+ 1
        let subnetLast = broadcast &- 1
        let lower: UInt32
        let upper: UInt32
        if prefix < 24 {
            // Wider than a /24: scan only the local /24's .1...254, clamped to the real subnet's host range.
            isPartialSubnet = true
            let base24 = address & 0xFFFF_FF00
            lower = max(subnetFirst, base24 &+ 1)
            upper = min(subnetLast, base24 | 0x0000_00FE)
        } else {
            isPartialSubnet = false
            lower = subnetFirst
            upper = subnetLast
        }
        guard lower <= upper else { self.hosts = []; return }
        var candidates: [UInt32] = []
        candidates.reserveCapacity(Int(upper - lower) + 1)
        var host = lower
        while host <= upper {
            if host != address { candidates.append(host) }
            if host == upper { break }
            host &+= 1
        }
        precondition(candidates.count <= Self.maximumHosts, "plan exceeded /24 bound")
        self.hosts = candidates
    }

    /// String convenience used by the default scanner and tests. Strict dotted-decimal only: anything hex,
    /// octal, short, IPv6, link-local or otherwise obfuscated is rejected as an invalid plan.
    init(address: String, netmask: String) throws {
        guard let addr = Self.parseStrictIPv4(address), let mask = Self.parseStrictIPv4(netmask) else {
            throw WatchDiscoveryError.invalidPlan
        }
        try self.init(ipv4: addr, netmask: mask)
    }

    // MARK: Numeric helpers

    static func dottedQuad(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }

    /// Strict dotted-decimal IPv4 parse. Requires exactly four decimal octets (0...255) with no leading zeros,
    /// so obfuscated forms (`0x7f…`, `017…`, `2130706433`, short `10.1`) and IPv6 are rejected.
    static func parseStrictIPv4(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part == "0" || part.first != "0", let octet = Int(part), octet <= 255
            else { return nil }
            value = (value << 8) | UInt32(octet)
        }
        return value
    }

    static func isPrivateIPv4(_ value: UInt32) -> Bool {
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        switch (a, b) {
        case (10, _): return true
        case (172, 16...31): return true
        case (192, 168): return true
        default: return false
        }
    }

    /// Returns the CIDR prefix length if the mask is a contiguous run of high bits, else nil.
    static func contiguousPrefixLength(_ mask: UInt32) -> Int? {
        let hostBits = ~mask
        // Contiguous iff the host portion is a low run of 1s: hostBits & (hostBits + 1) == 0.
        guard hostBits & (hostBits &+ 1) == 0 else { return nil }
        return 32 - hostBits.nonzeroBitCount
    }
}
