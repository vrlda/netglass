import Foundation
import Testing
@testable import FlowModel
@testable import NetglassMac

@Suite struct OperationScopeTests {
    @Test func cidrMatching() {
        let range = try! #require(IPRange(text: "10.20.0.0/16"))
        #expect(range.contains([10, 20, 30, 1]))
        #expect(!range.contains([10, 21, 0, 1]))
        #expect(!range.contains([192, 168, 1, 1]))
        let v6 = try! #require(IPRange(text: "2001:db8::/32"))
        #expect(v6.contains(IPAddress(text: "2001:db8::1")!.bytes))
        #expect(!v6.contains(IPAddress(text: "2001:db9::1")!.bytes))
    }

    @Test func verdictPrecedence() {
        let scope = OperationScope(
            allowedCIDRs: [try! #require(IPRange(text: "10.20.0.0/16"))],
            allowedDomains: ["*.lab.example"],
            excludedIPs: ["10.20.10.50"],
            excludedDomains: ["admin.lab.example"])
        #expect(scope.verdict(ip: IPAddress(text: "10.20.30.1")!.bytes, domain: nil) == .inScope)
        #expect(scope.verdict(ip: IPAddress(text: "10.20.10.50")!.bytes, domain: nil) == .excluded)
        #expect(scope.verdict(ip: IPAddress(text: "10.40.0.1")!.bytes, domain: nil) == .outOfScope)
        #expect(scope.verdict(ip: IPAddress(text: "1.2.3.4")!.bytes, domain: "x.lab.example") == .inScope)
        #expect(scope.verdict(ip: IPAddress(text: "1.2.3.4")!.bytes, domain: "admin.lab.example") == .excluded)
        #expect(scope.verdict(ip: IPAddress(text: "1.2.3.4")!.bytes, domain: nil) == .unknown)
        #expect(scope.verdict(ip: IPAddress(text: "1.2.3.4")!.bytes, domain: "lab.example") == .outOfScope)
    }

    @Test func scopeParsesLines() {
        let scope = OperationScope.parse(lines: ["10.20.0.0/16", "*.lab.example", "",
                                                 "excluded: 10.20.10.50", "excluded: admin.lab.example", "garbage"])
        #expect(scope.allowedCIDRs.count == 1)
        #expect(scope.allowedDomains == ["lab.example"])
        #expect(scope.excludedIPs == ["10.20.10.50"])
        #expect(scope.excludedDomains == ["admin.lab.example"])
    }

    @Test func scopeParsesYaml() {
        let yaml = """
        # lab scope
        allowed:
          - 10.20.0.0/16
          - "*.lab.example"
        excluded:
          - 10.20.10.50
          - admin.lab.example
        ignored: true
        """
        let scope = OperationScope.parse(yaml: yaml)
        #expect(scope.allowedCIDRs.count == 1)
        #expect(scope.allowedDomains == ["lab.example"])
        #expect(scope.excludedIPs == ["10.20.10.50"])
        #expect(scope.excludedDomains == ["admin.lab.example"])
    }

    @Test func scopeRendersNormalizedLines() {
        let scope = OperationScope(
            allowedCIDRs: [IPRange(text: "10.20.0.0/16")!],
            allowedDomains: ["lab.example"],
            excludedIPs: ["10.20.10.50"],
            excludedDomains: ["admin.lab.example"])
        let lines = scope.normalizedLines()
        #expect(lines.contains("10.20.0.0/16"))
        #expect(lines.contains("*.lab.example"))
        #expect(lines.contains("excluded: 10.20.10.50"))
        #expect(lines.contains("excluded: admin.lab.example"))
    }
}
