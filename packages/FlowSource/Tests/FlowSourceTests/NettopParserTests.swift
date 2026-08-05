import Foundation
import Testing
@testable import FlowSource

@Suite struct NettopParserTests {
    private let parser = NettopParser()

    @Test func parsesIPv4ConnectionRow() throws {
        let line = "00:34:29.225703,tcp4 198.18.0.1:65333<->17.57.146.137:5223,utun8,Established,5542,34103,"
        let rows = parser.parse(line)
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.transport == .tcp)
        #expect(row.interface == "utun8")
        #expect(row.state == "Established")
        #expect(row.bytesIn == 5542)
        #expect(row.bytesOut == 34103)
        #expect(row.local.address.text == "198.18.0.1")
        #expect(row.local.port == 65333)
        #expect(row.remote.address.text == "17.57.146.137")
        #expect(row.remote.port == 5223)
    }

    @Test func parsesIPv6DotPort() throws {
        let line = "00:00:00.000002,tcp6 fe80::1.51234<->2001:db8::1.443,en0,Established,10,20,"
        let row = try #require(parser.parse(line).first)
        #expect(row.transport == .tcp)
        #expect(row.local.address.text == "fe80::1")
        #expect(row.local.port == 51234)
        #expect(row.remote.address.text == "2001:db8::1")
        #expect(row.remote.port == 443)
    }

    @Test func parsesQUICAndMapsTransport() throws {
        let line = "00:00:00.000003,quic4 192.168.1.134:64243<->8.47.69.0:443,en0,,4182,3700,"
        let row = try #require(parser.parse(line).first)
        #expect(row.transport == .quic)
        #expect(row.bytesIn == 4182)
        #expect(row.bytesOut == 3700)
    }

    @Test func skipsProcessSummaryWildcardScopedAndHostnameRows() {
        let text = """
        time,,interface,state,bytes_in,bytes_out,
        00:00:00.000001,apsd.590,,,5542,34103,
        00:00:00.000004,udp4 *:*<->*:*,,,,,
        00:00:00.000005,udp4 *:5353<->*.*,,,,,
        00:00:00.000006,quic6 fe80::7ca2:20ff:fe4d:277%awdl0.52214<->fe80::13:faff:fe55:a839%awdl0.50386,awdl0,,1001065,136242,
        00:00:00.000007,tcp4 1.2.3.4:5<->one.one.one.one:443,en0,Established,1,1,
        """
        #expect(parser.parse(text).isEmpty)
    }

    @Test func missingByteCountersBecomeZero() throws {
        let line = "00:00:00.000012,tcp4 10.0.0.5:61000<->10.0.0.1:443,en0,Established,,"
        let row = try #require(parser.parse(line).first)
        #expect(row.bytesIn == 0)
        #expect(row.bytesOut == 0)
    }

    @Test func malformedEndpointTokenSkipped() {
        let line = "00:00:00.000009,tcp4 malformed-endpoint-token,en0,Established,1,1,"
        #expect(parser.parse(line).isEmpty)
    }

    @Test func readsRealFixture() throws {
        let url = try FixtureLocator.repoRoot()
            .appendingPathComponent("Fixtures/nettop/capture-1.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = parser.parse(text)
        #expect(rows.count > 10)   // 302-line capture, wildcards/process-rows filtered
        #expect(rows.contains { $0.transport == .tcp })
    }
}
