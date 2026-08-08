import Foundation
import Testing
@testable import FlowSource

@Suite struct LsofParserTests {
    private let parser = LsofParser()

    @Test func parsesSocketRow() throws {
        let line = "Telegram  9217 danil 10u  IPv4 0x1 0t0 0 TCP 192.168.1.42:51234->149.154.167.51:443 (ESTABLISHED)"
        let sockets = parser.parse(line)
        #expect(sockets.count == 1)
        let socket = try #require(sockets.first)
        #expect(socket.pid == 9217)
        #expect(socket.processName == "Telegram")
        #expect(socket.transport == .tcp)
        #expect(socket.local.address.text == "192.168.1.42")
        #expect(socket.remote.address.text == "149.154.167.51")
        #expect(socket.remote.port == 443)
    }

    @Test func parsesBracketedIPv6() throws {
        let line = "Safari  8810 danil 11u  IPv6 0x2 0t0 0 TCP [fe80::1]:51235->[2001:db8::1]:443 (ESTABLISHED)"
        let socket = try #require(parser.parse(line).first)
        #expect(socket.local.address.text == "fe80::1")
        #expect(socket.remote.address.text == "2001:db8::1")
        #expect(socket.remote.port == 443)
    }

    @Test func parsesUDPWithoutState() throws {
        let line = "mDNSRespo 690 _mdns 12u IPv4 0x3 0t0 0 UDP 192.168.1.42:5353->239.255.255.250:1900"
        let socket = try #require(parser.parse(line).first)
        #expect(socket.transport == .udp)
        #expect(socket.remote.address.text == "239.255.255.250")
    }

    @Test func skipsHeaderAndListeners() {
        let text = """
        COMMAND   PID USER   FD   TYPE  DEVICE  SIZE/OFF NODE NAME
        Finder    987  danil 13u  IPv4 0x4 0t0 0 TCP *:51560 (LISTEN)
        rapportd  1178 danil 10u IPv4 0x5 0t0 0 TCP *:51560 (LISTEN)
        identitys 1189 danil 10u IPv4 0x6 0t0 0 UDP *:*
        """
        #expect(parser.parse(text).isEmpty)
    }

    @Test func readsRealFixture() throws {
        let url = try FixtureLocator.repoRoot()
            .appendingPathComponent("Fixtures/lsof/capture-1.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        let sockets = parser.parse(text)
        #expect(sockets.count > 0)   // 163-line live capture, listeners/wildcards filtered
    }

    @Test func parsesListeners() {
        let text = """
        COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        python3 4242 dan   10u  IPv4 0x1    0t0     0  TCP 0.0.0.0:8000 (LISTEN)
        sshd    999  root   3u  IPv6 0x2    0t0     0  TCP [::1]:2222 (LISTEN)
        python3 4242 dan   11u  IPv4 0x3    0t0     0  TCP 127.0.0.1:9000 (LISTEN)
        rapportd 123  dan   12u  IPv4 0x4    0t0     0  TCP *:51560 (LISTEN)
        """
        let listeners = LsofParser().parseListeners(text)
        #expect(listeners.count == 4)
        #expect(listeners[0].processName == "python3")
        #expect(listeners[0].pid == 4242)
        #expect(listeners[0].address == "0.0.0.0")
        #expect(listeners[0].port == 8000)
        #expect(listeners[1].address == "::1")
        #expect(listeners[1].port == 2222)
        #expect(listeners[2].address == "127.0.0.1")
        let rapportd = listeners.first { $0.processName == "rapportd" }
        #expect(rapportd?.address == "*")
        #expect(rapportd?.port == 51560)
        #expect(rapportd?.exposure == .allInterfaces)
    }

    @Test func listenerExposure() {
        func listener(_ address: String) -> LsofListener {
            LsofListener(pid: 1, processName: "sshd", transport: .tcp, address: address, port: 22)
        }
        #expect(listener("0.0.0.0").exposure == .allInterfaces)
        #expect(listener("::").exposure == .allInterfaces)
        #expect(listener("*").exposure == .allInterfaces)
        #expect(listener("127.0.0.1").exposure == .loopback)
        #expect(listener("::1").exposure == .loopback)
        #expect(listener("192.168.1.5").exposure == .specific)
    }
}
