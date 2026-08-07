import Foundation
import Testing
@testable import NetglassMac

@Suite struct PcapParserTests {
    /// A tiny pcap: global header + one Ethernet/IPv4/TCP record.
    private func pcapBytes(with packet: [UInt8]) -> Data {
        var data = Data()
        data.append(contentsOf: [0xd4, 0xc3, 0xb2, 0xa1])   // magic LE
        data.append(contentsOf: [0x02, 0x00, 0x04, 0x00])   // version 2.4
        data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        data.append(contentsOf: [0xff, 0xff, 0x00, 0x00])   // snaplen 65535
        data.append(contentsOf: [0x01, 0x00, 0x00, 0x00])   // linktype 1 (Ethernet)
        // record header: ts_sec=1700000000, ts_usec=123456, incl=len, orig=len
        data.append(contentsOf: [0x00, 0xf1, 0x53, 0x65])   // 1700000000 LE
        data.append(contentsOf: [0x40, 0xe2, 0x01, 0x00])   // 123456 LE
        data.append(contentsOf: withUnsafeBytes(of: UInt32(packet.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(packet.count).littleEndian) { Array($0) })
        data.append(contentsOf: packet)
        return data
    }

    @Test func parsesClassicPcap() throws {
        let packet: [UInt8] = Array(repeating: 0xAB, count: 64)
        let parsed = try PcapParser.parse(pcapBytes(with: packet))
        #expect(parsed.count == 1)
        #expect(parsed[0].linkType == 1)
        #expect(parsed[0].capturedLength == 64)
        #expect(parsed[0].bytes == packet)
        #expect(parsed[0].timestamp.timeIntervalSince1970 == 1700000000.123456)
    }

    @Test func rejectsUnknownFormat() {
        #expect(throws: PcapParser.ParseError.unknownFormat) {
            _ = try PcapParser.parse(Data([0x00, 0x01, 0x02, 0x03]))
        }
    }

    @Test func rejectsTruncatedRecord() {
        // record header claims 100 bytes but only 10 follow
        var data = pcapBytes(with: Array(repeating: 0x00, count: 10))
        data.replaceSubrange(32..<36, with: withUnsafeBytes(of: UInt32(100).littleEndian) { Array($0) })
        #expect(throws: PcapParser.ParseError.truncatedRecord) {
            _ = try PcapParser.parse(data)
        }
    }

    @Test func parsesPcapng() throws {
        // SHB
        var data = Data()
        data.append(contentsOf: [0x0a, 0x0d, 0x0d, 0x0a])
        data.append(contentsOf: withUnsafeBytes(of: UInt32(28).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x1A2B3C4D).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(28).littleEndian) { Array($0) })
        // IDB (linktype 1): type(4) len(4) linktype(2) reserved(2) snaplen(4) len(4)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(20).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(65535).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(20).littleEndian) { Array($0) })
        // EPB: 32 bytes of payload
        let payload = Array(repeating: UInt8(0xCD), count: 32)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(6).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(64).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })      // ts high
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1_700_000_000).littleEndian) { Array($0) })   // ts low µs
        data.append(contentsOf: withUnsafeBytes(of: UInt32(32).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(32).littleEndian) { Array($0) })
        data.append(contentsOf: payload)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(64).littleEndian) { Array($0) })

        let parsed = try PcapParser.parse(data)
        #expect(parsed.count == 1)
        #expect(parsed[0].linkType == 1)
        #expect(parsed[0].bytes == payload)
        #expect(parsed[0].timestamp.timeIntervalSince1970 == 1700.0)   // ts 1_700_000_000 µs
    }
}
