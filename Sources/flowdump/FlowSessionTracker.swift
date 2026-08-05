import Foundation
import FlowModel

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

        for row in rows {
            guard let pid = row.pid,
                  let local = row.local,
                  let remote = row.remote,
                  let transport = row.transport else { continue }

            let key = SessionKey(pid: pid, transport: transport, local: local, remote: remote)
            seen.insert(key)
            let identity = identityForPID(pid)
            let path = identity?.executablePath

            if let session = sessions[key] {
                if session.executablePath != path || hasCounterReset(row, session) {
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
                if row.bytesOut ?? 0 != session.lastBytesSent
                    || row.bytesIn ?? 0 != session.lastBytesReceived {
                    events.append(.flowUpdated(FlowEvent.FlowCounters(
                        flowID: session.flowID,
                        bytesSent: row.bytesOut ?? 0,
                        bytesReceived: row.bytesIn ?? 0,
                        observedAt: currentTime)))
                }
                sessions[key] = FlowSession(
                    flowID: session.flowID,
                    lastBytesSent: row.bytesOut ?? 0,
                    lastBytesReceived: row.bytesIn ?? 0,
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
        (row.bytesOut ?? 0) < session.lastBytesSent
            || (row.bytesIn ?? 0) < session.lastBytesReceived
    }

    private func makeSession(pid: Int32, transport: TransportProtocol,
                             local: NetworkEndpoint, remote: NetworkEndpoint,
                             path: String?, row: NettopRow, at date: Date) -> FlowSession {
        FlowSession(flowID: UUID(), lastBytesSent: row.bytesOut ?? 0,
                    lastBytesReceived: row.bytesIn ?? 0,
                    executablePath: path, misses: 0)
    }
}
