import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// One active IPv4 interface the Watch could scan from, reduced to the fields a plan needs.
///
/// This is deliberately a plain value so interface enumeration can be tested with injected records and the
/// scanner never has to touch `getifaddrs` in tests.
struct WatchNetworkInterface: Sendable, Equatable {
    /// IPv4 address in host byte order.
    let address: UInt32
    /// Netmask in host byte order.
    let netmask: UInt32
}

/// Supplies the single eligible local interface, or `nil` when the Watch has no direct Wi-Fi link.
///
/// Per Apple TN3179 the implementation does not key on BSD interface names. It enumerates `getifaddrs`
/// (a read-only call, no sockets, no `NWPathMonitor`, no Bonjour) and keeps only active, broadcast-capable,
/// non-loopback, non-point-to-point IPv4 interfaces carrying a private RFC1918 address with a contiguous mask.
/// If exactly one such subnet exists it is returned; any other count fails closed with `nil`.
protocol WatchNetworkInterfaceProviding: Sendable {
    /// Returns the sole eligible interface, or `nil` to force `WatchDiscoveryError.noLocalWiFi`.
    func localInterface() -> WatchNetworkInterface?
}

/// Reads interfaces from the system via `getifaddrs`. Returns `nil` on any platform without Darwin.
struct WatchSystemInterfaceProvider: WatchNetworkInterfaceProviding {
    func localInterface() -> WatchNetworkInterface? {
        WatchInterfaceSelection.sole(from: Self.activeInterfaces())
    }

    /// Enumerates active, broadcast-capable, non-loopback, non-point-to-point private IPv4 interfaces.
    static func activeInterfaces() -> [WatchNetworkInterface] {
        #if canImport(Darwin)
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var found: [WatchNetworkInterface] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addrPtr = entry.pointee.ifa_addr,
                  addrPtr.pointee.sa_family == sa_family_t(AF_INET),
                  addrPtr.pointee.sa_len >= UInt8(MemoryLayout<sockaddr_in>.size) else { continue }

            // `ifa_flags` is a `UInt32`; compare with unsigned masks so high bits never trap on Int32 conversion.
            let flags = entry.pointee.ifa_flags
            func isSet(_ flag: Int32) -> Bool { flags & UInt32(bitPattern: flag) != 0 }
            guard isSet(IFF_UP), isSet(IFF_RUNNING), isSet(IFF_BROADCAST),
                  !isSet(IFF_LOOPBACK), !isSet(IFF_POINTOPOINT) else { continue }
            guard let maskPtr = entry.pointee.ifa_netmask,
                  let netmask = Self.decodeIPv4Netmask(UnsafePointer(maskPtr)) else { continue }

            let address = Self.hostOrderIPv4(addrPtr)
            guard WatchDiscoveryPlan.isPrivateIPv4(address),
                  WatchDiscoveryPlan.contiguousPrefixLength(netmask) != nil else { continue }
            found.append(WatchNetworkInterface(address: address, netmask: netmask))
        }
        return found
        #else
        return []
        #endif
    }

    #if canImport(Darwin)
    /// Darwin can omit a netmask's trailing zero bytes (for example, a /24 mask has sa_len=7, not 16).
    /// The associated ifa_addr already supplies IPv4 context. Copy only the declared bytes into a zeroed
    /// sockaddr_in so compact masks never require an out-of-bounds typed read or acquire garbage suffix bits.
    static func decodeIPv4Netmask(_ address: UnsafePointer<sockaddr>) -> UInt32? {
        let length = Int(address.pointee.sa_len)
        guard (2...MemoryLayout<sockaddr_in>.size).contains(length) else { return nil }
        let family = address.pointee.sa_family
        guard family == sa_family_t(AF_INET) || family == sa_family_t(AF_UNSPEC) else { return nil }
        var expanded = sockaddr_in()
        withUnsafeMutableBytes(of: &expanded) { destination in
            destination.copyMemory(from: UnsafeRawBufferPointer(start: address, count: length))
        }
        return UInt32(bigEndian: expanded.sin_addr.s_addr)
    }

    /// Reads a `sockaddr_in` through an aliased pointer and returns the IPv4 address in host byte order.
    private static func hostOrderIPv4(_ sa: UnsafeMutablePointer<sockaddr>) -> UInt32 {
        sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
        }
    }
    #endif
}

/// Pure selection logic, separated so it can be unit-tested with injected interface records.
enum WatchInterfaceSelection {
    /// Returns the one eligible interface, or `nil` when there are zero, or more than one DISTINCT eligible
    /// `(address, mask)` record.
    ///
    /// Identical records (the same address and mask reported more than once) are de-duplicated and treated as
    /// one. Any two genuinely different eligible records are ambiguous (they could imply a different own `/24`,
    /// and probing one would not exclude the Watch's other address), so we fail closed.
    static func sole(from interfaces: [WatchNetworkInterface]) -> WatchNetworkInterface? {
        let eligible = interfaces.filter {
            WatchDiscoveryPlan.isPrivateIPv4($0.address)
                && WatchDiscoveryPlan.contiguousPrefixLength($0.netmask) != nil
        }
        var distinct: [WatchNetworkInterface] = []
        for record in eligible where !distinct.contains(record) { distinct.append(record) }
        return distinct.count == 1 ? distinct[0] : nil
    }
}
