import Foundation
import Testing
@testable import NetglassMac

@Suite struct CredentialScanTests {
    private func record(id: Int, protocolName: String = "TCP", port: UInt16? = 80,
                        info: String = "", bytes: [UInt8] = []) -> PacketRecord {
        PacketRecord(id: id, timestamp: Date(), deltaMs: 0,
                     source: "10.0.0.1", sourcePort: 51234,
                     destination: "93.184.216.34", destinationPort: port,
                     protocolName: protocolName, length: bytes.count,
                     info: info, rawBytes: bytes, layers: [])
    }

    @Test func httpAuthorizationDetected() {
        let payload = Array("GET /login HTTP/1.1\r\nHost: x\r\nAuthorization: Basic dXNlcjpwYXNz\r\n".utf8)
        let hits = CredentialScan.scan([record(id: 1, info: "GET /login HTTP/1.1", bytes: payload)])
        #expect(hits.contains { $0.kind == "http-auth" && $0.packetID == 1 })
    }

    @Test func urlCredentialsDetected() {
        let payload = Array("GET http://user:pass@example.com/ HTTP/1.1\r\n".utf8)
        let hits = CredentialScan.scan([record(id: 2, info: "GET http://user:pass@example.com/ HTTP/1.1", bytes: payload)])
        #expect(hits.contains { $0.kind == "url-credentials" })
    }

    @Test func plaintextProtocolDetected() {
        let payload = Array("USER dan\r\nPASS secret\r\n".utf8)
        let hits = CredentialScan.scan([record(id: 3, port: 21, info: "TCP", bytes: payload)])
        #expect(hits.contains { $0.kind == "plaintext-login" })
    }

    @Test func tlsNotFlaggedAsPlaintext() {
        let tlsHello: [UInt8] = [0x16, 0x03, 0x01] + Array(repeating: 0xAB, count: 20)
        let hits = CredentialScan.scan([record(id: 4, port: 443, info: "TLS", bytes: tlsHello)])
        #expect(!hits.contains { $0.kind == "plaintext-login" })
    }

    @Test func sensitiveDNSDetected() {
        let hits = CredentialScan.scan([record(id: 5, protocolName: "UDP", port: 53,
                                               info: "Standard query 0x2a41 login.example.com: type A")])
        #expect(hits.contains { $0.kind == "dns-sensitive" && $0.detail.contains("login.example.com") })
    }

    @Test func benignPacketsProduceNoHits() {
        let hits = CredentialScan.scan([
            record(id: 6, port: 443, info: "TLS", bytes: [0x16, 0x03, 0x01]),
            record(id: 7, protocolName: "UDP", port: 53, info: "Standard query 0x0001 www.example.com: type A"),
            record(id: 8, info: "GET /index.html HTTP/1.1", bytes: Array("GET /index.html HTTP/1.1\r\n".utf8)),
        ])
        #expect(hits.isEmpty)
    }
}
