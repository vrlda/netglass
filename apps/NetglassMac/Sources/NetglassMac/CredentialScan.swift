import Foundation

/// A likely plaintext-sensitive protocol use found in an inspected capture.
/// Payload analysis is opt-in by construction: it only runs on capture files
/// the user opened in the Packet Inspector — nothing is sniffed live.
public struct CredentialHit: Identifiable, Equatable, Sendable {
    public let id: String
    public let packetID: Int
    public let kind: String      // http-auth | url-credentials | plaintext-login | dns-sensitive
    public let detail: String
    public let protocolName: String
    public let destination: String
}

public enum CredentialScan {
    /// Tokens for login-style plaintext payloads (FTP/Telnet/POP3/IMAP lines
    /// like USER/PASS). `user`/`pass` are too noisy for DNS names, so DNS
    /// uses the narrower list below.
    private static let payloadTokens = ["password", "login", "auth", "token", "secret", "credential",
                                        "user", "pass"]
    private static let dnsTokens = ["password", "login", "auth", "token", "secret", "credential"]
    private static let plaintextPorts: Set<UInt16> = [21, 23, 25, 80, 110, 143]

    public static func scan(_ packets: [PacketRecord]) -> [CredentialHit] {
        var hits: [CredentialHit] = []
        for packet in packets {
            let text = String(decoding: packet.rawBytes, as: UTF8.self)
            let lower = text.lowercased()
            if lower.contains("authorization:") || lower.contains("cookie:") {
                hits.append(hit(packet, kind: "http-auth",
                                detail: "Authorization/Cookie header in plaintext"))
            }
            if lower.contains("@") && (lower.contains("http://") || lower.contains("https://")) {
                hits.append(hit(packet, kind: "url-credentials",
                                detail: "URL with embedded credentials"))
            }
            if let port = packet.destinationPort,
               plaintextPorts.contains(port),
               packet.protocolName != "UDP",
               !isTLS(packet.rawBytes),
               payloadTokens.contains(where: { lower.contains($0) }) {
                hits.append(hit(packet, kind: "plaintext-login",
                                detail: "Plaintext protocol on port \(port)"))
            }
            if let name = dnsQueryName(from: packet.info),
               dnsTokens.contains(where: { name.lowercased().contains($0) }) {
                hits.append(hit(packet, kind: "dns-sensitive",
                                detail: "DNS query \(name)"))
            }
        }
        return hits
    }

    private static func hit(_ packet: PacketRecord, kind: String, detail: String) -> CredentialHit {
        CredentialHit(id: "\(packet.id)-\(kind)", packetID: packet.id, kind: kind,
                      detail: detail, protocolName: packet.protocolName,
                      destination: "\(packet.destination):\(packet.destinationPort.map(String.init) ?? "?")")
    }

    /// TLS records start with 0x16 0x03 (handshake, TLS 1.x).
    static func isTLS(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 3 && bytes[0] == 0x16 && bytes[1] == 0x03
    }

    /// Extracts the query name from the decoder's DNS info string, e.g.
    /// "Standard query 0x2a41 login.example.com: type A" or a response
    /// "Standard response 0x2a41 example.com → 1.2.3.4".
    static func dnsQueryName(from info: String) -> String? {
        let text = info.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("Standard query 0x") || text.hasPrefix("Standard response 0x"),
              let idRange = text.range(of: "0x") else { return nil }
        let afterID = text.index(idRange.lowerBound, offsetBy: 6, limitedBy: text.endIndex)
            ?? text.endIndex
        guard afterID < text.endIndex else { return nil }
        var cursor = afterID
        while cursor < text.endIndex, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        let namePart = text[cursor...]
        guard let name = namePart.split(whereSeparator: { $0 == ":" || $0 == "→" }).first else {
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
