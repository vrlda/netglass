import Foundation

/// One network interface with its addresses, from getifaddrs (no permissions).
public struct NetInterface: Identifiable, Equatable, Sendable {
    public let name: String
    public let ipv4: String?
    public let ipv6: String?

    public var id: String { name }

    public var display: String {
        var parts = [name]
        if let ipv4 { parts.append(ipv4) }
        return parts.joined(separator: " ")
    }
}

/// Real interface enumeration via getifaddrs.
public enum InterfaceStore {
    /// Active, non-loopback interfaces with an address, sorted by name.
    public static func interfaces() -> [NetInterface] {
        var list: [NetInterface] = []
        var ifaddrsPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrsPointer) == 0, let first = ifaddrsPointer else {
            return []
        }
        defer { freeifaddrs(first) }

        var byName: [String: NetInterface] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let node = cursor {
            guard let addr = node.pointee.ifa_addr else {
                cursor = node.pointee.ifa_next
                continue
            }
            let name = String(cString: node.pointee.ifa_name)
            let flags = node.pointee.ifa_flags
            if flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host,
                               socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    var entry = byName[name] ?? NetInterface(name: name, ipv4: nil, ipv6: nil)
                    if ip.contains(":") {
                        entry = NetInterface(name: name, ipv4: entry.ipv4, ipv6: ip)
                    } else {
                        entry = NetInterface(name: name, ipv4: ip, ipv6: entry.ipv6)
                    }
                    byName[name] = entry
                }
            }
            cursor = node.pointee.ifa_next
        }
        list = byName.values.filter { $0.ipv4 != nil || $0.ipv6 != nil }
            .sorted { $0.name < $1.name }
        return list
    }

    /// First interface with an IPv4 address, "en0" fallback.
    public static func primary() -> String {
        interfaces().first(where: { $0.ipv4 != nil })?.name ?? "en0"
    }
}
