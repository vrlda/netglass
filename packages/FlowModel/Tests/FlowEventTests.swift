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
        #expect(TransportProtocol.icmp.rawValue == "icmp")
        #expect(TransportProtocol.other.rawValue == "other")
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

    @Test func identityInequality() {
        let base = ProcessIdentity(pid: 9217, startTime: nil,
                                   executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                                   bundleIdentifier: "org.telegram.desktop", parentPID: nil)
        let differentPID = ProcessIdentity(pid: 9218, startTime: nil,
                                           executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                                           bundleIdentifier: "org.telegram.desktop", parentPID: nil)
        #expect(base != differentPID)
    }
}

@Suite struct FlowEventTests {
    private func opened() throws -> FlowEvent.FlowOpened {
        FlowEvent.FlowOpened(
            flowID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
            process: ProcessIdentity(
                pid: 9217,
                startTime: nil,
                executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                bundleIdentifier: "org.telegram.desktop",
                parentPID: nil
            ),
            pid: 9217,
            transport: .tcp,
            local: NetworkEndpoint(address: try #require(IPAddress(text: "192.168.1.42")), port: 51234),
            remote: NetworkEndpoint(address: try #require(IPAddress(text: "149.154.167.51")), port: 443),
            interface: "en0",
            startedAt: Date(timeIntervalSince1970: 1_752_800_000.125),
            bytesSent: 3400,
            bytesReceived: 1200
        )
    }

    @Test func openedCarriesInterface() throws {
        let event: FlowEvent = .flowOpened(try opened())
        guard case .flowOpened(let payload) = event else { Issue.record("not opened"); return }
        #expect(payload.interface == "en0")
    }

    @Test func flowOpenedCodableRoundTrip() throws {
        let event: FlowEvent = .flowOpened(try opened())
        let data = try FlowJSON.encoder.encode(event)
        let decoded = try FlowJSON.decoder.decode(FlowEvent.self, from: data)
        #expect(decoded == event)
    }

    @Test func encodingIsDeterministic() throws {
        let event: FlowEvent = .flowOpened(try opened())
        let first = try FlowJSON.encoder.encode(event)
        let second = try FlowJSON.encoder.encode(event)
        #expect(first == second)
    }

    @Test func datesKeepFractionalSeconds() throws {
        let event: FlowEvent = .flowOpened(try opened())
        let data = try FlowJSON.encoder.encode(event)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains(".125Z"))   // ISO8601 with fractional seconds
    }

    @Test func goldenWireFormat() throws {
        let event: FlowEvent = .flowOpened(try opened())
        let data = try FlowJSON.encoder.encode(event)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("\"flowOpened\":{"))
        #expect(!text.contains("_0"))                       // no compiler artifact
        #expect(text.contains("\"address\":\"192.168.1.42\""))  // IP as text
        #expect(text.contains("\"transport\":\"tcp\""))
        #expect(text.contains("\"startedAt\":\"2025-07-18T00:53:20.125Z\""))
    }

    @Test func allCasesRoundTrip() throws {
        let cases: [FlowEvent] = [
            .flowOpened(try opened()),
            .flowUpdated(.init(flowID: UUID(), bytesSent: 5000, bytesReceived: 2000, observedAt: Date(timeIntervalSince1970: 1_752_800_010))),
            .flowClosed(.init(flowID: UUID(), endedAt: Date(timeIntervalSince1970: 1_752_800_020))),
        ]
        for event in cases {
            let data = try FlowJSON.encoder.encode(event)
            let decoded = try FlowJSON.decoder.decode(FlowEvent.self, from: data)
            #expect(decoded == event)
        }
    }
}
