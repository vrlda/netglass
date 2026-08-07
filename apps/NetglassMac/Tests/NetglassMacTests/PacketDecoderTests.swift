import Foundation
import Testing
@testable import NetglassMac

@Suite struct PacketDecoderTests {
    func ethFrame(ipv4: [UInt8]) -> RawPacket {
        var frame: [UInt8] = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x01,   // dst MAC
            0x00, 0x00, 0x00, 0x00, 0x00, 0x02,   // src MAC
            0x08, 0x00,                           // EtherType IPv4
        ]
        frame += ipv4
        return RawPacket(timestamp: Date(timeIntervalSince1970: 1700000000),
                         capturedLength: frame.count, linkType: 1, bytes: frame)
    }

    func tcpIPv4(src: String, dst: String, srcPort: UInt16, dstPort: UInt16,
                         payload: [UInt8] = []) -> RawPacket {
        let srcParts = src.split(separator: ".").map { UInt8($0)! }
        let dstParts = dst.split(separator: ".").map { UInt8($0)! }
        var ip: [UInt8] = [0x45, 0x00]
        ip += [0x00, 0x00]                       // total length (patched below)
        ip += [0x00, 0x01, 0x40, 0x00, 0x40, 0x06]
        ip += [0x00, 0x00]                       // checksum (ignored)
        ip += srcParts + dstParts
        var tcp: [UInt8] = [
            UInt8(srcPort >> 8), UInt8(srcPort & 0xFF),
            UInt8(dstPort >> 8), UInt8(dstPort & 0xFF),
            0, 0, 0, 1,                           // seq
            0, 0, 0, 1,                           // ack
            0x50, 0x18, 0x04, 0x00,               // data offset 5, PSH+ACK, window 1024
            0, 0,                                 // checksum
            0, 0,                                 // urgent pointer
        ]
        tcp += payload
        let total = UInt16(20 + tcp.count)
        ip[2] = UInt8(total >> 8)
        ip[3] = UInt8(total & 0xFF)
        return ethFrame(ipv4: ip + tcp)
    }

    func buildPacket(payload: [UInt8]) -> RawPacket {
        tcpIPv4(src: "192.168.1.42", dst: "149.154.167.51",
                srcPort: 51234, dstPort: 443, payload: payload)
    }

    @Test func decodesTcpOverEthernetIPv4() throws {
        let raw = tcpIPv4(src: "192.168.1.42", dst: "149.154.167.51",
                          srcPort: 51234, dstPort: 443)
        let record = PacketDecoders.decode(raw, number: 1)
        #expect(record.source == "192.168.1.42")
        #expect(record.destination == "149.154.167.51")
        #expect(record.sourcePort == 51234)
        #expect(record.destinationPort == 443)
        #expect(record.protocolName == "TCP")
        #expect(record.info.contains("51234 → 443"))
        #expect(record.layers.contains { $0.name.contains("Internet Protocol") })
        #expect(record.layers.contains { $0.name.contains("Transmission Control") })
    }

    @Test func extractsTlsSniFromClientHello() throws {
        // minimal ClientHello: record type 0x16, version 0x0301,
        // handshake ClientHello(1), then SNI extension
        var hello: [UInt8] = [0x16, 0x03, 0x01]
        var body: [UInt8] = [0x01, 0x00, 0x00, 0x00]   // handshake type + length placeholder
        body += [0x03, 0x03]                            // client version
        body += Array(repeating: 0x4a, count: 32)       // random
        body += [0x00]                                  // session id len
        body += [0x00, 0x02, 0x13, 0x01]                // cipher suites (2 bytes len + 1)
        body += [0x01, 0x00]                            // compression
        // extension: server_name
        let name = Array("telegram.org".utf8)
        var ext: [UInt8] = [0x00, 0x00]                 // type server_name
        ext += [0x00, UInt8(name.count + 5)]            // ext len
        ext += [0x00, UInt8(name.count + 3)]            // list len
        ext += [0x00]                                   // name type host
        ext += [0x00, UInt8(name.count)]
        ext += name
        body += [0x00, UInt8(ext.count)]                // extensions len
        body += ext
        let bodyLen = body.count - 4
        body[2] = UInt8(bodyLen >> 8)
        body[3] = UInt8(bodyLen & 0xFF)
        hello += [0x00, UInt8(body.count)]              // record length
        hello += body

        let raw = tcpIPv4(src: "192.168.1.42", dst: "149.154.167.51",
                          srcPort: 51234, dstPort: 443, payload: hello)
        let record = PacketDecoders.decode(raw, number: 1)
        #expect(record.protocolName == "TLS")
        #expect(record.info.contains("telegram.org"))
    }

    @Test func decodesDnsQuery() throws {
        // DNS query for "example.com" A over UDP
        var dns: [UInt8] = [0x2a, 0x41, 0x01, 0x00]          // id + flags (query)
        dns += [0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        dns += [0x07] + Array("example".utf8)
        dns += [0x03] + Array("com".utf8)
        dns += [0x00, 0x00, 0x01, 0x00, 0x01]                // A, IN
        var ip: [UInt8] = [0x45, 0x00, 0x00, 0x00, 0x00, 0x01, 0x40, 0x00,
                           0x40, 0x11, 0x00, 0x00,
                           192, 168, 1, 42, 8, 8, 8, 8]
        var udp: [UInt8] = [0xd0, 0x15, 0x00, 0x35]          // 53301 → 53
        udp += [0x00, UInt8(8 + dns.count)]
        udp += [0, 0]
        udp += dns
        let total = UInt16(20 + udp.count)
        ip[2] = UInt8(total >> 8)
        ip[3] = UInt8(total & 0xFF)
        let raw = RawPacket(timestamp: Date(timeIntervalSince1970: 1700000000),
                            capturedLength: 14 + ip.count + udp.count,
                            linkType: 1, bytes: ethFrame(ipv4: ip + udp).bytes)
        let record = PacketDecoders.decode(raw, number: 1)
        #expect(record.protocolName == "DNS")
        #expect(record.info.contains("example.com"))
        #expect(record.info.contains("Standard query"))
    }

    @Test func decodesHttpFirstLine() throws {
        let payload = Array("GET /api/v2 HTTP/1.1\r\nHost: telegram.org\r\n".utf8)
        let raw = tcpIPv4(src: "192.168.1.42", dst: "149.154.167.51",
                          srcPort: 51234, dstPort: 80, payload: payload)
        let record = PacketDecoders.decode(raw, number: 1)
        #expect(record.protocolName == "HTTP")
        #expect(record.info.hasPrefix("GET /api/v2"))
    }
}
