import FlowModel
import Foundation

/// Resolves remote IPs to domain candidates via reverse DNS with forward
/// confirmation (FCrDNS). Results are cached per IP with a TTL; misses are
/// retried sooner than hits so a transient failure doesn't poison the cache.
/// Actor-isolated: the live loop awaits lookups without blocking the main
/// thread — the blocking network calls run detached.
public actor DomainResolver {
    public struct Entry {
        public let candidate: DomainCandidate?
        public let resolvedAt: Date
    }

    private let lookup: ReverseDNSResolving
    private let hitTTL: TimeInterval
    private let missTTL: TimeInterval
    private let now: () -> Date
    private var cache: [String: Entry] = [:]
    private var inFlight: [String: Task<DomainCandidate?, Never>] = [:]

    public init(lookup: ReverseDNSResolving = SystemResolver(),
                hitTTL: TimeInterval = 30 * 60,
                missTTL: TimeInterval = 60,
                now: @escaping () -> Date = Date.init) {
        self.lookup = lookup
        self.hitTTL = hitTTL
        self.missTTL = missTTL
        self.now = now
    }

    /// Strongest candidate for an IP, resolving on first sight and caching.
    public func candidate(for ip: String) async -> DomainCandidate? {
        if let entry = cache[ip] {
            let ttl = entry.candidate == nil ? missTTL : hitTTL
            if now().timeIntervalSince(entry.resolvedAt) < ttl {
                return entry.candidate
            }
        }
        if let pending = inFlight[ip] {
            return await pending.value
        }
        let task = Task.detached(priority: .utility) { [lookup, ip] in
            Self.resolve(ip: ip, lookup: lookup)
        }
        inFlight[ip] = task
        let candidate = await task.value
        inFlight[ip] = nil
        cache[ip] = Entry(candidate: candidate, resolvedAt: now())
        return candidate
    }

    public func clearCache() {
        cache.removeAll()
    }

    /// Pure scoring: FCrDNS beats bare PTR; bare PTR beats nothing. Testable
    /// without the actor.
    static func resolve(ip: String, lookup: ReverseDNSResolving) -> DomainCandidate? {
        guard let name = lookup.hostname(for: ip),
              name.contains(".") else { return nil }   // bare names are junk
        let forward = lookup.ipAddresses(for: name)
        if forward.contains(ip) {
            return DomainCandidate(domain: name,
                                   confidence: DomainCandidate.forwardConfirmedConfidence,
                                   source: .forwardConfirmedPTR)
        }
        return DomainCandidate(domain: name,
                               confidence: DomainCandidate.ptrOnlyConfidence,
                               source: .ptrOnly)
    }
}
