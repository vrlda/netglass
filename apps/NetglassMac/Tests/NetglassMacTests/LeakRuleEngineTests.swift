import Foundation
import Testing
@testable import FlowModel
@testable import NetglassMac

@Suite struct LeakRuleEngineTests {
    private func session(expectedTunnel: String = "utun4") -> OperationSession {
        OperationSession(name: "T", expectedTunnel: expectedTunnel,
                         scope: OperationScope(allowedCIDRs: [IPRange(text: "10.20.0.0/16")!]),
                         snapshotIn: OperationSnapshot(date: Date()))
    }

    private func conn(interface: String, remote: String, opened: Bool = true) -> OperationEvent {
        .connection(opened: opened, date: Date(), process: "nmap", executablePath: "/bin/nmap",
                    remote: NetworkEndpoint(address: IPAddress(text: remote)!, port: 443),
                    interface: interface, transport: .tcp, bytes: 10)
    }

    @Test func interfaceMismatchWarns() {
        let engine = LeakRuleEngine()
        let warnings = engine.evaluate(batch: [conn(interface: "en0", remote: "10.20.30.1")],
                                       session: session(), now: Date())
        #expect(warnings.contains { $0.rule == .interfaceMismatch && $0.severity == .critical })
        let ok = engine.evaluate(batch: [conn(interface: "utun4", remote: "10.20.30.1")],
                                 session: session(), now: Date())
        #expect(!ok.contains { $0.rule == .interfaceMismatch })
    }

    @Test func ipv6EscapeWarns() {
        let engine = LeakRuleEngine()
        let warnings = engine.evaluate(batch: [conn(interface: "utun4", remote: "2001:db8::1")],
                                       session: session(), now: Date())
        #expect(warnings.contains { $0.rule == .ipv6Escape })
    }

    @Test func scopeViolationWarns() {
        let engine = LeakRuleEngine()
        let out = engine.evaluate(batch: [conn(interface: "utun4", remote: "10.40.0.1")],
                                  session: session(), now: Date())
        #expect(out.contains { $0.rule == .scopeViolation && $0.severity == .critical })
        let inScope = engine.evaluate(batch: [conn(interface: "utun4", remote: "10.20.30.1")],
                                      session: session(), now: Date())
        #expect(!inScope.contains { $0.rule == .scopeViolation })
    }

    @Test func listenerExposureWarns() {
        let engine = LeakRuleEngine()
        let listener = OperationEvent.listener(ListeningPort(
            process: "python3", pid: 5, address: "0.0.0.0", port: 8000,
            proto: "TCP", exposure: "allInterfaces", action: .opened))
        let warnings = engine.evaluate(batch: [listener], session: session(), now: Date())
        #expect(warnings.contains { $0.rule == .listenerExposure })
    }

    @Test func trafficAfterStopWarns() {
        let engine = LeakRuleEngine()
        var session = session()
        session.endedAt = Date().addingTimeInterval(-60)
        let warnings = engine.evaluate(batch: [conn(interface: "utun4", remote: "10.20.30.1", opened: true)],
                                       session: session, now: Date())
        #expect(warnings.contains { $0.rule == .trafficAfterStop })
    }

    @Test func preTunnelDNSWarns() {
        let engine = LeakRuleEngine()
        let session = session()
        // DNS within the grace window of session start warns
        let early = OperationEvent.dns(date: session.startedAt.addingTimeInterval(5),
                                       process: "curl", domain: "target.example", ip: "1.2.3.4")
        let warnings = engine.evaluate(batch: [early], session: session, now: Date())
        #expect(warnings.contains { $0.rule == .preTunnelDNS })
        // DNS after the grace period does not warn
        let late = OperationEvent.dns(date: session.startedAt.addingTimeInterval(120),
                                      process: "curl", domain: "target.example", ip: "1.2.3.4")
        let noWarn = engine.evaluate(batch: [late], session: session, now: Date())
        #expect(!noWarn.contains { $0.rule == .preTunnelDNS })
        // DNS dated before the session started does not warn
        let beforeStart = OperationEvent.dns(date: session.startedAt.addingTimeInterval(-1),
                                             process: "curl", domain: "target.example", ip: "1.2.3.4")
        let preStart = engine.evaluate(batch: [beforeStart], session: session, now: Date())
        #expect(!preStart.contains { $0.rule == .preTunnelDNS })
    }

    @Test func resolverMismatchWarns() {
        let engine = LeakRuleEngine()
        let session = session()
        let current = [ResolverConfig(nameservers: ["10.20.0.1"])]
        let warnings = engine.evaluate(batch: [], session: session,
                                       currentResolvers: current, now: Date())
        #expect(warnings.contains { $0.rule == .resolverMismatch && $0.severity == .info })
        let same = engine.evaluate(batch: [], session: session,
                                   currentResolvers: session.snapshotIn.resolvers, now: Date())
        #expect(!same.contains { $0.rule == .resolverMismatch })
    }

    @Test func resolverMismatchDoesNotWarnWhenMatchingNonEmptyResolvers() {
        let engine = LeakRuleEngine()
        let resolvers = [ResolverConfig(nameservers: ["10.20.0.1"])]
        let session = OperationSession(
            name: "T", expectedTunnel: "utun4", scope: OperationScope(),
            snapshotIn: OperationSnapshot(date: Date(), resolvers: resolvers))
        let warnings = engine.evaluate(batch: [], session: session,
                                       currentResolvers: resolvers, now: Date())
        #expect(!warnings.contains { $0.rule == .resolverMismatch })
    }

    @Test func ipv6EscapeDoesNotWarnWhenTunnelHasIPv6() {
        let engine = LeakRuleEngine()
        let session = OperationSession(
            name: "T", expectedTunnel: "utun4",
            scope: OperationScope(allowedCIDRs: [IPRange(text: "10.20.0.0/16")!]),
            snapshotIn: OperationSnapshot(
                date: Date(),
                interfaces: [NetInterface(name: "utun4", ipv4: "10.0.0.1", ipv6: "fd00::1")]))
        let warnings = engine.evaluate(batch: [conn(interface: "utun4", remote: "2001:db8::1")],
                                       session: session, now: Date())
        #expect(!warnings.contains { $0.rule == .ipv6Escape })
    }

    @Test func localhostNotScopeViolated() {
        let engine = LeakRuleEngine()
        let session = session()
        let warnings = engine.evaluate(batch: [conn(interface: "utun4", remote: "127.0.0.1")],
                                       session: session, now: Date())
        #expect(!warnings.contains { $0.rule == .scopeViolation })
        #expect(session.scope.verdict(ip: [127, 0, 0, 1], domain: nil) == .unknown)
    }

    @Test func preStopCloseEventDoesNotWarnTrafficAfterStop() {
        let engine = LeakRuleEngine()
        var session = session()
        let endedAt = Date()
        session.endedAt = endedAt
        let closeBefore = OperationEvent.connection(
            opened: false, date: endedAt.addingTimeInterval(-1), process: "curl",
            executablePath: "/bin/curl",
            remote: NetworkEndpoint(address: IPAddress(text: "10.20.30.1")!, port: 443),
            interface: "utun4", transport: .tcp, bytes: 10)
        let noWarn = engine.evaluate(batch: [closeBefore], session: session, now: Date())
        #expect(!noWarn.contains { $0.rule == .trafficAfterStop })
        let openAfter = OperationEvent.connection(
            opened: true, date: endedAt.addingTimeInterval(1), process: "curl",
            executablePath: "/bin/curl",
            remote: NetworkEndpoint(address: IPAddress(text: "10.20.30.1")!, port: 443),
            interface: "utun4", transport: .tcp, bytes: 10)
        let warns = engine.evaluate(batch: [openAfter], session: session, now: Date())
        #expect(warns.contains { $0.rule == .trafficAfterStop })
    }
}
