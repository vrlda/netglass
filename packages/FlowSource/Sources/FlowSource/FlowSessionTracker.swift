import Foundation
import FlowModel

// Call from the polling run loop only; not thread-safe. Revisit if callers become concurrent (M2+).
public final class FlowSessionTracker: @unchecked Sendable {
    private struct SessionKey: Hashable {
        let pid: Int32
        let transport: TransportProtocol
        let local: NetworkEndpoint
        let remote: NetworkEndpoint
    }

    private struct FlowSession: Equatable {
        let flowID: UUID
        var lastBytesSent: UInt64
        var lastBytesReceived: UInt64
        var executablePath: String?
        var misses: Int
    }

    private let now: @Sendable () -> Date
    private var sessions: [SessionKey: FlowSession] = [:]

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func ingest(
        _ rows: [NettopRow],
        identityForPID: (Int32) -> ProcessIdentity?
    ) -> [FlowEvent] {
        var events: [FlowEvent] = []
        var seen: Set<SessionKey> = []
        let currentTime = now()

        var resolvedPIDs: Set<Int32> = []
        var identities: [Int32: ProcessIdentity?] = [:]
        for row in rows {
            guard let pid = row.pid, !resolvedPIDs.contains(pid) else { continue }
            resolvedPIDs.insert(pid)
            identities[pid] = identityForPID(pid)
        }

        for row in rows {
            guard let pid = row.pid,
                  let local = row.local,
                  let remote = row.remote,
                  let transport = row.transport else { continue }

            let key = SessionKey(pid: pid, transport: transport, local: local, remote: remote)
            seen.insert(key)
            let identity = identities[pid] ?? nil
            let path = identity?.executablePath

            if let session = sessions[key] {
                guard let bytesOut = row.bytesOut, let bytesIn = row.bytesIn else {
                    // no counter info this sample; keep session, emit nothing
                    sessions[key] = FlowSession(flowID: session.flowID,
                                                lastBytesSent: session.lastBytesSent,
                                                lastBytesReceived: session.lastBytesReceived,
                                                executablePath: session.executablePath, misses: 0)
                    continue
                }
                let identityChanged: Bool
                if let oldPath = session.executablePath, let newPath = path {
                    identityChanged = oldPath != newPath
                } else {
                    identityChanged = false
                }
                if identityChanged || hasCounterReset(row, session) {
                    events.append(.flowClosed(FlowEvent.FlowClosed(flowID: session.flowID, endedAt: currentTime)))
                    let fresh = makeSession(pid: pid, transport: transport, local: local,
                                            remote: remote, path: path, row: row, at: currentTime)
                    sessions[key] = fresh
                    events.append(.flowOpened(FlowEvent.FlowOpened(
                        flowID: fresh.flowID, process: identity, pid: pid,
                        transport: transport, local: local, remote: remote,
                        startedAt: currentTime,
                        bytesSent: fresh.lastBytesSent, bytesReceived: fresh.lastBytesReceived)))
                    continue
                }
                if bytesOut != session.lastBytesSent || bytesIn != session.lastBytesReceived {
                    events.append(.flowUpdated(FlowEvent.FlowCounters(
                        flowID: session.flowID,
                        bytesSent: bytesOut,
                        bytesReceived: bytesIn,
                        observedAt: currentTime)))
                }
                sessions[key] = FlowSession(
                    flowID: session.flowID,
                    lastBytesSent: bytesOut,
                    lastBytesReceived: bytesIn,
                    executablePath: path,
                    misses: 0)
            } else {
                let fresh = makeSession(pid: pid, transport: transport, local: local,
                                        remote: remote, path: path, row: row, at: currentTime)
                sessions[key] = fresh
                events.append(.flowOpened(FlowEvent.FlowOpened(
                    flowID: fresh.flowID, process: identity, pid: pid,
                    transport: transport, local: local, remote: remote,
                    startedAt: currentTime,
                    bytesSent: fresh.lastBytesSent, bytesReceived: fresh.lastBytesReceived)))
            }
        }

        for (key, session) in sessions where !seen.contains(key) {
            let misses = session.misses + 1
            if misses >= 3 {
                events.append(.flowClosed(FlowEvent.FlowClosed(flowID: session.flowID, endedAt: currentTime)))
                sessions.removeValue(forKey: key)
            } else {
                sessions[key] = FlowSession(flowID: session.flowID,
                                            lastBytesSent: session.lastBytesSent,
                                            lastBytesReceived: session.lastBytesReceived,
                                            executablePath: session.executablePath,
                                            misses: misses)
            }
        }
        return events
    }

    private func hasCounterReset(_ row: NettopRow, _ session: FlowSession) -> Bool {
        guard let bytesOut = row.bytesOut, let bytesIn = row.bytesIn else { return false }
        return bytesOut < session.lastBytesSent || bytesIn < session.lastBytesReceived
    }

    private func makeSession(pid: Int32, transport: TransportProtocol,
                             local: NetworkEndpoint, remote: NetworkEndpoint,
                             path: String?, row: NettopRow, at date: Date) -> FlowSession {
        FlowSession(flowID: UUID(), lastBytesSent: row.bytesOut ?? 0,
                    lastBytesReceived: row.bytesIn ?? 0,
                    executablePath: path, misses: 0)
    }
}
