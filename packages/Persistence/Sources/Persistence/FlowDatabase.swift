import Foundation
import FlowModel

public struct StoredFlow: Equatable, Sendable, Codable {
    public let flowID: UUID
    public let processPath: String
    public let bundleIdentifier: String?
    public let transport: TransportProtocol
    public let localAddress: IPAddress
    public let localPort: UInt16
    public let remoteAddress: IPAddress
    public let remotePort: UInt16
    public let startedAt: Date
    public let endedAt: Date?
    public let bytesSent: UInt64
    public let bytesReceived: UInt64
}

extension StoredFlow: Identifiable {
    public var id: UUID { flowID }
}

public final class FlowDatabase: @unchecked Sendable {
    private let db: Database

    public init(path: String) throws {
        db = try Database(path: path)
        try db.exec(Schema.create)
    }

    public func ingest(_ events: [FlowEvent]) throws {
        try db.exec("BEGIN")
        do {
            for event in events {
                switch event {
                case .flowOpened(let opened):
                    try insert(opened)
                case .flowUpdated(let counters):
                    try db.exec(
                        "UPDATE flows SET bytes_sent = ?, bytes_received = ? WHERE id = ? AND ended_at IS NULL",
                        [.int(Int64(counters.bytesSent)), .int(Int64(counters.bytesReceived)), .text(counters.flowID.uuidString)])
                case .flowClosed(let closed):
                    try db.exec(
                        "UPDATE flows SET ended_at = ? WHERE id = ?",
                        [.double(closed.endedAt.timeIntervalSince1970), .text(closed.flowID.uuidString)])
                }
            }
            try db.exec("COMMIT")
        } catch {
            try? db.exec("ROLLBACK")
            throw error
        }
    }

    public func flows(processPath: String? = nil,
                      remoteAddress: IPAddress? = nil,
                      remotePort: UInt16? = nil,
                      limit: Int = 1000) throws -> [StoredFlow] {
        var sql = """
        SELECT f.id, p.executable_path, p.bundle_identifier, f.transport,
               f.local_address, f.local_port, f.remote_address, f.remote_port,
               f.started_at, f.ended_at, f.bytes_sent, f.bytes_received
        FROM flows f JOIN processes p ON p.id = f.process_id
        """
        var bindings: [SQLBinding] = []
        var clauses: [String] = []
        if let processPath {
            clauses.append("p.executable_path = ?")
            bindings.append(.text(processPath))
        }
        if let remoteAddress {
            clauses.append("f.remote_address = ?")
            bindings.append(.blob(remoteAddress.bytes))
        }
        if let remotePort {
            clauses.append("f.remote_port = ?")
            bindings.append(.int(Int64(remotePort)))
        }
        if !clauses.isEmpty {
            sql += " WHERE " + clauses.joined(separator: " AND ")
        }
        sql += " ORDER BY f.started_at DESC LIMIT \(limit)"

        let statement = try db.prepare(sql)
        try statement.bind(bindings)
        var result: [StoredFlow] = []
        while try statement.step() {
            guard let flowID = UUID(uuidString: statement.text(0)),
                  let transport = TransportProtocol(rawValue: statement.text(3)),
                  let localAddress = IPAddress(statement.blob(4)),
                  let remoteAddress = IPAddress(statement.blob(6)) else { continue }
            result.append(StoredFlow(
                flowID: flowID,
                processPath: statement.text(1),
                bundleIdentifier: statement.text(2).isEmpty ? nil : statement.text(2),
                transport: transport,
                localAddress: localAddress,
                localPort: UInt16(statement.int64(5)),
                remoteAddress: remoteAddress,
                remotePort: UInt16(statement.int64(7)),
                startedAt: Date(timeIntervalSince1970: statement.double(8)),
                endedAt: statement.isNull(9) ? nil : Date(timeIntervalSince1970: statement.double(9)),
                bytesSent: UInt64(statement.int64(10)),
                bytesReceived: UInt64(statement.int64(11))))
        }
        statement.close()
        return result
    }

    public func processCount() throws -> Int64 {
        let statement = try db.prepare("SELECT COUNT(*) FROM processes")
        _ = try statement.step()
        let count = statement.int64(0)
        statement.close()
        return count
    }

    /// Closes any flows still marked open — called at app bootstrap so a fresh
    /// observation session doesn't leave the previous session's flows dangling.
    public func closeOrphanedFlows(endedAt: Date) throws {
        try db.exec("UPDATE flows SET ended_at = ? WHERE ended_at IS NULL",
                    [.double(endedAt.timeIntervalSince1970)])
    }

    public func close() { db.close() }

    private func insert(_ opened: FlowEvent.FlowOpened) throws {
        guard let process = opened.process else { return }
        let bundleID = process.bundleIdentifier ?? ""
        try db.exec(
            "INSERT OR IGNORE INTO processes(executable_path, bundle_identifier) VALUES (?, ?)",
            [.text(process.executablePath), .text(bundleID)])
        let statement = try db.prepare(
            "SELECT id FROM processes WHERE executable_path = ? AND bundle_identifier = ?")
        try statement.bind([.text(process.executablePath), .text(bundleID)])
        guard try statement.step() else {
            statement.close()
            throw DatabaseError.sqlite("process row missing after insert")
        }
        let processRowID = statement.int64(0)
        statement.close()
        try db.exec(
            "INSERT OR IGNORE INTO flows(id, process_id, transport, local_address, local_port, remote_address, remote_port, started_at, bytes_sent, bytes_received) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [.text(opened.flowID.uuidString), .int(processRowID),
             .text(opened.transport.rawValue), .blob(opened.local.address.bytes),
             .int(Int64(opened.local.port)), .blob(opened.remote.address.bytes),
             .int(Int64(opened.remote.port)), .double(opened.startedAt.timeIntervalSince1970),
             .int(Int64(opened.bytesSent)), .int(Int64(opened.bytesReceived))])
    }
}
