import Foundation
import Testing
@testable import FlowModel

@Suite struct NetworkEndpointTests {
    @Test func endpointHoldsBinaryAddressAndPort() throws {
        let address = try #require(IPAddress(text: "149.154.167.51"))
        let endpoint = NetworkEndpoint(address: address, port: 443)
        #expect(endpoint.port == 443)
        #expect(endpoint.address.bytes == [149, 154, 167, 51])
        #expect(endpoint == NetworkEndpoint(address: address, port: 443))
        #expect(endpoint != NetworkEndpoint(address: address, port: 444))
    }

    @Test func transportRawValues() {
        #expect(TransportProtocol.tcp.rawValue == "tcp")
        #expect(TransportProtocol(rawValue: "udp") == .udp)
        #expect(TransportProtocol(rawValue: "bogus") == nil)
    }
}

@Suite struct ProcessIdentityTests {
    @Test func identityIsHashableAndCodable() throws {
        let identity = ProcessIdentity(
            pid: 9217,
            startTime: nil,
            executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
            bundleIdentifier: "org.telegram.desktop",
            parentPID: 1
        )
        let data = try JSONEncoder().encode(identity)
        let decoded = try JSONDecoder().decode(ProcessIdentity.self, from: data)
        #expect(decoded == identity)
        #expect(Set([identity, identity]).count == 1)
    }
}
