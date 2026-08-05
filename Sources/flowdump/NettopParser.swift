import Foundation
import FlowModel

public struct NettopConnection: Equatable, Sendable {
    public let transport: TransportProtocol
    public let local: NetworkEndpoint
    public let remote: NetworkEndpoint
    public let interface: String?
    public let state: String?
    public let bytesIn: UInt64
    public let bytesOut: UInt64
}

public struct NettopParser: Sendable {
    public init() {}

    /// Parses nettop `-J` output per the G4-locked contract (Fixtures/nettop/README.md):
    /// header line `time,,interface,state,bytes_in,bytes_out,`; connection rows
    /// `PROTO local<->remote,interface,state,bytes_in,bytes_out,`; process summary
    /// rows (`Name.pid`) and rows with wildcard/scoped/hostname endpoints are skipped.
    public func parse(_ text: String) -> [NettopConnection] {
        var rows: [NettopConnection] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 6 else { continue }
            if fields[0] == "time" { continue }               // header
            guard fields[1] != "time" else { continue }       // defensive: header at any position
            guard let connection = parseConnection(fields) else { continue }
            rows.append(connection)
        }
        return rows
    }

    private func parseConnection(_ fields: [String]) -> NettopConnection? {
        let provenance = fields[1]
        guard let space = provenance.firstIndex(of: " ") else { return nil }  // summary rows
        let protocolToken = String(provenance[..<space])
        let pair = provenance[provenance.index(after: space)...]
        guard let separator = pair.range(of: "<->") else { return nil }
        let localToken = String(pair[..<separator.lowerBound])
        let remoteToken = String(pair[separator.upperBound...])

        guard let transport = Self.parseTransport(protocolToken),
              let local = Self.parseEndpoint(localToken),
              let remote = Self.parseEndpoint(remoteToken) else { return nil }

        func field(_ index: Int) -> String? {
            guard index < fields.count, !fields[index].isEmpty else { return nil }
            return fields[index]
        }

        return NettopConnection(
            transport: transport,
            local: local,
            remote: remote,
            interface: field(2),
            state: field(3),
            bytesIn: field(4).flatMap(UInt64.init) ?? 0,
            bytesOut: field(5).flatMap(UInt64.init) ?? 0)
    }

    /// Endpoint rendering: IPv4 `ip:port`; IPv6 `addr.port` (dot separator, per G4);
    /// bracketed `[addr]:port` accepted defensively (lsof style). Wildcards (`*`),
    /// hostnames, and `%zone` scoped addresses return nil (IPAddress rejects zones).
    private static func parseEndpoint(_ token: String) -> NetworkEndpoint? {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("*") else { return nil }

        var addressPart: String?
        var portPart: String?

        if trimmed.hasPrefix("[") {
            guard let end = trimmed.firstIndex(of: "]") else { return nil }
            addressPart = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
            let after = trimmed[trimmed.index(after: end)...]
            if after.hasPrefix(":") { portPart = String(after.dropFirst()) }
        } else if let colon = trimmed.lastIndex(of: ":") {
            // Last-colon heuristic: real input is nettop dot-port or lsof bracket-port,
            // so trailing-group IPv6 ambiguity (2001:db8::1:2:3) is unreachable.
            let candidate = String(trimmed[..<colon])
            if IPAddress(text: candidate) != nil {
                addressPart = candidate
                portPart = String(trimmed[trimmed.index(after: colon)...])
            }
        }
        if addressPart == nil, let dot = trimmed.lastIndex(of: ".") {
            let candidate = String(trimmed[..<dot])
            if IPAddress(text: candidate) != nil {
                addressPart = candidate
                portPart = String(trimmed[trimmed.index(after: dot)...])
            }
        }

        guard let addressPart, let address = IPAddress(text: addressPart) else { return nil }
        guard let portPart, let port = UInt16(portPart), port > 0 else { return nil }
        return NetworkEndpoint(address: address, port: port)
    }

    private static func parseTransport(_ token: String) -> TransportProtocol? {
        switch token {
        case "tcp4", "tcp6": return .tcp
        case "udp4", "udp6": return .udp
        case "quic4", "quic6": return .quic
        case "icmp4", "icmp6", "icmp": return .icmp
        default: return nil
        }
    }
}

/// Endpoint parsing shared with LsofParser. Bracketed IPv6 `[addr]:port` and
/// bare IPv4 `ip:port` are accepted; wildcards/hostnames/zones return nil.
extension NettopParser {
    static func parseEndpointForLsof(_ token: String) -> NetworkEndpoint? {
        parseEndpoint(token)
    }
}

public struct NettopRow: Equatable, Sendable {
    public let processName: String
    public let pid: Int32?
    public let connID: String?
    public let state: String?
    public let interface: String?
    public let bytesIn: UInt64?
    public let bytesOut: UInt64?
    public let local: NetworkEndpoint?
    public let remote: NetworkEndpoint?
    public let transport: TransportProtocol?
}
