import Foundation
import FlowModel

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

    public func verdict(ip: [UInt8], domain: String?) -> ScopeVerdict {
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
