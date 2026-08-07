import Foundation
import Testing
@testable import NetglassMac

@Suite struct GeoIPv6Tests {
    @Test func parsesIpv6Literals() {
        let bytes = GeoIP.ipv6ToBytes("2001:4860:4860::8888")
        #expect(bytes != nil)
        #expect(bytes!.count == 16)
        #expect(bytes![0] == 0x20 && bytes![1] == 0x01)
        #expect(bytes![14] == 0x88 && bytes![15] == 0x88)
        #expect(GeoIP.ipv6ToBytes("::1")![15] == 1)
        #expect(GeoIP.ipv6ToBytes("fe80::1%en0") == nil)      // zone rejected
        #expect(GeoIP.ipv6ToBytes("not-an-ip") == nil)
        #expect(GeoIP.ipv6ToBytes("1:2:3:4:5:6:7:8:9") == nil) // too many groups
    }

    @Test func looksUpIpv6Prefixes() {
        #expect(GeoIP.lookup("2001:4860:4860::8888")?.asn == "AS15169")     // Google DNS
        #expect(GeoIP.lookup("2606:4700:4700::1111")?.asn == "AS13335")     // Cloudflare
        #expect(GeoIP.lookup("2001:b28::1")?.organization.contains("Telegram") == true)
        #expect(GeoIP.lookup("fd7a:115c:a1e0::bc01:dd18")?.organization.contains("Tailscale") == true)
        #expect(GeoIP.lookup("2001:db8::1") == nil)                          // documentation range
        #expect(GeoIP.lookup("2400:cb00::1") == nil)                         // unknown
    }
}

@Suite struct TLSCertificateTests {
    /// Builds a minimal DER certificate: SEQUENCE { SEQUENCE (tbs) , signature }
    /// with issuer/subject CNs and validity times inside the tbs.
    private func der(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] {
        var len = body.count
        var header: [UInt8] = [tag]
        if len < 128 {
            header.append(UInt8(len))
        } else {
            var bytes: [UInt8] = []
            while len > 0 {
                bytes.insert(UInt8(len & 0xFF), at: 0)
                len >>= 8
            }
            header.append(UInt8(0x80 | bytes.count))
            header += bytes
        }
        return header + body
    }

    private func oid(_ bytes: UInt8...) -> [UInt8] { der(0x06, bytes) }

    private func name(_ cn: String) -> [UInt8] {
        let cnOID = oid(0x55, 0x04, 0x03)
        let value = der(0x0C, Array(cn.utf8))
        let attr = der(0x30, cnOID + value)
        let set = der(0x31, attr)
        return der(0x30, set)
    }

    private func time(_ value: String) -> [UInt8] { der(0x17, Array(value.utf8)) }

    private func cert(subject: String, issuer: String) -> [UInt8] {
        let serial = der(0x02, [0x01])
        let signature = der(0x30, oid(0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B))
        let issuerName = name(issuer)
        let validity = der(0x30, time("260101000000Z") + time("360101000000Z"))
        let subjectName = name(subject)
        let spki = der(0x30, der(0x30, oid(0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01))
            + der(0x03, [0x00, 0x00]))
        let tbs = der(0x30, serial + signature + issuerName + validity + subjectName + spki)
        return der(0x30, tbs + der(0x30, oid(0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B)))
    }

    @Test func parsesCertificateNamesAndValidity() throws {
        let der = cert(subject: "telegram.org", issuer: "Cloudflare Inc ECC CA-3")
        let parsed = try #require(PacketDecoders.parseCertificate(der))
        #expect(parsed.subject == "telegram.org")
        #expect(parsed.issuer == "Cloudflare Inc ECC CA-3")
        #expect(parsed.notBefore == "260101000000Z")
        #expect(parsed.notAfter == "360101000000Z")
    }

    @Test func rejectsNonCertificate() {
        #expect(PacketDecoders.parseCertificate([0x01, 0x02, 0x03]) == nil)
        #expect(PacketDecoders.decodeTLSCertificate([0x16, 0x03, 0x01, 0x00, 0x01, 0x02]) == nil)
    }
}

@Suite struct StreamReassemblerTests {
    private func record(id: Int, src: String, srcPort: UInt16,
                        dst: String, dstPort: UInt16,
                        payload: [UInt8], protocolName: String = "TCP") -> PacketRecord {
        // real Ethernet/IPv4/TCP frame so the reassembler can locate payloads
        let srcParts = src.split(separator: ".").map { UInt8($0)! }
        let dstParts = dst.split(separator: ".").map { UInt8($0)! }
        var ip: [UInt8] = [0x45, 0x00, 0x00, 0x00, 0x00, 0x01, 0x40, 0x00,
                           0x40, 0x06, 0x00, 0x00] + srcParts + dstParts
        var tcp: [UInt8] = [
            UInt8(srcPort >> 8), UInt8(srcPort & 0xFF),
            UInt8(dstPort >> 8), UInt8(dstPort & 0xFF),
            0, 0, 0, 1, 0, 0, 0, 1,
            0x50, 0x18, 0x04, 0x00, 0, 0, 0, 0,
        ]
        tcp += payload
        let total = UInt16(20 + tcp.count)
        ip[2] = UInt8(total >> 8)
        ip[3] = UInt8(total & 0xFF)
        var frame: [UInt8] = [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 2, 0x08, 0x00]
        frame += ip + tcp
        return PacketRecord(id: id, timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
                            deltaMs: 0, source: src, sourcePort: srcPort,
                            destination: dst, destinationPort: dstPort,
                            protocolName: protocolName, length: frame.count,
                            info: "", rawBytes: frame, layers: [])
    }

    @Test func endpointsIdentifyClientByHigherPort() throws {
        let packet = record(id: 1, src: "192.168.1.42", srcPort: 51234,
                            dst: "149.154.167.51", dstPort: 443, payload: [])
        let endpoints = try #require(StreamReassembler.endpoints(packet: packet))
        #expect(endpoints.client == "192.168.1.42:51234")
        #expect(endpoints.server == "149.154.167.51:443")
    }

    @Test func reassemblesBothDirections() throws {
        let clientHello = Array("GET / HTTP/1.1\r\nHost: t\r\n\r\n".utf8)
        let serverHello = Array("HTTP/1.1 200 OK\r\n".utf8)
        let packets = [
            record(id: 1, src: "192.168.1.42", srcPort: 51234,
                   dst: "149.154.167.51", dstPort: 443, payload: clientHello),
            record(id: 2, src: "149.154.167.51", srcPort: 443,
                   dst: "192.168.1.42", dstPort: 51234, payload: serverHello),
        ]
        let stream = StreamReassembler.reassemble(packets: packets, for: packets[0])
        #expect(stream.clientToServer.bytes == clientHello)
        #expect(stream.serverToClient.bytes == serverHello)
        #expect(stream.clientToServer.packets == [1])
        #expect(stream.totalBytes == clientHello.count + serverHello.count)
    }

    @Test func nonTcpProtocolsYieldEmpty() {
        let packet = record(id: 1, src: "10.0.0.1", srcPort: 1, dst: "10.0.0.2", dstPort: 2,
                            payload: [], protocolName: "ICMP")
        let stream = StreamReassembler.reassemble(packets: [packet], for: packet)
        #expect(stream.totalBytes == 0)
    }
}

@Suite struct PcapWriterTests {
    @Test func roundTripsThroughParser() throws {
        let packet = PacketRecord(id: 1, timestamp: Date(timeIntervalSince1970: 1_700_000_000.5),
                                  deltaMs: 0, source: "192.168.1.42", sourcePort: 51234,
                                  destination: "149.154.167.51", destinationPort: 443,
                                  protocolName: "TCP", length: 64,
                                  info: "test", rawBytes: Array(repeating: 0xAB, count: 64),
                                  layers: [])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("netglass-write-\(UUID().uuidString).pcap")
        defer { try? FileManager.default.removeItem(at: url) }
        try PcapWriter.write(packets: [packet], to: url)
        let data = try Data(contentsOf: url)
        let parsed = try PcapParser.parse(data)
        #expect(parsed.count == 1)
        #expect(parsed[0].bytes == packet.rawBytes)
        #expect(parsed[0].linkType == 1)
        #expect(abs(parsed[0].timestamp.timeIntervalSince1970 - 1_700_000_000.5) < 0.001)
    }
}
