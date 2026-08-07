import Foundation

/// One direction of a reassembled TCP/UDP flow.
public struct StreamDirection: Equatable, Sendable {
    public let packets: [Int]
    public let bytes: [UInt8]
}

/// Reassembled bidirectional flow for Follow Stream.
public struct ReassembledStream: Equatable, Sendable {
    public let clientToServer: StreamDirection
    public let serverToClient: StreamDirection
    /// Total payload bytes across both directions.
    public var totalBytes: Int {
        clientToServer.bytes.count + serverToClient.bytes.count
    }
}

/// Pure TCP/UDP stream reassembly from decoded packets. The client side is
/// the endpoint with the ephemeral (higher) port — the connection initiator.
public enum StreamReassembler {
    /// Frames a connection as (client, server) endpoint strings "ip:port".
    public static func endpoints(packet: PacketRecord)
        -> (client: String, server: String)? {
        guard let srcPort = packet.sourcePort, let dstPort = packet.destinationPort else {
            return nil
        }
        if srcPort > dstPort {
            return ("\(packet.source):\(srcPort)", "\(packet.destination):\(dstPort)")
        }
        return ("\(packet.destination):\(dstPort)", "\(packet.source):\(srcPort)")
    }

    /// Reassembles payloads for the flow the packet belongs to (either
    /// direction matches). TCP and UDP only; other protocols yield empty.
    public static func reassemble(packets: [PacketRecord],
                                  for packet: PacketRecord) -> ReassembledStream {
        guard packet.protocolName == "TCP" || packet.protocolName == "UDP",
              let (client, server) = endpoints(packet: packet) else {
            return ReassembledStream(clientToServer: StreamDirection(packets: [], bytes: []),
                                     serverToClient: StreamDirection(packets: [], bytes: []))
        }
        let clientParts = client.split(separator: ":")
        let serverParts = server.split(separator: ":")
        guard clientParts.count == 2, serverParts.count == 2 else {
            return ReassembledStream(clientToServer: StreamDirection(packets: [], bytes: []),
                                     serverToClient: StreamDirection(packets: [], bytes: []))
        }
        let clientIP = String(clientParts[0])
        let clientPort = UInt16(clientParts[1])
        let serverIP = String(serverParts[0])
        let serverPort = UInt16(serverParts[1])

        var c2s: [UInt8] = []
        var s2c: [UInt8] = []
        var c2sIDs: [Int] = []
        var s2cIDs: [Int] = []
        for p in packets where p.protocolName == packet.protocolName {
            guard let srcPort = p.sourcePort, let dstPort = p.destinationPort else { continue }
            if p.source == clientIP, srcPort == clientPort,
               p.destination == serverIP, dstPort == serverPort {
                c2s.append(contentsOf: payload(p))
                c2sIDs.append(p.id)
            } else if p.source == serverIP, srcPort == serverPort,
                      p.destination == clientIP, dstPort == clientPort {
                s2c.append(contentsOf: payload(p))
                s2cIDs.append(p.id)
            }
        }
        return ReassembledStream(
            clientToServer: StreamDirection(packets: c2sIDs, bytes: c2s),
            serverToClient: StreamDirection(packets: s2cIDs, bytes: s2c))
    }

    /// TCP payload is everything after the header; UDP after the 8-byte header.
    private static func payload(_ packet: PacketRecord) -> [UInt8] {
        guard let srcPort = packet.sourcePort, let dstPort = packet.destinationPort else { return [] }
        let bytes = packet.rawBytes
        // find the transport header via the TCP layer offset heuristics:
        // scan from the IP header (20 bytes after Ethernet) — validated by
        // port match on the first two bytes.
        var cursor = 14
        if bytes.count > 34, bytes[12] == 0x08, bytes[13] == 0x00 {
            cursor += 20
        }
        while cursor + 4 <= bytes.count {
            let port = (UInt16(bytes[cursor]) << 8) | UInt16(bytes[cursor + 1])
            if port == srcPort || port == dstPort { break }
            cursor += 1
        }
        guard cursor + 4 <= bytes.count else { return [] }
        if packet.protocolName == "UDP" {
            return cursor + 8 <= bytes.count ? Array(bytes[(cursor + 8)...]) : []
        }
        // TCP: data offset in byte 12 of the header
        let dataOffset = Int(bytes[cursor + 12] >> 4) * 4
        let payloadStart = cursor + dataOffset
        return payloadStart <= bytes.count ? Array(bytes[payloadStart...]) : []
    }
}
