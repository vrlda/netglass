import Foundation

public struct IPAddress: Codable, Hashable, Sendable, CustomStringConvertible {
    public let bytes: [UInt8]

    public init?(text: String) {
        guard !text.contains("%") else { return nil }
        if !text.contains(":") {
            guard Self.isValidDottedQuad(text) else { return nil }
            var v4 = in_addr()
            if text.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 {
                self.bytes = withUnsafeBytes(of: &v4) { Array($0.prefix(4)) }
                return
            }
            return nil
        }
        var v6 = in6_addr()
        if text.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 {
            self.bytes = withUnsafeBytes(of: &v6) { Array($0.prefix(16)) }
            return
        }
        return nil
    }

    private static func isValidDottedQuad(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard !part.isEmpty,
                  UInt8(part) != nil,
                  part.count == 1 || part.first != "0" else { return false }
        }
        return true
    }

    public init?(_ bytes: [UInt8]) {
        guard bytes.count == 4 || bytes.count == 16 else { return nil }
        self.bytes = bytes
    }

    public var isIPv4: Bool { bytes.count == 4 }
    public var isIPv6: Bool { bytes.count == 16 }

    public var text: String {
        if isIPv4 {
            return render4()
        }
        return render6()
    }

    public var description: String { text }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let parsed = IPAddress(text: text) else {
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "invalid IP address text: \(text)")
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }

    private func render4() -> String {
        var addr = in_addr()
        withUnsafeMutableBytes(of: &addr) { $0.copyBytes(from: bytes) }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &buf, socklen_t(buf.count))
        return String(cString: buf)
    }

    private func render6() -> String {
        var addr = in6_addr()
        withUnsafeMutableBytes(of: &addr) { $0.copyBytes(from: bytes) }
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        inet_ntop(AF_INET6, &addr, &buf, socklen_t(buf.count))
        return String(cString: buf)
    }
}
