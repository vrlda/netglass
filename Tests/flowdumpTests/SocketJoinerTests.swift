import Foundation
import FlowModel
import Testing
@testable import flowdump

@Suite struct SocketJoinerTests {
    private func connection(_ transport: TransportProtocol, local: String, remote: String,
                            bytesIn: UInt64 = 100, bytesOut: UInt64 = 200) throws -> NettopConnection {
        NettopConnection(
            transport: transport,
            local: NetworkEndpoint(address: try #require(IPAddress(text: local)), port: 51234),
            remote: NetworkEndpoint(address: try #require(IPAddress(text: remote)), port: 443),
            interface: "en0", state: "Established",
            bytesIn: bytesIn, bytesOut: bytesOut)
    }

    private func socket(_ pid: Int32, _ name: String, transport: TransportProtocol,
                        local: String, remote: String) throws -> LsofSocket {
        LsofSocket(pid: pid, processName: name, transport: transport,
                   local: NetworkEndpoint(address: try #require(IPAddress(text: local)), port: 51234),
                   remote: NetworkEndpoint(address: try #require(IPAddress(text: remote)), port: 443))
    }

    @Test func joinsConnectionToSocket() throws {
        let c = try connection(.tcp, local: "192.168.1.42", remote: "149.154.167.51")
        let s = try socket(9217, "Telegram", transport: .tcp, local: "192.168.1.42", remote: "149.154.167.51")
        let rows = SocketJoiner().join(connections: [c], sockets: [s])
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.pid == 9217)
        #expect(row.processName == "Telegram")
        #expect(row.transport == .tcp)
        #expect(row.bytesIn == 100)
        #expect(row.bytesOut == 200)
        #expect(row.state == "Established")
    }

    @Test func joinsQUICConnectionToUDPSocket() throws {
        let c = try connection(.quic, local: "192.168.1.134", remote: "8.47.69.0")
        let s = try socket(700, "Chrome", transport: .udp, local: "192.168.1.134", remote: "8.47.69.0")
        let rows = SocketJoiner().join(connections: [c], sockets: [s])
        #expect(rows.count == 1)
        #expect(rows[0].transport == .quic)   // transport preserved from nettop
        #expect(rows[0].pid == 700)
    }

    @Test func unmatchedConnectionDropped() throws {
        let c = try connection(.tcp, local: "192.168.1.42", remote: "149.154.167.51")
        let s = try socket(5, "Other", transport: .tcp, local: "10.0.0.1", remote: "8.8.8.8")
        #expect(SocketJoiner().join(connections: [c], sockets: [s]).isEmpty)
    }

    @Test func doesNotJoinSameEndpointsAcrossProtocols() throws {
        let c = try connection(.tcp, local: "192.168.1.42", remote: "149.154.167.51")
        let s = try socket(5, "Other", transport: .udp, local: "192.168.1.42", remote: "149.154.167.51")
        #expect(SocketJoiner().join(connections: [c], sockets: [s]).isEmpty)
    }

    @Test func joinsSyntheticFixturesEndToEnd() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let nettopText = try String(contentsOf: base.appendingPathComponent("Fixtures/nettop/synthetic.txt"), encoding: .utf8)
        let lsofText = try String(contentsOf: base.appendingPathComponent("Fixtures/lsof/synthetic.txt"), encoding: .utf8)
        let connections = NettopParser().parse(nettopText)
        let sockets = LsofParser().parse(lsofText)
        let rows = SocketJoiner().join(connections: connections, sockets: sockets)
        #expect(rows.count == 2)   // Telegram TCP 443 (9217) + mDNSRespo UDP 5353 (690) joined; Safari/Finder unmatched
        #expect(rows.contains { $0.pid == 9217 })
        #expect(rows.contains { $0.pid == 690 })
    }
}
