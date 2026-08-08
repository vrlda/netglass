import Foundation

/// IPv4/IPv6 CIDR range for scope matching.
/// Bare hosts (`10.20.10.50`) parse as a full-length prefix (/32, /128).
public struct IPRange: Equatable, Sendable, Codable {
    public let base: [UInt8]
    public let prefix: Int

    public init?(text: String) {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        var prefix: Int?
        if parts.count == 2 {
            guard let parsed = Int(parts[1]), parsed >= 0 else { return nil }
            prefix = parsed
        } else if parts.count != 1 {
            return nil
        }
        var addr = in6_addr()
        let cString = String(parts[0])
        var bytes: [UInt8] = []
        let maxPrefix: Int
        if cString.withCString({ inet_pton(AF_INET, $0, &addr) }) == 1 {
            bytes = withUnsafeBytes(of: addr) { Array($0.prefix(4)) }
            maxPrefix = 32
        } else if cString.withCString({ inet_pton(AF_INET6, $0, &addr) }) == 1 {
            bytes = withUnsafeBytes(of: addr) { Array($0.prefix(16)) }
            maxPrefix = 128
        } else {
            return nil
        }
        let resolved = prefix ?? maxPrefix
        guard resolved <= maxPrefix else { return nil }
        self.base = bytes
        self.prefix = resolved
    }

    public func contains(_ ip: [UInt8]) -> Bool {
        guard ip.count == base.count else { return false }
        let fullBytes = prefix / 8
        guard base.prefix(fullBytes) == ip.prefix(fullBytes) else { return false }
        let remainder = prefix % 8
        guard remainder > 0 else { return true }
        let mask: UInt8 = 0xFF << (8 - remainder)
        return base[fullBytes] & mask == ip[fullBytes] & mask
    }
}
