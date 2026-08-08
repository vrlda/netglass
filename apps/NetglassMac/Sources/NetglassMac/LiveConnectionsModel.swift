import Foundation
import FlowModel
import FlowSource
import Persistence

/// Live view over the current observation: holds sampled flows on the main
/// actor, applies FlowEvents tick by tick, and exposes a search filter.
@MainActor
public final class LiveConnectionsModel: ObservableObject {
    @Published public private(set) var flows: [LiveFlow] = []
    @Published public private(set) var throughput = Throughput.zero
    @Published public private(set) var throughputHistory: [ThroughputSample] = []
    @Published public private(set) var resolutionEvents: [ResolutionEvent] = []
    @Published public var searchText: String = ""

    /// Optional observer for operation sessions: receives one batch of
    /// OperationEvents per tick (connections + DNS resolutions).
    public var operationSink: (([OperationEvent]) -> Void)?

    /// Rolling window of per-second throughput samples for the traffic chart.
    /// History is decimated to 1 Hz (see updateThroughput), so 1200 samples =
    /// the 20-minute live window (60 buckets x 5 s = 5 minutes shown).
    private let historyCapacity: Int
    /// Ticks left until the next 1 Hz history sample. First tick records
    /// immediately, then once per second of ticks (4 at 0.25 s, 2 at 0.5 s).
    private var ticksUntilHistorySample = 1
    /// Closed flows older than this drop out of the live table (history keeps
    /// them). Bound the in-memory list for long-running sessions.
    private let evictionTTL: TimeInterval

    /// Baseline for menu-bar throughput: cumulative bytes summed across all
    /// live flows at the previous successful tick. Deltas over real elapsed
    /// time, so a missed tick doesn't inflate the rate.
    private var lastTotals: (sent: UInt64, received: UInt64)?
    private var lastTickDate: Date?
    /// When the totals last moved: nettop refreshes counters at ~1 Hz while
    /// ticks run at 0.25 s, so three of four ticks see frozen counters and
    /// must keep the last rate instead of reporting zero.
    private var lastCounterChangeDate: Date?
    private let idleTimeout: TimeInterval = 2.0
    /// Bytes of flows OPENED this tick: nettop counters are cumulative from
    /// connection start, so an opening flow's bytes are baseline, not traffic.
    private var openedBaseline: (sent: UInt64, received: UInt64) = (0, 0)
    /// Bytes of flows REMOVED this tick (closed predecessors replaced by a
    /// reopen): drop them from the previous snapshot before computing deltas.
    private var removedBaseline: (sent: UInt64, received: UInt64) = (0, 0)

    /// Sampling cadence — runtime adjustable (Settings → Update frequency).
    public var interval: TimeInterval

    /// Optional history sink: when set, every tick's events are also persisted
    /// so the live session shows up in the History window. nil in contexts
    /// with no database (CLI-free tests).
    private let database: FlowDatabase?
    /// Resolves remote IPs to domain candidates (DNS evidence). Cache-backed;
    /// network work never runs on the main actor.
    private let domainResolver: DomainResolver

    public var visibleFlows: [LiveFlow] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return flows }
        return flows.filter { flow in
            flow.processName.lowercased().contains(query)
                || flow.executablePath.lowercased().contains(query)
                || flow.local.address.text.contains(query)
                || flow.remote.address.text.contains(query)
                || String(flow.remote.port).contains(query)
        }
    }

    /// Internal for tests: the two-tick counter test swaps the sampler's
    /// clients between ticks (a whole-sampler swap would reset the tracker and
    /// re-open every flow with a fresh flowID).
    var sampler: Sampler
    private var tickTask: Task<Void, Never>?

    public init(sampler: Sampler, database: FlowDatabase? = nil, interval: TimeInterval = 0.25,
                historyCapacity: Int = 1200, domainResolver: DomainResolver = DomainResolver(),
                evictionTTL: TimeInterval = 600) {
        self.sampler = sampler
        self.database = database
        self.interval = interval
        self.historyCapacity = historyCapacity
        self.domainResolver = domainResolver
        self.evictionTTL = evictionTTL
    }

    /// Chart history is recorded at 1 Hz, so a 5-second bucket always spans
    /// exactly 5 samples regardless of the sampling interval.
    public var samplesPerBucket: Int { 5 }

    public func start() {
        guard tickTask == nil else { return }
        // A fresh session restarts the delta baseline: without this, a long
        // stop() gap would show the whole gap's traffic as one tick's rate.
        lastTotals = nil
        lastTickDate = nil
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runOnce()
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    /// Cancels the tick loop. Residual overlap: one in-flight detached sample
    /// is not awaited, so it may run to completion concurrently with the next
    /// tick's sample — a data race on the same non-thread-safe Sampler (shared
    /// FlowSessionTracker) plus duplicate subprocesses. Full closure is M3.
    public func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// One sampling tick. Public for tests.
    public func runOnce() async {
        guard !Task.isCancelled else { return }
        let sampler = self.sampler   // read on main actor; Sampler is @unchecked Sendable
        let events: [FlowEvent]
        do {
            // Detached task is unstructured and unreferenced: if sample()
            // hangs, cancellation cannot interrupt it — a zombie task that
            // runs to completion. Accepted M3 residual.
            events = try await Task.detached(priority: .utility) { try sampler.sample() }.value
        } catch {
            return   // sampling failure: keep last-known state; retry next tick
        }
        guard !Task.isCancelled else { return }
        apply(events)
        updateThroughput(now: Date())
        let domains = await enrichDomains(for: events)
        // Persistence is best-effort and off the main actor: a failing ingest
        // (disk full, schema mismatch) must never break the live loop. The
        // detached task is unstructured (accepted residual, like sampling).
        if let database {
            let db = database
            let eventsToPersist = events
            let domainsToPersist = domains.domains
            Task.detached(priority: .utility) {
                try? db.ingest(eventsToPersist, domains: domainsToPersist)
            }
        }
        // Operation observer: forward this tick's flow opens/closes and the
        // DNS resolutions just produced by enrichment. Runs on the main actor.
        if let operationSink {
            var opEvents: [OperationEvent] = []
            let now = Date()
            for event in events {
                switch event {
                case .flowOpened(let opened):
                    guard let process = opened.process else { continue }
                    opEvents.append(.connection(
                        opened: true, date: now,
                        process: process.executablePath.split(separator: "/").last.map(String.init) ?? "?",
                        executablePath: process.executablePath,
                        remote: opened.remote, interface: opened.interface,
                        transport: opened.transport, bytes: opened.bytesSent + opened.bytesReceived))
                case .flowClosed(let closed):
                    if let index = flows.firstIndex(where: { $0.flowID == closed.flowID }) {
                        let flow = flows[index]
                        opEvents.append(.connection(
                            opened: false, date: now,
                            process: flow.processName,
                            executablePath: flow.executablePath,
                            remote: flow.remote, interface: flow.interface,
                            transport: flow.transport, bytes: flow.bytesSent + flow.bytesReceived))
                    }
                case .flowUpdated:
                    break
                }
            }
            for resolution in resolutionEvents.suffix(domains.appended) {
                opEvents.append(.dns(date: resolution.date, process: resolution.processName,
                                     domain: resolution.domain ?? "?", ip: resolution.ip))
            }
            if !opEvents.isEmpty {
                operationSink(opEvents)
            }
        }
    }

    /// Resolves domain evidence for every opened flow's remote IP and stamps
    /// it onto the matching live rows. Cached per IP, so steady-state ticks
    /// do not touch the network.
    private func enrichDomains(for events: [FlowEvent]) async -> (domains: [UUID: DomainCandidate], appended: Int) {
        var result: [UUID: DomainCandidate] = [:]
        var appended = 0
        let opened = events.compactMap { event -> FlowEvent.FlowOpened? in
            guard case .flowOpened(let opened) = event else { return nil }
            return opened
        }
        for flow in opened {
            let candidate = await domainResolver.candidate(for: flow.remote.address.text)
            let processName = flow.process?.executablePath.split(separator: "/").last.map(String.init) ?? "?"
            resolutionEvents.append(ResolutionEvent(
                date: Date(), ip: flow.remote.address.text,
                domain: candidate?.domain,
                confidence: candidate?.confidence,
                source: candidate?.source.rawValue,
                processName: processName))
            appended += 1
            if resolutionEvents.count > 200 {
                resolutionEvents.removeFirst(resolutionEvents.count - 200)
            }
            guard let candidate else { continue }
            result[flow.flowID] = candidate
            if let index = flows.firstIndex(where: { $0.flowID == flow.flowID }) {
                flows[index].remoteDomain = candidate.domain
                flows[index].remoteDomainConfidence = candidate.confidence
            }
        }
        return (domains: result, appended: appended)
    }

    private func apply(_ events: [FlowEvent]) {
        for event in events {
            switch event {
            case .flowOpened(let opened):
                guard let process = opened.process else { continue }
                flows.removeAll { $0.flowID == opened.flowID }
                // A reopen after a close carries the connection's CUMULATIVE
                // bytes — drop the closed predecessor so its stale counters
                // don't inflate the totals (and poison one throughput sample).
                let removed = flows.filter { flow in
                    !flow.isActive
                        && flow.pid == opened.pid
                        && flow.transport == opened.transport
                        && flow.local == opened.local
                        && flow.remote == opened.remote
                }
                removedBaseline.sent += removed.reduce(0) { $0 + $1.bytesSent }
                removedBaseline.received += removed.reduce(0) { $0 + $1.bytesReceived }
                flows.removeAll { flow in
                    !flow.isActive
                        && flow.pid == opened.pid
                        && flow.transport == opened.transport
                        && flow.local == opened.local
                        && flow.remote == opened.remote
                }
                // the opening counters are cumulative: baseline, not traffic
                openedBaseline.sent += opened.bytesSent
                openedBaseline.received += opened.bytesReceived
                flows.append(LiveFlow(
                    flowID: opened.flowID, pid: opened.pid,
                    processName: process.executablePath.split(separator: "/").last.map(String.init) ?? "?",
                    executablePath: process.executablePath,
                    bundleIdentifier: process.bundleIdentifier,
                    transport: opened.transport,
                    local: opened.local, remote: opened.remote,
                    interface: opened.interface,
                    startedAt: opened.startedAt,
                    bytesSent: opened.bytesSent, bytesReceived: opened.bytesReceived,
                    isActive: true))
            case .flowUpdated(let counters):
                guard let index = flows.firstIndex(where: { $0.flowID == counters.flowID }) else { continue }
                flows[index].bytesSent = counters.bytesSent
                flows[index].bytesReceived = counters.bytesReceived
            case .flowClosed(let closed):
                guard let index = flows.firstIndex(where: { $0.flowID == closed.flowID }) else { continue }
                flows[index].isActive = false
                flows[index].endedAt = closed.endedAt
            }
        }
        evictClosedFlows(now: Date())
    }

    /// Drops closed flows older than the eviction TTL so long-running sessions
    /// don't grow the live table forever.
    private func evictClosedFlows(now: Date) {
        guard evictionTTL >= 0 else { return }
        flows.removeAll { flow in
            guard !flow.isActive, let endedAt = flow.endedAt else { return false }
            return now.timeIntervalSince(endedAt) > evictionTTL
        }
    }

    private func updateThroughput(now: Date) {
        let sent = flows.reduce(UInt64(0)) { $0 + $1.bytesSent }
        let received = flows.reduce(UInt64(0)) { $0 + $1.bytesReceived }
        // rate deltas exclude baselines: opened flows' cumulative counters and
        // removed predecessors' stale counters are both subtracted
        let trafficSent = sent >= openedBaseline.sent ? sent - openedBaseline.sent : 0
        let trafficReceived = received >= openedBaseline.received
            ? received - openedBaseline.received : 0
        if let last = lastTotals, let lastDate = lastTickDate {
            if sent != last.sent || received != last.received {
                // counters moved (nettop refresh): report the delta over real
                // elapsed time; frozen counters keep the previous rate
                let elapsed = now.timeIntervalSince(lastDate)
                if elapsed > 0 {
                    let lastSent = last.sent >= removedBaseline.sent
                        ? last.sent - removedBaseline.sent : 0
                    let lastReceived = last.received >= removedBaseline.received
                        ? last.received - removedBaseline.received : 0
                    let down = trafficReceived >= lastReceived
                        ? Double(trafficReceived - lastReceived) / elapsed : 0
                    let up = trafficSent >= lastSent
                        ? Double(trafficSent - lastSent) / elapsed : 0
                    throughput = Throughput(bytesPerSecondDown: down, bytesPerSecondUp: up)
                }
                lastTotals = (sent, received)
                lastTickDate = now
                lastCounterChangeDate = now
            }
        } else {
            lastTotals = (sent, received)
            lastTickDate = now   // first observation: baseline only, no rate yet
        }
        // Idle decay: counters stopped moving (no traffic for a while) — the
        // last rate must not linger forever.
        if let lastChange = lastCounterChangeDate,
           now.timeIntervalSince(lastChange) > idleTimeout,
           throughput != .zero {
            throughput = .zero
        }
        openedBaseline = (0, 0)
        removedBaseline = (0, 0)
        // Chart history at 1 Hz: the live bar steps once per second even when
        // sampling runs faster. The meter follows counter changes (~1 Hz).
        if ticksUntilHistorySample <= 1 {
            ticksUntilHistorySample = max(1, Int((1.0 / interval).rounded()))
            throughputHistory.append(ThroughputSample(
                date: now, bytesPerSecondDown: throughput.bytesPerSecondDown,
                bytesPerSecondUp: throughput.bytesPerSecondUp))
            if throughputHistory.count > historyCapacity {
                throughputHistory.removeFirst(throughputHistory.count - historyCapacity)
            }
        } else {
            ticksUntilHistorySample -= 1
        }
    }
}

/// One per-tick rate sample for the traffic chart.
public struct ThroughputSample: Equatable, Sendable {
    public let date: Date
    public let bytesPerSecondDown: Double
    public let bytesPerSecondUp: Double

    public init(date: Date, bytesPerSecondDown: Double, bytesPerSecondUp: Double) {
        self.date = date
        self.bytesPerSecondDown = bytesPerSecondDown
        self.bytesPerSecondUp = bytesPerSecondUp
    }
}

/// A real domain-resolution outcome (reverse DNS evidence) observed while
/// enriching a flow. Drives DNS Activity and the Overview events.
public struct ResolutionEvent: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public let date: Date
    public let ip: String
    public let domain: String?
    public let confidence: Double?
    public let source: String?
    public let processName: String

    public init(date: Date, ip: String, domain: String?, confidence: Double?,
                source: String?, processName: String) {
        self.date = date
        self.ip = ip
        self.domain = domain
        self.confidence = confidence
        self.source = source
        self.processName = processName
    }
}

/// Current network rate as seen by the last sampling tick.
public struct Throughput: Equatable, Sendable {
    public var bytesPerSecondDown: Double
    public var bytesPerSecondUp: Double

    public init(bytesPerSecondDown: Double, bytesPerSecondUp: Double) {
        self.bytesPerSecondDown = bytesPerSecondDown
        self.bytesPerSecondUp = bytesPerSecondUp
    }

    public static let zero = Throughput(bytesPerSecondDown: 0, bytesPerSecondUp: 0)
}

public struct LiveFlow: Identifiable, Equatable {
    public let flowID: UUID
    public let pid: Int32
    public let processName: String
    public let executablePath: String
    public let bundleIdentifier: String?
    public let transport: TransportProtocol
    public let local: NetworkEndpoint
    public let remote: NetworkEndpoint
    public let interface: String
    public let startedAt: Date
    public var bytesSent: UInt64
    public var bytesReceived: UInt64
    public var isActive: Bool
    public var endedAt: Date?
    public var remoteDomain: String?
    public var remoteDomainConfidence: Double?

    public var id: UUID { flowID }
}
