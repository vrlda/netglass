import Foundation
import FlowModel
import FlowSource

public enum ScopeVerdict: String, Codable, Sendable {
    case inScope, excluded, outOfScope, unknown
}

public struct OperationScope: Codable, Equatable, Sendable {
    public var allowedCIDRs: [IPRange]
    public var allowedDomains: [String]
    public var excludedIPs: [String]
    public var excludedDomains: [String]

    public init(allowedCIDRs: [IPRange] = [], allowedDomains: [String] = [],
                excludedIPs: [String] = [], excludedDomains: [String] = []) {
        self.allowedCIDRs = allowedCIDRs
        self.allowedDomains = allowedDomains
        self.excludedIPs = excludedIPs
        self.excludedDomains = excludedDomains
    }

    /// Parses plain-text lines: `10.20.0.0/16`, `*.lab.example`, and
    /// `excluded: <value>`. Invalid lines are ignored.
    public static func parse(lines: [String]) -> OperationScope {
        var allowedCIDRs: [IPRange] = []
        var allowedDomains: [String] = []
        var excludedIPs: [String] = []
        var excludedDomains: [String] = []
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let excluded = line.hasPrefix("excluded:")
            let value = excluded
                ? String(line.dropFirst("excluded:".count)).trimmingCharacters(in: .whitespaces)
                : line
            if let range = IPRange(text: value) {
                if excluded { excludedIPs.append(value) } else { allowedCIDRs.append(range) }
            } else if value.hasPrefix("*.") {
                let domain = String(value.dropFirst(2))
                if excluded { excludedDomains.append(domain) } else { allowedDomains.append(domain) }
            } else if value.contains(".") {
                if excluded { excludedDomains.append(value) } else { allowedDomains.append(value) }
            }
        }
        return OperationScope(allowedCIDRs: allowedCIDRs, allowedDomains: allowedDomains,
                              excludedIPs: excludedIPs, excludedDomains: excludedDomains)
    }

    /// Minimal YAML-subset parser for the scope file shape:
    /// `allowed:` / `excluded:` blocks with `- value` list items; `#` comments;
    /// quoted values stripped. Everything else is ignored. Delegates to the
    /// plain-line classifier, so classification stays consistent.
    public static func parse(yaml: String) -> OperationScope {
        enum Section { case none, allowed, excluded }
        var lines: [String] = []
        var section = Section.none
        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]) }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasSuffix(":") {
                let key = String(line.dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
                // Only recognized section keys switch the list; items under
                // unknown keys (typos) are ignored, never flipped to allowed.
                switch key {
                case "allowed": section = .allowed
                case "excluded": section = .excluded
                default: section = .none
                }
                continue
            }
            guard line.hasPrefix("-") else { continue }
            let value = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else { continue }
            switch section {
            case .allowed: lines.append(value)
            case .excluded: lines.append("excluded: \(value)")
            case .none: break
            }
        }
        return parse(lines: lines)
    }

    /// Normalized plain lines (round-trips through `parse(lines:)`), used to
    /// fill the scope editor after a YAML import.
    public func normalizedLines() -> [String] {
        var lines: [String] = []
        lines.append(contentsOf: allowedCIDRs.map(\.text))
        lines.append(contentsOf: allowedDomains.map { "*.\($0)" })
        lines.append(contentsOf: excludedIPs.map { "excluded: \($0)" })
        lines.append(contentsOf: excludedDomains.map { "excluded: \($0)" })
        return lines
    }

    public func verdict(ip: [UInt8], domain: String?) -> ScopeVerdict {
        if isLoopback(ip) { return .unknown }
        if excludedIPs.contains(where: { parseAndMatch($0, ip) })
            || excludedDomains.contains(where: { domain?.lowercased() == $0.lowercased() }) {
            return .excluded
        }
        if allowedCIDRs.contains(where: { $0.contains(ip) })
            || domainMatchesAllowed(domain) {
            return .inScope
        }
        if domain == nil && (allowedCIDRs.isEmpty || !(IPAddress(ip)?.isLocal ?? false)) {
            return .unknown
        }
        return .outOfScope
    }

    private func isLoopback(_ ip: [UInt8]) -> Bool {
        if ip.count == 4 { return ip[0] == 127 }
        if ip.count == 16 { return ip[0...14].allSatisfy { $0 == 0 } && ip[15] == 1 }
        return false
    }

    private func domainMatchesAllowed(_ domain: String?) -> Bool {
        // `*.lab.example` allows `x.lab.example` but not the bare apex
        guard let domain = domain?.lowercased() else { return false }
        return allowedDomains.contains { entry in
            let normalized = entry.hasPrefix("*.")
                ? String(entry.dropFirst(2)).lowercased()
                : entry.lowercased()
            return domain.hasSuffix("." + normalized)
        }
    }

    private func parseAndMatch(_ text: String, _ ip: [UInt8]) -> Bool {
        guard let range = IPRange(text: text) else { return false }
        return range.contains(ip)
    }
}

// MARK: - Operation events

public enum ListenerAction: String, Codable, Sendable {
    case opened, closed
}

public struct ListeningPort: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let process: String
    public let pid: Int32
    public let address: String
    public let port: UInt16
    public let proto: String
    public let exposure: String    // "loopback" | "allInterfaces" | "specific"
    public let action: ListenerAction

    public init(process: String, pid: Int32, address: String, port: UInt16,
                proto: String, exposure: String, action: ListenerAction) {
        self.id = "\(pid)-\(proto)-\(address):\(port)"
        self.process = process
        self.pid = pid
        self.address = address
        self.port = port
        self.proto = proto
        self.exposure = exposure
        self.action = action
    }
}

public enum OperationEvent: Codable, Equatable, Sendable {
    case connection(opened: Bool, date: Date, process: String,
                    executablePath: String, remote: NetworkEndpoint,
                    interface: String, transport: TransportProtocol, bytes: UInt64)
    case dns(date: Date, process: String, domain: String, ip: String)
    case listener(ListeningPort)
}

// MARK: - Leak warnings

public enum LeakRuleID: String, Codable, Sendable {
    case interfaceMismatch, ipv6Escape, preTunnelDNS, resolverMismatch,
         scopeViolation, listenerExposure, trafficAfterStop
}

public enum Severity: String, Codable, Sendable {
    case info, warning, critical
}

public struct LeakWarning: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let rule: LeakRuleID
    public let severity: Severity
    public let title: String
    public let details: [String]

    public init(rule: LeakRuleID, severity: Severity, title: String, details: [String]) {
        self.id = UUID()
        self.date = Date()
        self.rule = rule
        self.severity = severity
        self.title = title
        self.details = details
    }
}

// MARK: - Snapshots

public struct ResolverConfig: Codable, Equatable, Sendable {
    public let nameservers: [String]
    public init(nameservers: [String]) { self.nameservers = nameservers }
}

public struct OperationSnapshot: Codable, Equatable, Sendable {
    public let date: Date
    public let defaultRouteInterface: String
    public let interfaces: [NetInterface]
    public let resolvers: [ResolverConfig]
    public let listeners: [LsofListener]

    public init(date: Date, defaultRouteInterface: String = "",
                interfaces: [NetInterface] = [],
                resolvers: [ResolverConfig] = [],
                listeners: [LsofListener] = []) {
        self.date = date
        self.defaultRouteInterface = defaultRouteInterface
        self.interfaces = interfaces
        self.resolvers = resolvers
        self.listeners = listeners
    }
}

// MARK: - Session

public struct OperationSession: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let startedAt: Date
    public var endedAt: Date?
    public let expectedTunnel: String
    public let scope: OperationScope
    public let snapshotIn: OperationSnapshot
    public var snapshotOut: OperationSnapshot?
    public var cleanupReport: CleanupReport?
    public var events: [OperationEvent]
    public var warnings: [LeakWarning]
    public var periodic: [PeriodicPattern]

    public init(id: UUID = UUID(), name: String, startedAt: Date = Date(),
                expectedTunnel: String, scope: OperationScope,
                snapshotIn: OperationSnapshot) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = nil
        self.expectedTunnel = expectedTunnel
        self.scope = scope
        self.snapshotIn = snapshotIn
        self.snapshotOut = nil
        self.cleanupReport = nil
        self.events = []
        self.warnings = []
        self.periodic = []
    }
}

// MARK: - Cleanup report

public struct CleanupReport: Codable, Equatable, Sendable {
    public let activeProcessPaths: [String]
    public let newListenersAtEnd: [String]
    public let activeConnectionCount: Int
    public let resolverChanged: Bool
    public let defaultRouteChanged: Bool
    public let endedAt: Date

    public init(snapshotIn: OperationSnapshot, snapshotOut: OperationSnapshot,
                liveFlows: [LiveFlow], endedAt: Date) {
        self.activeProcessPaths = Array(Set(liveFlows.map(\.executablePath))).sorted()
        self.newListenersAtEnd = snapshotOut.listeners
            .filter { listener in
                guard listener.pid != 0 else { return false }
                return !snapshotIn.listeners.contains {
                    $0.pid == listener.pid
                        && $0.address == listener.address
                        && $0.port == listener.port
                }
            }
            .map { "\($0.processName):\($0.address):\($0.port)" }
            .sorted()
        self.activeConnectionCount = liveFlows.filter(\.isActive).count
        self.resolverChanged = snapshotIn.resolvers != snapshotOut.resolvers
        self.defaultRouteChanged = snapshotIn.defaultRouteInterface != snapshotOut.defaultRouteInterface
            && !snapshotOut.defaultRouteInterface.isEmpty
        self.endedAt = endedAt
    }
}

// MARK: - Export bundle

public struct OperationBundle: Codable, Equatable, Sendable {
    public let app: String
    public let version: String
    public let operation: OperationSession
    public let snapshotIn: OperationSnapshot
    public let snapshotOut: OperationSnapshot?
    public let warnings: [LeakWarning]
    public let events: [OperationEvent]
    public let cleanupReport: CleanupReport?
    public let periodic: [PeriodicPattern]

    public init(operation: OperationSession, warnings: [LeakWarning],
                events: [OperationEvent], snapshotIn: OperationSnapshot,
                snapshotOut: OperationSnapshot?, cleanupReport: CleanupReport?) {
        self.app = "Netglass"
        self.version = "1.2.1"
        self.operation = operation
        self.warnings = warnings
        self.events = events
        self.snapshotIn = snapshotIn
        self.snapshotOut = snapshotOut
        self.cleanupReport = cleanupReport
        self.periodic = operation.periodic
    }
}
