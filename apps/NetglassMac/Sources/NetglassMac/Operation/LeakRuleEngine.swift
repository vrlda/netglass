import Foundation
import FlowModel

/// Pure leak rules: turn operation events into warnings using session context.
/// No I/O, no clock dependency beyond injected `now`/event dates.
public struct LeakRuleEngine {
    public let preTunnelGrace: TimeInterval

    public init(preTunnelGrace: TimeInterval = 30) {
        self.preTunnelGrace = preTunnelGrace
    }

    public func evaluate(batch: [OperationEvent], session: OperationSession,
                         currentResolvers: [ResolverConfig] = [], now: Date) -> [LeakWarning] {
        var warnings: [LeakWarning] = []
        let tunnelExpected = !session.expectedTunnel.isEmpty
        for event in batch {
            switch event {
            case .connection(let opened, let date, let process, _,
                             let remote, let interface, _, _):
                if session.endedAt != nil {
                    warnings.append(LeakWarning(
                        rule: .trafficAfterStop, severity: .critical,
                        title: "Traffic continuing after operation stopped",
                        details: ["Process: \(process)", "Destination: \(remote.address.text):\(remote.port)"]))
                }
                if tunnelExpected && opened && interface != session.expectedTunnel {
                    warnings.append(LeakWarning(
                        rule: .interfaceMismatch, severity: .critical,
                        title: "Traffic bypassing tunnel",
                        details: ["Process: \(process)", "Destination: \(remote.address.text)",
                                  "Expected route: \(session.expectedTunnel)",
                                  "Observed interface: \(interface.isEmpty ? "unknown" : interface)"]))
                }
                if remote.address.text.contains(":")
                    && tunnelExpected
                    && session.snapshotIn.interfaces.first(where: { $0.name == session.expectedTunnel })?.ipv6 == nil {
                    warnings.append(LeakWarning(
                        rule: .ipv6Escape, severity: .warning,
                        title: "IPv6 traffic outside the IPv4 tunnel",
                        details: ["Process: \(process)", "Destination: \(remote.address.text)",
                                  "Tunnel: \(session.expectedTunnel) has no IPv6"]))
                }
                let verdict = session.scope.verdict(ip: remote.address.bytes, domain: nil)
                if verdict == .outOfScope {
                    warnings.append(LeakWarning(
                        rule: .scopeViolation, severity: .critical,
                        title: "Out-of-scope destination contacted",
                        details: ["Process: \(process)", "Destination: \(remote.address.text):\(remote.port)"]))
                } else if verdict == .excluded {
                    warnings.append(LeakWarning(
                        rule: .scopeViolation, severity: .warning,
                        title: "Excluded destination contacted",
                        details: ["Process: \(process)", "Destination: \(remote.address.text):\(remote.port)"]))
                }
            case .dns(let date, let process, let domain, _):
                if tunnelExpected && date.timeIntervalSince(session.startedAt) < preTunnelGrace {
                    warnings.append(LeakWarning(
                        rule: .preTunnelDNS, severity: .warning,
                        title: "DNS query before tunnel readiness",
                        details: ["Process: \(process)", "Query: \(domain)",
                                  "Started: \(session.startedAt)", "Queried: \(date)"]))
                }
            case .listener(let listener):
                if listener.action == .opened && listener.exposure == "allInterfaces" {
                    warnings.append(LeakWarning(
                        rule: .listenerExposure, severity: .warning,
                        title: "Listener exposed to all interfaces",
                        details: ["Process: \(listener.process)",
                                  "Listener: \(listener.address):\(listener.port)"]))
                }
            }
        }
        if !currentResolvers.isEmpty, Self.resolverFingerprint(currentResolvers) != Self.resolverFingerprint(session.snapshotIn.resolvers) {
            warnings.append(LeakWarning(
                rule: .resolverMismatch, severity: .info,
                title: "System resolver changed during operation",
                details: currentResolvers.flatMap { $0.nameservers }
                    .map { "Resolver: \($0)" }))
        }
        return warnings
    }

    /// Order-insensitive set of nameservers: resolver churn/reorder on macOS
    /// (e.g. Tailscale appearing in multiple configs) must not false-positive.
    static func resolverFingerprint(_ resolvers: [ResolverConfig]) -> Set<String> {
        Set(resolvers.flatMap { $0.nameservers })
    }
}
