import Foundation
import Testing
@testable import FlowModel

@Suite struct IPAddressLocalTests {
    private func local(_ ip: String) -> Bool {
        IPAddress(text: ip)?.isLocal ?? false
    }

    @Test func localIPv4() {
        #expect(local("127.0.0.1"))
        #expect(local("127.255.255.255"))
        #expect(local("10.0.0.1"))
        #expect(local("172.16.0.1"))
        #expect(local("172.31.255.255"))
        #expect(local("192.168.1.5"))
        #expect(local("169.254.1.1"))
        #expect(local("0.0.0.0"))
        #expect(local("224.0.0.1"))
        #expect(local("239.255.255.250"))
        #expect(local("255.255.255.255"))
    }

    @Test func publicIPv4() {
        #expect(!local("8.8.8.8"))
        #expect(!local("149.154.167.51"))
        #expect(!local("17.253.144.10"))
        #expect(!local("172.32.0.1"))
        #expect(!local("172.15.255.255"))
        #expect(!local("169.253.0.1"))
    }

    @Test func localIPv6() {
        #expect(local("::1"))
        #expect(local("::"))
        #expect(local("fe80::1"))
        #expect(local("fd7a:115c:a1e0::1"))      // ULA (Tailscale)
        #expect(local("ff02::1"))                 // multicast
    }

    @Test func publicIPv6() {
        #expect(!local("2001:4860:4860::8888"))
        #expect(!local("2606:4700:4700::1111"))
        #expect(!local("2a00:1450::1"))
    }
}
