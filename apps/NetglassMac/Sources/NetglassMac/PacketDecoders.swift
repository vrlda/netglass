import Foundation

/// One decoded packet ready for the inspector UI.
public struct PacketRecord: Identifiable, Equatable, Sendable {
    public let id: Int
    public let timestamp: Date
    public let deltaMs: Double
    public let source: String
    public let sourcePort: UInt16?
    public let destination: String
    public let destinationPort: UInt16?
    public let protocolName: String
    public let length: Int
    public let info: String
    public let rawBytes: [UInt8]
    public let layers: [PacketLayer]
}

public struct PacketLayer: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let fields: [PacketField]
}

public struct PacketField: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let value: String
    public let offset: Int
    public let length: Int
    public let detail: String?
}

/// Native protocol decoders: Ethernet, IPv4/IPv6, TCP/UDP/ICMP, DNS, TLS
/// ClientHello (SNI), HTTP/1.1 first line. Unknown payloads get a summary.
public enum PacketDecoders {
    public static func decode(_ raw: RawPacket, number: Int,
                              previous: RawPacket? = nil) -> PacketRecord {
        var offset = 0
        var layers: [PacketLayer] = []
        var source = "?"
        var destination = "?"
        var srcPort: UInt16?
        var dstPort: UInt16?
        var protocolName = "Unknown"
        var info = ""

        layers.append(eth(raw, number: number))

        if raw.linkType == 1 {   // Ethernet
            offset = 14
            let etherType = (UInt16(raw.bytes[12]) << 8) | UInt16(raw.bytes[13])
            if etherType == 0x0800 {
                let ip = decodeIPv4(raw, offset: offset)
                layers.append(ip.layer)
                source = ip.source
                destination = ip.destination
                offset = ip.payloadOffset
                switch ip.protocolNumber {
                case 6:
                    protocolName = "TCP"
                    let tcp = decodeTCP(raw, offset: offset)
                    layers.append(tcp.layer)
                    srcPort = tcp.srcPort
                    dstPort = tcp.dstPort
                    offset = tcp.payloadOffset
                    info = tcp.info
                case 17:
                    protocolName = "UDP"
                    let udp = decodeUDP(raw, offset: offset)
                    layers.append(udp.layer)
                    srcPort = udp.srcPort
                    dstPort = udp.dstPort
                    offset = udp.payloadOffset
                    info = "\(udp.srcPort) → \(udp.dstPort)"
                case 1:
                    protocolName = "ICMP"
                    let icmp = decodeICMP(raw, offset: offset)
                    layers.append(icmp.layer)
                    info = icmp.info
                default:
                    info = "IP protocol \(ip.protocolNumber)"
                }
            } else if etherType == 0x86DD {
                let ip = decodeIPv6(raw, offset: offset)
                layers.append(ip.layer)
                source = ip.source
                destination = ip.destination
                offset = ip.payloadOffset
                switch ip.protocolNumber {
                case 6:
                    protocolName = "TCP"
                    let tcp = decodeTCP(raw, offset: offset)
                    layers.append(tcp.layer)
                    srcPort = tcp.srcPort
                    dstPort = tcp.dstPort
                    offset = tcp.payloadOffset
                    info = tcp.info
                case 17:
                    protocolName = "UDP"
                    let udp = decodeUDP(raw, offset: offset)
                    layers.append(udp.layer)
                    srcPort = udp.srcPort
                    dstPort = udp.dstPort
                    offset = udp.payloadOffset
                    info = "\(udp.srcPort) → \(udp.dstPort)"
                case 58:
                    protocolName = "ICMPv6"
                    info = "ICMPv6"
                default:
                    info = "IPv6 next header \(ip.protocolNumber)"
                }
            } else if etherType == 0x0806 {
                protocolName = "ARP"
                layers.append(arpLayer(raw))
                info = "ARP request/reply"
            } else {
                info = "EtherType 0x\(String(format: "%04x", etherType))"
            }
        } else if let firstByte = raw.bytes.first {
            // raw IP capture (linktype 101/228/229/276)
            if firstByte >> 4 == 4 {
                let ip = decodeIPv4(raw, offset: 0)
                layers.append(ip.layer)
                source = ip.source
                destination = ip.destination
                offset = ip.payloadOffset
                protocolName = "IP"
                info = "IPv4"
            } else if firstByte >> 4 == 6 {
                let ip = decodeIPv6(raw, offset: 0)
                layers.append(ip.layer)
                source = ip.source
                destination = ip.destination
                offset = ip.payloadOffset
                protocolName = "IP"
                info = "IPv6"
            }
        }

        // application-layer decoders
        if protocolName == "TCP", offset + 1 < raw.bytes.count {
            let payload = Array(raw.bytes[offset...])
            if payload.first == 0x16, payload.count > 1, payload[1] == 0x03 {
                protocolName = "TLS"
                if let cert = decodeTLSCertificate(payload) {
                    let layer = PacketLayer(id: "tls-cert", name: "Transport Layer Security (Certificate)", fields: [
                        field("Subject CN", cert.subject, 0, 0),
                        field("Issuer CN", cert.issuer, 0, 0),
                        field("Not before", cert.notBefore, 0, 0),
                        field("Not after", cert.notAfter, 0, 0),
                    ])
                    layers.append(layer)
                    info = "Certificate, subject: \(cert.subject)"
                } else {
                    let tls = decodeTLSClientHello(payload)
                    layers.append(tls.layer)
                    info = tls.info
                }
            } else if let firstLine = httpFirstLine(payload) {
                protocolName = "HTTP"
                layers.append(layer(id: "http", name: "Hypertext Transfer Protocol", fields: [
                    field("Request line", firstLine, 0, payload.count)
                ]))
                info = firstLine
            }
        } else if protocolName == "UDP", let dstPort, dstPort == 53 || srcPort == 53 {
            if offset + 12 <= raw.bytes.count {
                protocolName = "DNS"
                let dns = decodeDNS(Array(raw.bytes[offset...]))
                layers.append(dns.layer)
                info = dns.info
            }
        }

        let delta = previous.map { raw.timestamp.timeIntervalSince($0.timestamp) * 1000 } ?? 0
        return PacketRecord(id: number, timestamp: raw.timestamp, deltaMs: delta,
                            source: source, sourcePort: srcPort,
                            destination: destination, destinationPort: dstPort,
                            protocolName: protocolName,
                            length: raw.capturedLength,
                            info: info.isEmpty ? "\(protocolName) frame" : info,
                            rawBytes: raw.bytes,
                            layers: layers)
    }

    // MARK: - Layers

    private static func eth(_ raw: RawPacket, number: Int) -> PacketLayer {
        let bytes = raw.bytes
        var fields: [PacketField] = [
            field("Frame number", "\(number)", 0, 1),
            field("Frame length", "\(raw.capturedLength) bytes", 0, 0),
            field("Capture time", raw.timestamp.formatted(date: .omitted, time: .standard), 0, 0),
        ]
        if raw.linkType == 1, bytes.count >= 14 {
            fields.append(field("Destination MAC", mac(bytes, 0), 0, 6))
            fields.append(field("Source MAC", mac(bytes, 6), 6, 6))
            fields.append(field("EtherType",
                                "0x\(String(format: "%04x", (UInt16(bytes[12]) << 8) | UInt16(bytes[13])))",
                                12, 2))
        }
        return PacketLayer(id: "frame", name: "Frame", fields: fields)
    }

    private static func mac(_ bytes: [UInt8], _ offset: Int) -> String {
        guard offset + 6 <= bytes.count else { return "—" }
        return bytes[offset..<(offset + 6)].map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    private static func decodeIPv4(_ raw: RawPacket, offset: Int) -> (layer: PacketLayer, source: String,
                                                                      destination: String,
                                                                      protocolNumber: UInt8,
                                                                      payloadOffset: Int) {
        let bytes = raw.bytes
        guard offset + 20 <= bytes.count else {
            return (PacketLayer(id: "ip", name: "Internet Protocol Version 4", fields: []),
                    "?", "?", 0, offset)
        }
        let ihl = Int(bytes[offset] & 0x0F) * 4
        let proto = bytes[offset + 9]
        let src = "\(bytes[offset + 12]).\(bytes[offset + 13]).\(bytes[offset + 14]).\(bytes[offset + 15])"
        let dst = "\(bytes[offset + 16]).\(bytes[offset + 17]).\(bytes[offset + 18]).\(bytes[offset + 19])"
        let totalLength = (UInt16(bytes[offset + 2]) << 8) | UInt16(bytes[offset + 3])
        let layer = PacketLayer(id: "ip", name: "Internet Protocol Version 4", fields: [
            field("Source", src, offset + 12, 4),
            field("Destination", dst, offset + 16, 4),
            field("Protocol", "\(proto) (\(protoName(proto)))", offset + 9, 1),
            field("Total length", "\(totalLength) bytes", offset + 2, 2),
        ])
        return (layer, src, dst, proto, offset + ihl)
    }

    private static func decodeIPv6(_ raw: RawPacket, offset: Int) -> (layer: PacketLayer, source: String,
                                                                      destination: String,
                                                                      protocolNumber: UInt8,
                                                                      payloadOffset: Int) {
        let bytes = raw.bytes
        guard offset + 40 <= bytes.count else {
            return (PacketLayer(id: "ipv6", name: "Internet Protocol Version 6", fields: []),
                    "?", "?", 0, offset)
        }
        let src = ipv6Text(bytes, offset + 8)
        let dst = ipv6Text(bytes, offset + 24)
        var next = bytes[offset + 6]
        var payload = offset + 40
        // skip extension headers
        var guardCount = 0
        while [0, 43, 60, 44, 51, 50].contains(next), payload + 8 <= bytes.count, guardCount < 8 {
            next = bytes[payload]
            let len = (Int(bytes[payload + 1]) + 1) * 8
            payload += len
            guardCount += 1
        }
        let layer = PacketLayer(id: "ipv6", name: "Internet Protocol Version 6", fields: [
            field("Source", src, offset + 8, 16),
            field("Destination", dst, offset + 24, 16),
            field("Next header", "\(next)", offset + 6, 1),
        ])
        return (layer, src, dst, next, payload)
    }

    private static func ipv6Text(_ bytes: [UInt8], _ offset: Int) -> String {
        guard offset + 16 <= bytes.count else { return "?" }
        let groups = stride(from: offset, to: offset + 16, by: 2).map {
            String(format: "%x", (UInt16(bytes[$0]) << 8) | UInt16(bytes[$0 + 1]))
        }
        return groups.joined(separator: ":")
    }

    private static func decodeTCP(_ raw: RawPacket, offset: Int) -> (layer: PacketLayer, srcPort: UInt16?,
                                                                     dstPort: UInt16?, payloadOffset: Int,
                                                                     info: String) {
        let bytes = raw.bytes
        guard offset + 20 <= bytes.count else {
            return (PacketLayer(id: "tcp", name: "Transmission Control Protocol", fields: []),
                    nil, nil, offset, "TCP (truncated)")
        }
        let src = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
        let dst = (UInt16(bytes[offset + 2]) << 8) | UInt16(bytes[offset + 3])
        let seq = (UInt64(bytes[offset + 4]) << 24) | (UInt64(bytes[offset + 5]) << 16)
            | (UInt64(bytes[offset + 6]) << 8) | UInt64(bytes[offset + 7])
        let dataOffset = Int(bytes[offset + 12] >> 4) * 4
        let flags = bytes[offset + 13]
        var flagChars = ""
        if flags & 0x02 != 0 { flagChars += "S" }
        if flags & 0x10 != 0 { flagChars += "A" }
        if flags & 0x08 != 0 { flagChars += "P" }
        if flags & 0x01 != 0 { flagChars += "F" }
        if flags & 0x04 != 0 { flagChars += "R" }
        if flagChars.isEmpty { flagChars = "." }
        let layer = PacketLayer(id: "tcp", name: "Transmission Control Protocol", fields: [
            field("Source port", "\(src)", offset, 2),
            field("Destination port", "\(dst)", offset + 2, 2),
            field("Sequence number", "\(seq)", offset + 4, 4),
            field("Flags", "0x\(String(format: "%02x", flags)) (\(flagChars))", offset + 13, 1),
        ])
        return (layer, src, dst, offset + dataOffset, "\(src) → \(dst) [\(flagChars)] Seq=\(seq)")
    }

    private static func decodeUDP(_ raw: RawPacket, offset: Int) -> (layer: PacketLayer, srcPort: UInt16?,
                                                                     dstPort: UInt16?, payloadOffset: Int) {
        let bytes = raw.bytes
        guard offset + 8 <= bytes.count else {
            return (PacketLayer(id: "udp", name: "User Datagram Protocol", fields: []),
                    nil, nil, offset)
        }
        let src = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
        let dst = (UInt16(bytes[offset + 2]) << 8) | UInt16(bytes[offset + 3])
        let len = (UInt16(bytes[offset + 4]) << 8) | UInt16(bytes[offset + 5])
        let layer = PacketLayer(id: "udp", name: "User Datagram Protocol", fields: [
            field("Source port", "\(src)", offset, 2),
            field("Destination port", "\(dst)", offset + 2, 2),
            field("Length", "\(len)", offset + 4, 2),
        ])
        return (layer, src, dst, offset + 8)
    }

    private static func decodeICMP(_ raw: RawPacket, offset: Int) -> (layer: PacketLayer, info: String) {
        let bytes = raw.bytes
        guard offset + 4 <= bytes.count else {
            return (PacketLayer(id: "icmp", name: "Internet Control Message Protocol", fields: []), "ICMP")
        }
        let type = bytes[offset]
        let code = bytes[offset + 1]
        let layer = PacketLayer(id: "icmp", name: "Internet Control Message Protocol", fields: [
            field("Type", "\(type)", offset, 1),
            field("Code", "\(code)", offset + 1, 1),
        ])
        return (layer, "ICMP type \(type) code \(code)")
    }

    private static func arpLayer(_ raw: RawPacket) -> PacketLayer {
        let bytes = raw.bytes
        var fields: [PacketField] = []
        if bytes.count >= 28 {
            let op = (UInt16(bytes[6]) << 8) | UInt16(bytes[7])
            let sender = "\(bytes[14]).\(bytes[15]).\(bytes[16]).\(bytes[17])"
            let target = "\(bytes[24]).\(bytes[25]).\(bytes[26]).\(bytes[27])"
            fields.append(field("Operation", op == 1 ? "request (1)" : "reply (2)", 6, 2))
            fields.append(field("Sender IP", sender, 14, 4))
            fields.append(field("Target IP", target, 24, 4))
        }
        return PacketLayer(id: "arp", name: "Address Resolution Protocol", fields: fields)
    }

    // MARK: - DNS

    private static func decodeDNS(_ payload: [UInt8]) -> (layer: PacketLayer, info: String) {
        var fields: [PacketField] = []
        guard payload.count >= 12 else {
            return (PacketLayer(id: "dns", name: "Domain Name System", fields: []), "DNS (truncated)")
        }
        let id = (UInt16(payload[0]) << 8) | UInt16(payload[1])
        let flags = (UInt16(payload[2]) << 8) | UInt16(payload[3])
        let isResponse = flags & 0x8000 != 0
        let qdCount = Int((UInt16(payload[4]) << 8) | UInt16(payload[5]))
        let anCount = Int((UInt16(payload[6]) << 8) | UInt16(payload[7]))
        fields.append(field("Transaction ID", "0x\(String(format: "%04x", id))", 0, 2))
        fields.append(field("Flags", "0x\(String(format: "%04x", flags)) \(isResponse ? "response" : "query")",
                            2, 2))

        var offset = 12
        var questions: [(name: String, type: String)] = []
        for _ in 0..<qdCount {
            guard let parsed = parseName(payload, offset: offset) else { break }
            offset = parsed.end
            guard offset + 4 <= payload.count else { break }
            let qtype = (UInt16(payload[offset]) << 8) | UInt16(payload[offset + 1])
            questions.append((parsed.name, dnsType(qtype)))
            offset += 4
        }
        let queryName = questions.first?.name ?? "?"
        let queryType = questions.first?.type ?? "?"

        var answers: [String] = []
        var answerOffset = offset
        for _ in 0..<anCount {
            guard answerOffset + 2 <= payload.count else { break }
            if payload[answerOffset] & 0xC0 == 0xC0 {
                answerOffset += 2
            } else if let parsed = parseName(payload, offset: answerOffset) {
                answerOffset = parsed.end
            } else { break }
            guard answerOffset + 10 <= payload.count else { break }
            let rtype = (UInt16(payload[answerOffset]) << 8) | UInt16(payload[answerOffset + 1])
            let rdLength = Int((UInt16(payload[answerOffset + 8]) << 8) | UInt16(payload[answerOffset + 9]))
            let rdataStart = answerOffset + 10
            guard rdataStart + rdLength <= payload.count else { break }
            let rdata = Array(payload[rdataStart..<(rdataStart + rdLength)])
            answers.append(formatRData(rtype, rdata, payload, rdataStart))
            answerOffset = rdataStart + rdLength
        }

        var info = "\(isResponse ? "Standard response" : "Standard query") 0x"
            + String(format: "%04x", id) + " \(queryName)"
        if isResponse {
            info += " → " + (answers.joined(separator: ", ") )
        } else {
            info += ": type \(queryType)"
        }

        fields.append(field("Queries", "\(qdCount)", 4, 2))
        fields.append(field("Query", "\(queryName): type \(queryType), class IN", offset, 0))
        fields.append(field("Answers", "\(anCount)", 6, 2))
        return (PacketLayer(id: "dns", name: "Domain Name System", fields: fields), info)
    }

    private static func parseName(_ payload: [UInt8], offset: Int) -> (name: String, end: Int)? {
        var labels: [String] = []
        var cursor = offset
        var guardCount = 0
        while cursor < payload.count, guardCount < 64 {
            let len = Int(payload[cursor])
            if len == 0 {
                cursor += 1
                break
            }
            if len & 0xC0 == 0xC0 {   // compression pointer
                let ptr = ((len & 0x3F) << 8) | Int(payload[cursor + 1])
                if let target = parseName(payload, offset: ptr) {
                    labels.append(target.name)
                }
                cursor += 2
                break
            }
            guard cursor + 1 + len <= payload.count else { return nil }
            if let label = String(bytes: payload[(cursor + 1)..<(cursor + 1 + len)], encoding: .utf8) {
                labels.append(label)
            }
            cursor += 1 + len
            guardCount += 1
        }
        return (labels.joined(separator: "."), cursor)
    }

    private static func formatRData(_ rtype: UInt16, _ rdata: [UInt8],
                                    _ payload: [UInt8], _ start: Int) -> String {
        switch rtype {
        case 1:   // A
            return rdata.count == 4 ? rdata.map(String.init).joined(separator: ".") : "?"
        case 28:  // AAAA
            return rdata.count == 16
                ? stride(from: 0, to: 16, by: 2).map {
                    String(format: "%x", (UInt16(rdata[$0]) << 8) | UInt16(rdata[$0 + 1]))
                }.joined(separator: ":") : "?"
        case 5:   // CNAME / 12 PTR
            return parseName(payload, offset: start)?.name ?? "?"
        case 2, 15:
            return parseName(payload, offset: start)?.name ?? "?"
        case 16:  // TXT
            if let first = rdata.first, rdata.count > first + 1 {
                return String(bytes: rdata[1...Int(first)], encoding: .utf8) ?? "?"
            }
            return "?"
        default:
            return "rdata(\(rdata.count))"
        }
    }

    private static func dnsType(_ t: UInt16) -> String {
        switch t {
        case 1: "A"
        case 2: "NS"
        case 5: "CNAME"
        case 6: "SOA"
        case 12: "PTR"
        case 15: "MX"
        case 16: "TXT"
        case 28: "AAAA"
        case 33: "SRV"
        case 41: "OPT"
        case 255: "ANY"
        default: "TYPE\(t)"
        }
    }

    // MARK: - TLS ClientHello

    private static func decodeTLSClientHello(_ payload: [UInt8]) -> (layer: PacketLayer, info: String) {
        var fields: [PacketField] = [
            field("Content type", "Handshake (0x16)", 0, 1),
            field("Version", "TLS \(payload[1]).\(payload[2])", 1, 2),
        ]
        var sni: String?
        if payload.count > 5 {
            let recordLen = (Int(payload[3]) << 8) | Int(payload[4])
            let end = min(payload.count, 5 + recordLen)
            if end > 5 + 4, payload[5] == 1 {   // ClientHello
                var cursor = 5 + 4
                if cursor + 34 <= end { cursor += 34 }   // version(2) + random(32)
                if cursor + 1 <= end {
                    let sidLen = Int(payload[cursor])
                    cursor += 1 + sidLen
                }
                if cursor + 2 <= end {
                    let csLen = Int(payload[cursor]) << 8 | Int(payload[cursor + 1])
                    cursor += 2 + csLen
                }
                if cursor + 1 <= end {
                    let compLen = Int(payload[cursor])
                    cursor += 1 + compLen
                }
                if cursor + 2 <= end {
                    let extLen = Int(payload[cursor]) << 8 | Int(payload[cursor + 1])
                    let extEnd = min(end, cursor + 2 + extLen)
                    cursor += 2
                    while cursor + 4 <= extEnd {
                        let extType = Int(payload[cursor]) << 8 | Int(payload[cursor + 1])
                        let len = Int(payload[cursor + 2]) << 8 | Int(payload[cursor + 3])
                        if extType == 0 {   // server_name
                            let data = Array(payload[(cursor + 4)..<min(extEnd, cursor + 4 + len)])
                            if data.count > 5, data[0] == 0 {
                                let nameLen = Int(data[3]) << 8 | Int(data[4])
                                if data.count >= 5 + nameLen {
                                    sni = String(bytes: data[5..<(5 + nameLen)], encoding: .utf8)
                                }
                            }
                        }
                        cursor += 4 + len
                    }
                }
            }
        }
        fields.append(field("Server name (SNI)", sni ?? "—", 0, 0))
        let layer = PacketLayer(id: "tls", name: "Transport Layer Security", fields: fields)
        let info = sni.map { "Client Hello, SNI: \($0)" } ?? "Client Hello"
        return (layer, info)
    }

    // MARK: - TLS Certificate (minimal ASN.1)

    /// Parses a TLS Certificate handshake: extracts subject CN, issuer CN and
    /// validity from the first certificate's DER. Returns nil when the
    /// structure isn't a recognizable certificate chain.
    public static func decodeTLSCertificate(_ payload: [UInt8]) -> (subject: String,
                                                                    issuer: String,
                                                                    notBefore: String,
                                                                    notAfter: String)? {
        guard payload.count > 5, payload[5] == 11 else { return nil }   // handshake type 11
        let handshakeLen = (Int(payload[6]) << 16) | (Int(payload[7]) << 8) | Int(payload[8])
        let handshakeEnd = min(payload.count, 9 + handshakeLen)
        guard handshakeEnd - 9 >= 3 else { return nil }
        let certsLen = (Int(payload[9]) << 16) | (Int(payload[10]) << 8) | Int(payload[11])
        var cursor = 12
        let certsEnd = min(handshakeEnd, cursor + certsLen)
        guard cursor + 3 <= certsEnd else { return nil }
        let certLen = (Int(payload[cursor]) << 16) | (Int(payload[cursor + 1]) << 8)
            | Int(payload[cursor + 2])
        cursor += 3
        guard cursor + certLen <= certsEnd else { return nil }
        let der = Array(payload[cursor..<(cursor + certLen)])
        return parseCertificate(der)
    }

    private struct TLValue {
        let tag: UInt8
        let value: [UInt8]
        let end: Int
    }

    private static func readTLV(_ bytes: [UInt8], at start: Int) -> TLValue? {
        guard start < bytes.count else { return nil }
        let tag = bytes[start]
        var cursor = start + 1
        guard cursor < bytes.count else { return nil }
        var length = Int(bytes[cursor])
        cursor += 1
        if length & 0x80 != 0 {
            let lenBytes = length & 0x7F
            guard lenBytes > 0, lenBytes <= 4, cursor + lenBytes <= bytes.count else { return nil }
            length = 0
            for _ in 0..<lenBytes {
                length = (length << 8) | Int(bytes[cursor])
                cursor += 1
            }
        }
        guard cursor + length <= bytes.count else { return nil }
        return TLValue(tag: tag, value: Array(bytes[cursor..<(cursor + length)]), end: cursor + length)
    }

    /// Finds the common name (OID 2.5.4.3) in a Name's content (SETs of
    /// attributes — callers pass the SEQUENCE content, which starts with the
    /// first SET directly).
    static func commonName(_ nameContent: [UInt8]) -> String? {
        var cursor = 0
        while cursor < nameContent.count {
            guard let set = readTLV(nameContent, at: cursor), set.tag == 0x31 else { break }
            var inner = 0
            while inner < set.value.count {
                guard let attr = readTLV(set.value, at: inner), attr.tag == 0x30 else { break }
                guard let oid = readTLV(attr.value, at: 0),
                      oid.tag == 0x06, oid.value == [0x55, 0x04, 0x03] else {
                    inner = attr.end
                    continue
                }
                // value follows the OID inside the attribute SEQUENCE
                if let value = readTLV(attr.value, at: oid.end),
                   value.tag == 0x0C || value.tag == 0x13 || value.tag == 0x16 {
                    return String(bytes: value.value, encoding: .utf8)
                }
                inner = attr.end
            }
            cursor = set.end
        }
        return nil
    }

    static func parseCertificate(_ der: [UInt8]) -> (subject: String, issuer: String,
                                                     notBefore: String, notAfter: String)? {
        guard der.count > 2, der[0] == 0x30 else { return nil }
        guard let outer = readTLV(der, at: 0), outer.tag == 0x30 else { return nil }
        // the tbs SEQUENCE begins after the outer TLV header (length may be
        // multi-byte, so derive the header size from the value length)
        let headerLen = der.count - outer.value.count
        guard let tbs = readTLV(der, at: headerLen), tbs.tag == 0x30 else { return nil }
        let body = tbs.value
        var cursor = 0
        var section = 0
        var issuerDER: [UInt8]?
        var validityDER: [UInt8]?
        var subjectDER: [UInt8]?
        while cursor < body.count, section < 4 {
            if body[cursor] == 0xA0 {
                guard let v = readTLV(body, at: cursor) else { break }
                cursor = v.end
                continue
            }
            guard let v = readTLV(body, at: cursor) else { break }
            if v.tag == 0x30 {
                switch section {
                case 0: break            // signature algorithm
                case 1: issuerDER = v.value
                case 2: validityDER = v.value
                case 3: subjectDER = v.value
                default: break
                }
                section += 1
            }
            cursor = v.end
        }
        var notBefore = "—"
        var notAfter = "—"
        if let validityDER {
            var vc = 0
            var times: [String] = []
            while vc < validityDER.count, times.count < 2 {
                guard let v = readTLV(validityDER, at: vc) else { break }
                if v.tag == 0x17 || v.tag == 0x18 {   // UTCTime / GeneralizedTime
                    times.append(String(bytes: v.value, encoding: .utf8) ?? "—")
                }
                vc = v.end
            }
            if times.count >= 2 {
                notBefore = times[0]
                notAfter = times[1]
            }
        }
        return (cn(subjectDER) ?? "—", cn(issuerDER) ?? "—", notBefore, notAfter)
    }

    private static func cn(_ nameDER: [UInt8]?) -> String? {
        guard let nameDER else { return nil }
        return commonName(nameDER)
    }

    // MARK: - HTTP

    private static func httpFirstLine(_ payload: [UInt8]) -> String? {
        guard payload.count >= 12 else { return nil }
        let head = String(bytes: payload.prefix(64), encoding: .utf8) ?? ""
        let methods = ["GET ", "POST ", "PUT ", "HEAD ", "DELETE ", "PATCH ", "OPTIONS ", "CONNECT ", "HTTP/"]
        guard methods.contains(where: head.hasPrefix) else { return nil }
        return head.split(separator: "\n").first.map(String.init) ?? nil
    }

    private static func protoName(_ p: UInt8) -> String {
        switch p {
        case 1: "ICMP"
        case 6: "TCP"
        case 17: "UDP"
        case 58: "ICMPv6"
        case 132: "SCTP"
        default: "IPPROTO_\(p)"
        }
    }

    // MARK: - Helpers

    private static func field(_ name: String, _ value: String, _ offset: Int, _ length: Int) -> PacketField {
        PacketField(id: "\(name)-\(offset)-\(length)", name: name, value: value,
                    offset: offset, length: length, detail: nil)
    }

    private static func layer(id: String, name: String, fields: [PacketField]) -> PacketLayer {
        PacketLayer(id: id, name: name, fields: fields)
    }
}
