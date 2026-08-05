import Foundation
import FlowModel

public struct LsofSocket: Equatable, Sendable {
    public let pid: Int32
    public let processName: String
    public let transport: TransportProtocol
    public let local: NetworkEndpoint
    public let remote: NetworkEndpoint
}

public struct LsofParser: Sendable {
    public init() {}

    /// Parses `lsof -i -n -P` output. NAME column is `PROTO local->remote (STATE)`
    /// or `PROTO local` for listeners. Header, wildcards, and listeners (no remote)
    /// are skipped. The protocol token is located by scanning from the NODE column
    /// onward: real lsof omits NODE for network rows (protocol at field 7), while
    /// the synthetic fixture carries `0` (protocol at field 8).
    public func parse(_ text: String) -> [LsofSocket] {
        var sockets: [LsofSocket] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("COMMAND") else { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 9 else { continue }
            guard let pid = Int32(fields[1]) else { continue }
            let processName = String(fields[0])
            guard let protoIndex = fields[7...].firstIndex(where: { $0 == "TCP" || $0 == "UDP" }) else { continue }
            let name = fields[protoIndex...].joined(separator: " ")

            guard let transport = Self.parseTransport(name),
                  let firstSpace = name.firstIndex(of: " "),
                  let pair = name.range(of: "->") else { continue }
            let localToken = String(name[name.index(after: firstSpace)..<pair.lowerBound])
            let remoteToken = String(name[pair.upperBound...].prefix { $0 != " " })

            guard let local = Self.parseEndpoint(localToken),
                  let remote = Self.parseEndpoint(remoteToken) else { continue }
            sockets.append(LsofSocket(pid: pid, processName: processName,
                                      transport: transport, local: local, remote: remote))
        }
        return sockets
    }

    private static func parseTransport(_ name: String) -> TransportProtocol? {
        if name.hasPrefix("TCP") { return .tcp }
        if name.hasPrefix("UDP") { return .udp }
        return nil
    }

    private static func parseEndpoint(_ token: String) -> NetworkEndpoint? {
        NettopParser.parseEndpointForLsof(token)
    }
}
