import Foundation
import FlowModel
import FlowSource
import Persistence

/// Live view over the current observation: holds sampled flows on the main
/// actor, applies FlowEvents tick by tick, and exposes a search filter.
@MainActor
public final class LiveConnectionsModel: ObservableObject {
    @Published public private(set) var flows: [LiveFlow] = []
    @Published public var searchText: String = ""

    /// Optional history sink: when set, every tick's events are also persisted
    /// so the live session shows up in the History window. nil in contexts
    /// with no database (CLI-free tests).
    private let database: FlowDatabase?

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
    private let interval: TimeInterval

    public init(sampler: Sampler, database: FlowDatabase? = nil, interval: TimeInterval = 1.0) {
        self.sampler = sampler
        self.database = database
        self.interval = interval
    }

    public func start() {
        guard tickTask == nil else { return }
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
        // Persistence is best-effort: a failing ingest (disk full, schema
        // mismatch) must never break the live loop — swallow like sampling errors.
        if let database {
            try? database.ingest(events)
        }
    }

    private func apply(_ events: [FlowEvent]) {
        for event in events {
            switch event {
            case .flowOpened(let opened):
                guard let process = opened.process else { continue }
                flows.removeAll { $0.flowID == opened.flowID }
                flows.append(LiveFlow(
                    flowID: opened.flowID, pid: opened.pid,
                    processName: process.executablePath.split(separator: "/").last.map(String.init) ?? "?",
                    executablePath: process.executablePath,
                    bundleIdentifier: process.bundleIdentifier,
                    transport: opened.transport,
                    local: opened.local, remote: opened.remote,
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
    }
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
    public let startedAt: Date
    public var bytesSent: UInt64
    public var bytesReceived: UInt64
    public var isActive: Bool
    public var endedAt: Date?

    public var id: UUID { flowID }
}
