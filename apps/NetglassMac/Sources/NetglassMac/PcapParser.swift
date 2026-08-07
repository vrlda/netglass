import Foundation

/// One raw captured packet (link-layer frame), before protocol decoding.
public struct RawPacket: Equatable, Sendable {
    public let timestamp: Date
    public let capturedLength: Int
    public let linkType: Int
    public let bytes: [UInt8]
}

/// Minimal pcap (libpcap) and pcapng reader — enough for tcpdump output and
/// Wireshark-compatible files. Pure, deterministic, testable.
public enum PcapParser {
    public enum ParseError: Error, Equatable {
        case tooShort
        case unknownFormat
        case truncatedRecord
        case noInterfaceDescription
    }

    private static let pcapMagicLE: [UInt8] = [0xd4, 0xc3, 0xb2, 0xa1]
    private static let pcapMagicBE: [UInt8] = [0xa1, 0xb2, 0xc3, 0xd4]
    private static let pcapMagicNanosecLE: [UInt8] = [0x4d, 0x3c, 0xb2, 0xa1]
    private static let pcapngMagic: [UInt8] = [0x0a, 0x0d, 0x0d, 0x0a]

    public static func parse(_ data: Data) throws -> [RawPacket] {
        guard data.count >= 4 else { throw ParseError.tooShort }
        let magic = [UInt8](data.prefix(4))
        if magic == pcapMagicLE || magic == pcapMagicNanosecLE {
            return try parsePcap(data, littleEndian: true, nanosec: magic == pcapMagicNanosecLE)
        }
        if magic == pcapMagicBE {
            return try parsePcap(data, littleEndian: false, nanosec: false)
        }
        if magic == pcapngMagic {
            return try parsePcapng(data)
        }
        throw ParseError.unknownFormat
    }

    // MARK: - Classic pcap

    private static func parsePcap(_ data: Data, littleEndian: Bool,
                                  nanosec: Bool) throws -> [RawPacket] {
        guard data.count >= 24 else { throw ParseError.tooShort }
        let network = u32(data, at: 20, littleEndian: littleEndian)
        let linkType = Int(network & 0xFFFF)
        var packets: [RawPacket] = []
        var offset = 24
        while offset + 16 <= data.count {
            let tsSec = u32(data, at: offset, littleEndian: littleEndian)
            let tsFrac = u32(data, at: offset + 4, littleEndian: littleEndian)
            let inclLen = Int(u32(data, at: offset + 8, littleEndian: littleEndian))
            let origLen = Int(u32(data, at: offset + 12, littleEndian: littleEndian))
            offset += 16
            guard offset + inclLen <= data.count else { throw ParseError.truncatedRecord }
            let bytes = [UInt8](data[offset..<(offset + inclLen)])
            offset += inclLen
            let seconds = TimeInterval(tsSec) + TimeInterval(tsFrac) / (nanosec ? 1_000_000_000 : 1_000_000)
            packets.append(RawPacket(timestamp: Date(timeIntervalSince1970: seconds),
                                     capturedLength: inclLen,
                                     linkType: linkType,
                                     bytes: bytes))
            _ = origLen
        }
        return packets
    }

    // MARK: - pcapng

    private static func parsePcapng(_ data: Data) throws -> [RawPacket] {
        var packets: [RawPacket] = []
        var linkTypes: [Int: Int] = [:]   // interface id → link type
        var offset = 0
        while offset + 12 <= data.count {
            let blockType = u32(data, at: offset, littleEndian: true)
            let totalLength = Int(u32(data, at: offset + 4, littleEndian: true))
            guard totalLength >= 12, offset + totalLength <= data.count else {
                throw ParseError.truncatedRecord
            }
            let body = offset + 8
            switch blockType {
            case 0x00000001:   // Interface Description Block
                // linktype is a u16 at the start of the block body
                let linkType = Int(u16(data, at: body, littleEndian: true))
                let ifID = linkTypes.count
                linkTypes[ifID] = linkType
            case 0x00000003:   // Simple Packet Block
                if let linkType = linkTypes[0] {
                    let origLen = Int(u32(data, at: body, littleEndian: true))
                    let dataLen = min(origLen, totalLength - 16)
                    let bytes = [UInt8](data[body + 4..<(body + 4 + dataLen)])
                    packets.append(RawPacket(timestamp: Date(timeIntervalSince1970: 0),
                                             capturedLength: dataLen,
                                             linkType: linkType,
                                             bytes: bytes))
                }
            case 0x00000006:   // Enhanced Packet Block
                let ifID = Int(u32(data, at: body, littleEndian: true))
                let tsHigh = u32(data, at: body + 4, littleEndian: true)
                let tsLow = u32(data, at: body + 8, littleEndian: true)
                let capLen = Int(u32(data, at: body + 12, littleEndian: true))
                guard let linkType = linkTypes[ifID] else {
                    throw ParseError.noInterfaceDescription
                }
                let dataStart = body + 20
                guard dataStart + capLen <= offset + totalLength else {
                    throw ParseError.truncatedRecord
                }
                let bytes = [UInt8](data[dataStart..<(dataStart + capLen)])
                let seconds = TimeInterval(tsHigh) * 4_294_967_296 + TimeInterval(tsLow)
                packets.append(RawPacket(timestamp: Date(timeIntervalSince1970: seconds / 1_000_000),
                                         capturedLength: capLen,
                                         linkType: linkType,
                                         bytes: bytes))
            default:
                break
            }
            offset += totalLength
        }
        return packets
    }

    private static func u16(_ data: Data, at offset: Int, littleEndian: Bool) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        let bytes = [UInt8](data[offset..<(offset + 2)])
        if littleEndian {
            return UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        }
        return UInt16(bytes[1]) | UInt16(bytes[0]) << 8
    }

    private static func u32(_ data: Data, at offset: Int, littleEndian: Bool) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let bytes = [UInt8](data[offset..<(offset + 4)])
        if littleEndian {
            return UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        }
        return UInt32(bytes[3]) | UInt32(bytes[2]) << 8
            | UInt32(bytes[1]) << 16 | UInt32(bytes[0]) << 24
    }
}
