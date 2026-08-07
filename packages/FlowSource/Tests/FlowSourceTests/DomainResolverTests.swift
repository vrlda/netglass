import FlowModel
@testable import FlowSource
import Foundation
import Testing

/// Deterministic fake: PTR + forward mappings, no network.
struct FakeResolver: ReverseDNSResolving {
    var ptr: [String: String]
    var forward: [String: [String]]
    var hostnameCalls: LockedCounter

    func hostname(for ip: String) -> String? { hostnameCalls.increment(); return ptr[ip] }
    func ipAddresses(for hostname: String) -> [String] { forward[hostname] ?? [] }
}

/// Small lock-free-ish counter for asserting lookup counts. Actor-safe.
final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    func count() -> Int { lock.lock(); defer { lock.unlock() }; return value }
}

@Suite struct DomainResolverTests {
    @Test func forwardConfirmedBeatsBarePTR() {
        // 8.8.8.8 → dns.google → 8.8.8.8 (round trip) → FCrDNS
        let fcr = DomainResolver.resolve(
            ip: "8.8.8.8",
            lookup: FakeResolver(ptr: ["8.8.8.8": "dns.google"],
                                 forward: ["dns.google": ["8.8.8.8", "8.8.4.4"]],
                                 hostnameCalls: LockedCounter()))
        #expect(fcr?.source == .forwardConfirmedPTR)
        #expect(fcr?.confidence == DomainCandidate.forwardConfirmedConfidence)

        // 149.154.167.51 → some.telegram.example, but the name does NOT
        // resolve back to this IP → bare PTR only
        let bare = DomainResolver.resolve(
            ip: "149.154.167.51",
            lookup: FakeResolver(ptr: ["149.154.167.51": "some.telegram.example"],
                                 forward: ["some.telegram.example": ["10.0.0.1"]],
                                 hostnameCalls: LockedCounter()))
        #expect(bare?.source == .ptrOnly)
        #expect(bare?.confidence == DomainCandidate.ptrOnlyConfidence)

        // monotonicity: FCrDNS > PTR-only
        #expect(fcr!.confidence > bare!.confidence)
    }

    @Test func noPtrYieldsNoCandidate() {
        let none = DomainResolver.resolve(
            ip: "149.154.167.51",
            lookup: FakeResolver(ptr: [:], forward: [:], hostnameCalls: LockedCounter()))
        #expect(none == nil)
    }

    @Test func bareHostnamesAreRejected() {
        let bare = DomainResolver.resolve(
            ip: "1.2.3.4",
            lookup: FakeResolver(ptr: ["1.2.3.4": "router"], forward: [:],
                                 hostnameCalls: LockedCounter()))
        #expect(bare == nil)
    }

    @Test func cacheHitsMissesTTL() async {
        let clock = MockClock()
        let resolver = DomainResolver(
            lookup: FakeResolver(ptr: ["8.8.8.8": "dns.google"],
                                 forward: ["dns.google": ["8.8.8.8"]],
                                 hostnameCalls: LockedCounter()),
            hitTTL: 600, missTTL: 60, now: { clock.now })

        // first lookups hit the network
        let first = await resolver.candidate(for: "8.8.8.8")
        #expect(first?.domain == "dns.google")

        // cached: no extra network work
        clock.advance(300)
        let second = await resolver.candidate(for: "8.8.8.8")
        #expect(second == first)

        // past the TTL: re-resolves
        clock.advance(301)
        let third = await resolver.candidate(for: "8.8.8.8")
        #expect(third == first)
    }

    @Test func missesRetrySooner() async {
        let clock = MockClock()
        let resolver = DomainResolver(
            lookup: FakeResolver(ptr: [:], forward: [:], hostnameCalls: LockedCounter()),
            hitTTL: 600, missTTL: 60, now: { clock.now })

        #expect(await resolver.candidate(for: "10.9.9.9") == nil)
        // within missTTL: cached miss, no new network work
        clock.advance(30)
        #expect(await resolver.candidate(for: "10.9.9.9") == nil)
        // past missTTL: retried
        clock.advance(31)
        #expect(await resolver.candidate(for: "10.9.9.9") == nil)
    }

    @Test func concurrentLookupsDedupe() async {
        let counter = LockedCounter()
        let resolver = DomainResolver(
            lookup: FakeResolver(ptr: ["8.8.8.8": "dns.google"],
                                 forward: ["dns.google": ["8.8.8.8"]],
                                 hostnameCalls: counter),
            hitTTL: 600, missTTL: 60)

        // fire many lookups at once for the same IP
        let results = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<20 {
                group.addTask { await resolver.candidate(for: "8.8.8.8")?.domain }
            }
            var domains: [String?] = []
            for await d in group { domains.append(d) }
            return domains
        }
        #expect(results.allSatisfy { $0 == "dns.google" })
        #expect(counter.count() == 1)   // exactly one network pass
    }
}

final class MockClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_752_800_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
}
