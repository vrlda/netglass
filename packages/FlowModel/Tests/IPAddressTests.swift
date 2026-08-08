import Foundation
import Testing
@testable import FlowModel

@Suite struct IPAddressTests {
    @Test func parsesIPv4() throws {
        let ip = try #require(IPAddress(text: "192.168.1.1"))
        #expect(ip.isIPv4)
        #expect(ip.isIPv6 == false)
        #expect(ip.bytes.count == 4)
        #expect(ip.text == "192.168.1.1")
    }

    @Test func parsesIPv6() throws {
        let ip = try #require(IPAddress(text: "2001:db8::1"))
        #expect(ip.isIPv6)
        #expect(ip.bytes.count == 16)
        #expect(ip.text == "2001:db8::1")
    }

    @Test func parsesLoopbackV6() throws {
        let ip = try #require(IPAddress(text: "::1"))
        #expect(ip.text == "::1")
    }

    @Test func rejectsInvalidText() {
        #expect(IPAddress(text: "999.1.1.1") == nil)
        #expect(IPAddress(text: "192.168.1") == nil)
        #expect(IPAddress(text: "192.168.001.001") == nil)
        #expect(IPAddress(text: "hello") == nil)
        #expect(IPAddress(text: "") == nil)
        #expect(IPAddress(text: "fe80::1%en0") == nil)
        #expect(IPAddress(text: "fe80::1%0") == nil)
    }

    @Test func parsesBareLinkLocal() throws {
        let ip = try #require(IPAddress(text: "fe80::1"))
        #expect(ip.isIPv6)
    }

    @Test func rejectsWrongByteCount() {
        #expect(IPAddress([1, 2, 3]) == nil)
        #expect(IPAddress([]) == nil)
        #expect(IPAddress([UInt8](repeating: 0, count: 5)) == nil)
    }

    @Test func roundTripsCanonicalForms() throws {
        for text in ["10.0.0.1", "255.255.255.255", "0.0.0.0",
                     "fe80::1", "2001:db8:85a3::8a2e:370:7334",
                     "::ffff:192.168.1.1"] {
            let ip = try #require(IPAddress(text: text))
            #expect(ip.text == text, "round-trip failed for \(text)")
        }
    }

    @Test func byteInitializerRoundTrip() throws {
        let ip = try #require(IPAddress([192, 168, 0, 1]))
        #expect(ip.text == "192.168.0.1")
    }

    @Test func bytesMatchParsedText() {
        #expect(IPAddress(text: "192.168.1.42")!.bytes == [192, 168, 1, 42])
        #expect(IPAddress(text: "2001:db8::1")!.bytes.count == 16)
    }
}
