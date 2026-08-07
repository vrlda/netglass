import Foundation

/// Writes decoded packets back to a classic pcap file (linktype 1, Ethernet).
/// Used for exporting selected packets from the inspector.
public enum PcapWriter {
    public static func write(packets: [PacketRecord], to url: URL) throws {
        var data = Data()
        // global header (little-endian, µs timestamps, snaplen 65535, Ethernet)
        data.append(contentsOf: [0xd4, 0xc3, 0xb2, 0xa1])
        data.append(contentsOf: [0x02, 0x00, 0x04, 0x00])
        data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        data.append(contentsOf: [0xff, 0xff, 0x00, 0x00])
        data.append(contentsOf: [0x01, 0x00, 0x00, 0x00])

        for packet in packets {
            let seconds = Int64(packet.timestamp.timeIntervalSince1970)
            let micros = Int32((packet.timestamp.timeIntervalSince1970
                - Double(seconds)) * 1_000_000)
            data.append(contentsOf: u32(UInt32(seconds)))
            data.append(contentsOf: u32(UInt32(micros)))
            data.append(contentsOf: u32(UInt32(packet.rawBytes.count)))
            data.append(contentsOf: u32(UInt32(packet.rawBytes.count)))
            data.append(contentsOf: packet.rawBytes)
        }
        try data.write(to: url, options: .atomic)
    }

    private static func u32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
         UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }
}
