import Foundation
import Testing
@testable import NetglassMac

@Suite struct GeoIPTests {
    @Test func knownProviders() {
        let google = GeoIP.lookup("8.8.8.8")
        #expect(google?.asn == "AS15169")
        #expect(google?.country == "US")

        let telegram = GeoIP.lookup("149.154.167.51")
        #expect(telegram?.asn == "AS62041")
        #expect(telegram?.organization.contains("Telegram") == true)

        let cloudflare = GeoIP.lookup("1.1.1.1")
        #expect(cloudflare?.asn == "AS13335")

        let apple = GeoIP.lookup("17.253.144.10")
        #expect(apple?.asn == "AS714")
        #expect(apple?.organization.contains("Apple") == true)
    }

    @Test func unknownAndInvalidReturnNil() {
        #expect(GeoIP.lookup("203.0.113.42") == nil)     // TEST-NET
        #expect(GeoIP.lookup("10.0.0.1") == nil)         // private
        #expect(GeoIP.lookup("2001:db8::1") == nil)      // IPv6 not supported
        #expect(GeoIP.lookup("not-an-ip") == nil)
        #expect(GeoIP.lookup("999.1.1.1") == nil)
    }

    @Test func rangeBoundaries() {
        // 17.0.0.0/8: first and last addresses match, neighbors don't
        #expect(GeoIP.lookup("17.0.0.0")?.asn == "AS714")
        #expect(GeoIP.lookup("17.255.255.255")?.asn == "AS714")
        #expect(GeoIP.lookup("16.255.255.255") != nil)   // Amazon 16/8
        #expect(GeoIP.lookup("18.0.0.0")?.organization.contains("Amazon") == true)
        #expect(GeoIP.lookup("19.0.0.0") == nil)         // outside all tables
    }

    @Test func expandedCoverage() {
        #expect(GeoIP.lookup("87.240.190.72")?.organization.contains("VK") == true)
        #expect(GeoIP.lookup("172.104.10.1")?.asn == "AS63949")    // Linode
        #expect(GeoIP.lookup("138.201.0.5")?.asn == "AS24940")     // Hetzner
        #expect(GeoIP.lookup("100.74.221.21")?.organization.contains("Tailscale") == true)
    }
}

@Suite struct CaptureFilterTests {
    @Test func filterExpressions() {
        #expect(PacketCaptureViewModel.filterExpression(scope: .allTraffic, value: nil) == "")
        #expect(PacketCaptureViewModel.filterExpression(scope: .ipAddress, value: "8.8.8.8")
            == "host 8.8.8.8")
        #expect(PacketCaptureViewModel.filterExpression(scope: .port, value: "443")
            == "port 443")
        #expect(PacketCaptureViewModel.filterExpression(scope: .connection, value: "1.2.3.4:443")
            == "host 1.2.3.4 and port 443")
        #expect(PacketCaptureViewModel.filterExpression(scope: .protocolName, value: "tcp") == "tcp")
        #expect(PacketCaptureViewModel.filterExpression(scope: .protocolName, value: "UDP") == "udp")
        #expect(PacketCaptureViewModel.filterExpression(scope: .application, value: "Telegram") == "")
    }
}
