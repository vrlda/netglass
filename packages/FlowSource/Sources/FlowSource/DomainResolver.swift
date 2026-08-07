import FlowModel
import Foundation

/// Injectable DNS lookup surface so the resolver is unit-testable without
/// touching the network. All methods are blocking — callers run them on
/// background threads.
public protocol ReverseDNSResolving: Sendable {
    /// PTR lookup: hostname for the given numeric IP, or nil.
    func hostname(for ip: String) -> String?
    /// Forward lookup: numeric IPs for the given hostname, or empty.
    func ipAddresses(for hostname: String) -> [String]
}

/// Real system lookups via getnameinfo / getaddrinfo. Stateless and Sendable.
public struct SystemResolver: ReverseDNSResolving {
    public init() {}

    public func hostname(for ip: String) -> String? {
        var storage = sockaddr_storage()
        let length = makeSockaddr(ip: ip, into: &storage)
        guard let length else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(length), &host, socklen_t(host.count),
                            nil, 0, NI_NAMEREQD)
            }
        }
        guard result == 0 else { return nil }
        let name = String(cString: host)
        guard name.contains(".") else { return nil }   // bare hostnames are junk
        return name
    }

    public func ipAddresses(for hostname: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, nil, &hints, &result) == 0, let result else { return [] }
        defer { freeaddrinfo(result) }
        var ips: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = result
        while let node = current {
            if let address = node.pointee.ai_addr {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, node.pointee.ai_addrlen, &host,
                               socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    ips.append(String(cString: host))
                }
            }
            current = node.pointee.ai_next
        }
        return ips
    }

    /// Builds a sockaddr for an IPv4/IPv6 literal. Returns its length.
    private func makeSockaddr(ip: String, into storage: inout sockaddr_storage) -> socklen_t? {
        var v4 = in_addr()
        if inet_pton(AF_INET, ip, &v4) == 1 {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_addr = v4
            memcpy(&storage, &addr, MemoryLayout<sockaddr_in>.size)
            return socklen_t(MemoryLayout<sockaddr_in>.size)
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, ip, &v6) == 1 {
            var addr = sockaddr_in6()
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_addr = v6
            memcpy(&storage, &addr, MemoryLayout<sockaddr_in6>.size)
            return socklen_t(MemoryLayout<sockaddr_in6>.size)
        }
        return nil
    }
}
